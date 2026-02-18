import time

from diarization_gate import DiarizationGate
from models import TranscriptSegment


def seg(speaker: str, conf: float = 0.9, seq: int = 1) -> TranscriptSegment:
    return TranscriptSegment(
        schemaVersion=1,
        seq=seq,
        utteranceId=f"u{seq}",
        isFinal=True,
        speaker=speaker,
        text="x",
        tsStart=0,
        tsEnd=float(seq),
        speakerConfidence=conf,
    )


def test_low_confidence_downgrade_to_them() -> None:
    gate = DiarizationGate()
    assert gate.resolve_speaker(seg("THEM_A", conf=0.5)) == "THEM"


def test_thrashing_disables_temporarily() -> None:
    gate = DiarizationGate()
    for i in range(1, 8):
        speaker = "THEM_A" if i % 2 == 0 else "THEM_B"
        gate.resolve_speaker(seg(speaker, conf=0.95, seq=i))
    # after many rapid switches gate should degrade
    assert gate.resolve_speaker(seg("THEM_A", conf=0.95, seq=99)) == "THEM"
