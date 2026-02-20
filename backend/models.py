from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass
class MicEvent:
    schemaVersion: int
    seq: int
    eventType: str
    timestamp: float
    confidence: float
    duration: float


@dataclass
class TranscriptSegment:
    schemaVersion: int
    seq: int
    utteranceId: str
    isFinal: bool
    speaker: str
    text: str
    tsStart: float
    tsEnd: float
    speakerConfidence: float


@dataclass
class SystemStateEvent:
    schemaVersion: int
    seq: int
    timestamp: float
    batteryLevel: float
    thermalState: str


@dataclass
class AudioLevelEvent:
    schemaVersion: int
    seq: int
    timestamp: float
    micRms: float
    systemRms: float


@dataclass
class SystemAudioChunk:
    """Base64-encoded PCM float32 chunk from system audio (16 kHz mono)."""
    session_id: str
    chunk_index: int
    sample_rate: int
    channels: int
    pcm_base64: str


@dataclass
class RawBufferEntry:
    speaker: str
    text: str
    ts_start: float
    ts_end: float


@dataclass
class InsightCard:
    id: str
    scenario: str
    card_mode: str
    trigger_reason: str
    insight: str
    reply_cautious: str
    reply_confident: str
    severity: str
    timestamp: float
    speaker: str
    agent_name: str = "Оркестратор"
    is_fallback: bool = False
    dismissed: bool = False
    pinned: bool = False
    excluded: bool = False
    source_ts_end: float = 0.0

    def to_wire(self) -> dict:
        return asdict(self)
