"""Post-meeting batch speaker re-diarization using Resemblyzer.

After meeting ends, reprocess the saved system audio WAV file:
1. For each transcript segment, extract the corresponding audio window
2. Compute Resemblyzer embeddings
3. Apply agglomerative clustering (scipy) with silhouette-based cluster selection
4. Reassign speaker labels THEM_A / THEM_B / ... to transcript segments

RAM: ~300 MB peak for a 1-hour meeting.
"""
from __future__ import annotations

import logging
import wave
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

# Lazy-loaded encoder
_encoder = None


def _get_encoder():
    global _encoder
    if _encoder is None:
        from resemblyzer import VoiceEncoder
        _encoder = VoiceEncoder("cpu")
        logger.info("Resemblyzer VoiceEncoder loaded for post-diarization")
    return _encoder


SPEAKER_LABELS = [f"THEM_{chr(ord('A') + i)}" for i in range(8)]


def _load_wav_float32(wav_path: str | Path) -> tuple[np.ndarray, int]:
    """Load a WAV file and return (float32 samples, sample_rate)."""
    with wave.open(str(wav_path), "rb") as wf:
        n_channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        sample_rate = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    if sample_width == 4:
        # float32
        samples = np.frombuffer(raw, dtype=np.float32)
    elif sample_width == 2:
        # int16 -> float32
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    else:
        raise ValueError(f"Unsupported sample width: {sample_width}")

    if n_channels > 1:
        samples = samples.reshape(-1, n_channels).mean(axis=1)

    return samples, sample_rate


def rediarize_session(
    system_audio_path: str | Path,
    transcript: list[dict],
    max_speakers: int = 5,
    min_speakers: int = 2,
) -> tuple[list[dict], dict]:
    """Re-diarize transcript segments using batch Resemblyzer analysis.

    Args:
        system_audio_path: Path to system audio WAV file (16 kHz mono).
        transcript: List of transcript segment dicts with tsStart, tsEnd, speaker fields.
        max_speakers: Maximum number of speakers to detect.
        min_speakers: Minimum number of speakers to detect.

    Returns:
        Tuple of (updated_transcript, metadata_dict).
    """
    audio_path = Path(system_audio_path)
    if not audio_path.exists():
        logger.warning("System audio file not found: %s", audio_path)
        return transcript, {"error": "system_audio_not_found"}

    try:
        audio, sample_rate = _load_wav_float32(audio_path)
    except Exception:
        logger.exception("Failed to load system audio WAV")
        return transcript, {"error": "wav_load_failed"}

    # Filter THEM segments only (we don't re-diarize ME)
    them_indices = []
    them_segments = []
    for i, seg in enumerate(transcript):
        speaker = seg.get("speaker", "")
        if speaker.startswith("THEM"):
            them_indices.append(i)
            them_segments.append(seg)

    if len(them_segments) < 2:
        logger.info("Too few THEM segments (%d) for re-diarization", len(them_segments))
        return transcript, {"skipped": True, "reason": "too_few_segments"}

    # Compute embeddings for each segment
    encoder = _get_encoder()
    embeddings = []
    valid_mask = []

    for seg in them_segments:
        ts_start = seg.get("tsStart", 0.0)
        ts_end = seg.get("tsEnd", 0.0)
        start_sample = max(0, int(ts_start * sample_rate))
        end_sample = min(len(audio), int(ts_end * sample_rate))

        if end_sample - start_sample < int(sample_rate * 0.3):
            # Segment too short for reliable embedding
            embeddings.append(np.zeros(256))
            valid_mask.append(False)
            continue

        segment_audio = audio[start_sample:end_sample]
        try:
            emb = encoder.embed_utterance(segment_audio)
            norm = np.linalg.norm(emb)
            if norm > 1e-8:
                emb = emb / norm
            embeddings.append(emb)
            valid_mask.append(True)
        except Exception:
            embeddings.append(np.zeros(256))
            valid_mask.append(False)

    embeddings_array = np.array(embeddings)
    valid_embeddings = embeddings_array[valid_mask]

    if len(valid_embeddings) < 2:
        logger.info("Too few valid embeddings (%d) for clustering", len(valid_embeddings))
        return transcript, {"skipped": True, "reason": "too_few_valid_embeddings"}

    # Agglomerative clustering with silhouette score to pick optimal k
    try:
        from scipy.cluster.hierarchy import fcluster, linkage
        from sklearn.metrics import silhouette_score
    except ImportError:
        logger.warning("scipy/sklearn not available for post-diarization")
        return transcript, {"error": "missing_dependencies"}

    # Compute linkage on valid embeddings
    Z = linkage(valid_embeddings, method="ward")

    best_k = min_speakers
    best_score = -1.0

    for k in range(min_speakers, min(max_speakers + 1, len(valid_embeddings))):
        labels = fcluster(Z, t=k, criterion="maxclust")
        if len(set(labels)) < 2:
            continue
        score = silhouette_score(valid_embeddings, labels)
        if score > best_score:
            best_score = score
            best_k = k

    final_labels = fcluster(Z, t=best_k, criterion="maxclust")

    # Map cluster IDs to THEM_A, THEM_B, ...
    cluster_to_label = {}
    label_idx = 0
    for cl in final_labels:
        if cl not in cluster_to_label:
            cluster_to_label[cl] = SPEAKER_LABELS[min(label_idx, len(SPEAKER_LABELS) - 1)]
            label_idx += 1

    # Apply labels back to transcript
    updated_transcript = list(transcript)
    valid_idx = 0
    for i, is_valid in enumerate(valid_mask):
        original_idx = them_indices[i]
        if is_valid:
            new_label = cluster_to_label[final_labels[valid_idx]]
            updated_transcript[original_idx] = dict(updated_transcript[original_idx])
            updated_transcript[original_idx]["speaker"] = new_label
            valid_idx += 1
        # Invalid segments keep their original THEM/THEM_X label

    metadata = {
        "speaker_count": best_k,
        "silhouette_score": round(float(best_score), 3),
        "total_them_segments": len(them_segments),
        "valid_embeddings": int(sum(valid_mask)),
    }

    logger.info(
        "Post-diarization complete: %d speakers, silhouette=%.3f, %d/%d segments",
        best_k, best_score, sum(valid_mask), len(them_segments),
    )
    return updated_transcript, metadata
