# MVP Definition of Done (Stage 0)

## Functional
- Swift captures microphone and system audio.
- Whisper provider emits partial/final transcript segments.
- Python trigger path works with keyword scoring and profile threshold.
- Card appears only in pause window after counterpart utterance.
- Fallback card is shown on realtime API timeout.

## UX behavior
- Active card collapses when user starts speaking.
- Pinned card does not collapse on user speech.
- Last 3 cards are visible in sidebar.
- Panic hotkey captures last context window and generates manual card.

## Safety/compliance
- One-time user acknowledgement is collected and stored.
- Capture status indicator is always visible (SCK/BlackHole/MIC/OFF).
- No in-meeting popups/toasts are used.

## Performance
- SLO targets in docs/telemetry/slo-and-metrics.md are met.
- 60+ minute session completes without crash.
- Bounded queues and backpressure policy verified.

## Observability
- Session export includes transcript, cards, memory, and metrics.
- Replay mode can explain trigger/no-trigger outcomes offline.
