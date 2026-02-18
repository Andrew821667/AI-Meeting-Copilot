# Stage 3 Report (Telemetry, Export, Postfactum)

## Scope
Deliver observability and session finalization layer: telemetry metrics, JSON export, postfactum markdown report, and lifecycle controls (pause/resume/end).

## Delivered
1. Backend telemetry subsystem:
   - `backend/telemetry.py`
   - tracks card counters, fallback/timeout rates, LLM latency, queue max len,
     audio source suspect, thermal serious duration, and card latency percentiles.
2. Session lifecycle control in backend (`start/pause/resume/end`):
   - `backend/main.py`
   - `session_control` handling + `session_ack` and `session_summary` responses.
3. JSON session export:
   - `backend/session_export.py`
   - output to `exports/<session_id>.json` with transcript/cards/memory/metrics/settings.
4. Postfactum report generation:
   - `backend/postfactum.py`
   - output to `exports/<session_id>-report.md`.
5. Orchestrator telemetry integration and pause/resume behavior:
   - `backend/orchestrator.py`
   - queue pressure tracking, LLM timeout accounting, audio/system state ingestion.
6. Swift integration updates:
   - pause/resume controls in UI and VM lifecycle (`MainViewModel`, `ContentView`)
   - periodic `system_state` events (30s + thermal change)
   - throttled `audio_level` events (1s)
   - session summary receive/display (export/report paths)
   - files: `MainViewModel.swift`, `ContentView.swift`, `UDSEventClient.swift`, `SessionSummary.swift`.
7. Stress tooling:
   - `backend/tests/stress_test.py` for long-run synthetic load and metrics report.

## Verification
- Python static compile check:
  - `python3 -m py_compile ...` (pass)
- Unit tests:
  - `PYTHONPATH=backend pytest -q backend/tests` -> `6 passed`
- Synthetic stress run:
  - `PYTHONPATH=backend python3 backend/tests/stress_test.py --duration-min 1 --inject-timeouts 0.05 --report /tmp/aimc_stress_report.json`
  - produced `cards_generated: 50`, `llm_timeout_rate: 0.04`, `pending_queue_len: 0`.

## Known limitations
1. Swift toolchain/SDK mismatch in this environment still blocks `swift build/test` execution.
2. WhisperKit runtime is still mock-backed.
3. System audio capture still uses Stage-2 diagnostic stub (full SCK ingest pending).
