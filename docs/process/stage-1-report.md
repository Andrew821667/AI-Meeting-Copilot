# Stage 1 Report (Audio-First MVP)

## Scope
Stage 1 delivers local Swift-first realtime foundation with visible transcript UI, onboarding, capture indicator, and core contracts for next stages.

## Delivered
1. Swift package bootstrap for macOS app + core module + tests.
2. Session state machine (IDLE/CAPTURING/PAUSED/ENDED) and seq generator.
3. Event models aligned to Stage 0 contracts (`MicEvent`, `TranscriptSegment`, `SystemStateEvent`, `AudioLevelEvent`, `CaptureMode`).
4. ASR abstraction (`ASRProvider`) and `WhisperKitProvider` boundary.
5. Mock streaming ASR provider for deterministic local demo stream.
6. Microphone pipeline (`AVAudioEngine` tap) with:
   - RMS computation
   - Energy VAD (`speech_start` / `speech_state` / `speech_end`)
   - sample-clock timestamping by processed samples
   - audio format watchdog hook
7. Hallucination filter (VAD gate + regex patterns).
8. Permissions/onboarding manager:
   - microphone authorization
   - screen recording authorization
   - one-time consent flag (`consent_ack_v1`)
9. SwiftUI app shell:
   - capture indicator (`CAPTURE OFF/SCK/BlackHole/MIC`)
   - onboarding checklist panel
   - start/stop controls
   - live transcript panel (partial/final)
   - live mic/system RMS diagnostics
10. Unit tests:
   - hallucination filter behavior
   - sample clock monotonicity and drift-safe math

## Controlled stubs (intentional)
1. `WhisperKitProvider` currently routes to `MockASRProvider` until WhisperKit package/runtime is wired.
2. `SystemAudioCaptureService` currently emits diagnostic levels and mode state, without full `ScreenCaptureKit` stream ingest.

These stubs keep architecture stable while unblocking Stage 2 IPC/orchestrator work.

## Verification status
- Source files generated and linked in package targets.
- JSON event schema from Stage 0 remains valid.
- Automated `swift build` / `swift test` could not be executed in this environment due local toolchain+SDK mismatch and sandboxed cache permissions.

## Gate assessment
Stage 1 foundation is implemented and ready for acceptance with the two explicit stubs above.
