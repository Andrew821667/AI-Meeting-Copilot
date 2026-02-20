"""Online speaker diarizer using Resemblyzer d-vectors + energy VAD.

Accepts 2-second PCM chunks (16 kHz mono float32) from system audio,
detects speech via energy VAD, computes speaker embeddings, and assigns
labels THEM_A / THEM_B / ... (up to MAX_SPEAKERS).

Thread-safe: all public methods acquire a lock.
"""
from __future__ import annotations

import logging
import threading
from collections import deque
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

# Lazy-loaded Resemblyzer encoder (expensive import, ~50 MB model)
_encoder = None
_encoder_lock = threading.Lock()


def _get_encoder():
    global _encoder
    if _encoder is None:
        with _encoder_lock:
            if _encoder is None:
                from resemblyzer import VoiceEncoder
                _encoder = VoiceEncoder("cpu")
                logger.info("Resemblyzer VoiceEncoder loaded")
    return _encoder


# Speaker labels
SPEAKER_LABELS = [f"THEM_{chr(ord('A') + i)}" for i in range(8)]
MAX_SPEAKERS = 5

# VAD parameters
ENERGY_THRESHOLD_DB = -35.0  # dBFS threshold for speech detection
MIN_SPEECH_DURATION_SEC = 0.3


class SpeakerCentroid:
    """Running centroid for a speaker with exponential moving average."""

    def __init__(self, embedding: np.ndarray, label: str, alpha: float = 0.3):
        self.embedding = embedding.copy()
        self.label = label
        self.count = 1
        self.alpha = alpha

    def update(self, new_embedding: np.ndarray) -> None:
        self.embedding = self.alpha * new_embedding + (1 - self.alpha) * self.embedding
        self.embedding /= np.linalg.norm(self.embedding) + 1e-8
        self.count += 1


class OnlineSpeakerDiarizer:
    """Online speaker diarizer for system audio stream.

    Usage:
        diarizer = OnlineSpeakerDiarizer()
        label = diarizer.process_chunk(pcm_float32_16khz)  # -> "THEM_A" | None
    """

    def __init__(
        self,
        similarity_threshold: float = 0.75,
        max_speakers: int = MAX_SPEAKERS,
        sample_rate: int = 16000,
    ):
        self.similarity_threshold = similarity_threshold
        self.max_speakers = max_speakers
        self.sample_rate = sample_rate
        self.centroids: list[SpeakerCentroid] = []
        self.last_label: str = SPEAKER_LABELS[0]
        self._lock = threading.Lock()
        self._recent_embeddings: deque[tuple[str, np.ndarray]] = deque(maxlen=100)

    def process_chunk(self, pcm: np.ndarray) -> Optional[str]:
        """Process a PCM chunk and return speaker label or None if no speech.

        Args:
            pcm: float32 numpy array, 16 kHz mono, typically 2 seconds (~32000 samples).

        Returns:
            Speaker label string ("THEM_A", "THEM_B", ...) or None if no speech detected.
        """
        with self._lock:
            return self._process_chunk_locked(pcm)

    def _process_chunk_locked(self, pcm: np.ndarray) -> Optional[str]:
        if pcm.size < int(self.sample_rate * MIN_SPEECH_DURATION_SEC):
            return None

        # Energy VAD
        speech_segments = self._energy_vad(pcm)
        if not speech_segments:
            return None

        # Extract speech-only audio
        speech_audio = np.concatenate([pcm[start:end] for start, end in speech_segments])
        if speech_audio.size < int(self.sample_rate * MIN_SPEECH_DURATION_SEC):
            return None

        # Compute embedding
        try:
            encoder = _get_encoder()
            embedding = encoder.embed_utterance(speech_audio)
        except Exception:
            logger.exception("Resemblyzer embedding failed")
            return self.last_label

        # Normalize
        norm = np.linalg.norm(embedding)
        if norm < 1e-8:
            return self.last_label
        embedding = embedding / norm

        # Match to existing centroids
        label = self._match_or_create(embedding)
        self.last_label = label
        self._recent_embeddings.append((label, embedding))
        return label

    def _energy_vad(self, pcm: np.ndarray) -> list[tuple[int, int]]:
        """Simple energy-based VAD. Returns list of (start, end) sample indices."""
        frame_size = int(self.sample_rate * 0.025)  # 25ms frames
        hop_size = int(self.sample_rate * 0.010)    # 10ms hop

        segments = []
        speech_start = None
        min_speech_frames = int(MIN_SPEECH_DURATION_SEC / 0.010)

        frame_count = 0
        speech_frame_count = 0

        for i in range(0, len(pcm) - frame_size, hop_size):
            frame = pcm[i : i + frame_size]
            rms = np.sqrt(np.mean(frame ** 2) + 1e-10)
            db = 20 * np.log10(rms + 1e-10)

            if db > ENERGY_THRESHOLD_DB:
                if speech_start is None:
                    speech_start = i
                speech_frame_count += 1
            else:
                if speech_start is not None and speech_frame_count >= min_speech_frames:
                    segments.append((speech_start, i + frame_size))
                speech_start = None
                speech_frame_count = 0
            frame_count += 1

        # Handle trailing speech
        if speech_start is not None and speech_frame_count >= min_speech_frames:
            segments.append((speech_start, len(pcm)))

        return segments

    def _match_or_create(self, embedding: np.ndarray) -> str:
        """Match embedding to existing centroid or create new one."""
        if not self.centroids:
            centroid = SpeakerCentroid(embedding, SPEAKER_LABELS[0])
            self.centroids.append(centroid)
            return centroid.label

        # Find best match
        best_sim = -1.0
        best_idx = -1
        for i, centroid in enumerate(self.centroids):
            sim = float(np.dot(embedding, centroid.embedding))
            if sim > best_sim:
                best_sim = sim
                best_idx = i

        if best_sim >= self.similarity_threshold:
            self.centroids[best_idx].update(embedding)
            return self.centroids[best_idx].label

        # New speaker
        if len(self.centroids) < self.max_speakers:
            label = SPEAKER_LABELS[len(self.centroids)]
            centroid = SpeakerCentroid(embedding, label)
            self.centroids.append(centroid)
            return label

        # Max speakers reached — assign to closest
        self.centroids[best_idx].update(embedding)
        return self.centroids[best_idx].label

    def get_speaker_count(self) -> int:
        """Return current number of identified speakers."""
        with self._lock:
            return len(self.centroids)

    def reset(self) -> None:
        """Reset all speaker centroids."""
        with self._lock:
            self.centroids.clear()
            self._recent_embeddings.clear()
            self.last_label = SPEAKER_LABELS[0]
