# Event Contract (Stage 0)

## Transport contract
- Transport: Unix Domain Socket (primary), localhost-only.
- Timestamp: monotonic seconds since session start.
- Ordering: Python orders by timestamp, not arrival order.
- Idempotency: deduplicate by seq.
- Versioning: every event includes schema_version.

## MicEvent
Fields:
- schema_version: int
- seq: uint64
- event_type: speech_start | speech_end | speech_state
- timestamp: float (monotonic)
- confidence: float [0..1]
- duration: float (required for speech_end, else 0)

## TranscriptSegment
Fields:
- schema_version: int
- seq: uint64
- utterance_id: string (same for partial and final of one utterance)
- is_final: bool
- speaker: THEM | THEM_A | THEM_B
- text: string
- ts_start: float (monotonic)
- ts_end: float (monotonic)
- speaker_confidence: float [0..1]

## SystemStateEvent
Fields:
- schema_version: int
- seq: uint64
- timestamp: float (monotonic)
- battery_level: float [0..1]
- thermal_state: nominal | fair | serious | critical

Behavior:
- emitted every 30s and on thermal state change
- Python disables heavy optional models on serious/critical or battery < 0.2

## AudioLevelEvent
Fields:
- schema_version: int
- seq: uint64
- timestamp: float
- mic_rms: float [0..1]
- system_rms: float [0..1]

Behavior:
- emitted every 1s for UI diagnostics
