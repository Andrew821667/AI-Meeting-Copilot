# Realtime Boundary (Stage 0)

## Purpose
Lock architectural boundaries before implementation.

## Mandatory decisions
1. Swift owns all realtime audio capture and processing.
2. Python owns orchestration and business logic only.
3. Raw PCM never crosses Swift <-> Python boundary.
4. VAD for microphone runs in Swift process near audio capture.
5. ASR is abstracted from day one with provider interface.
6. LLM in-flight cancellation is handled by Python request manager, not by stopping ASR.
7. Degrade gracefully (fallback card, diarization downgrade to THEM, delayed card over dropped card).
8. Event transport is ordered by monotonic timestamps, with seq-based idempotency.

## ASR abstraction contract
Swift side must expose a provider contract equivalent to:
- startStream()
- stopStream()
- reset()
- segments stream with partial and final transcript items

Partial segments are used for speculative scoring only.
Final segments are required for trigger finalization and card display eligibility.

## Session state machine
IDLE -> CAPTURING -> PAUSED -> CAPTURING -> ENDED

Transition rules:
- Start capture: new session_id, seq reset, queues clear, IPC open.
- Pause: stop ASR stream, keep session context.
- Resume: ASR reset + start, keep same session_id.
- End: finalize memory/report, close IPC, flush telemetry.
