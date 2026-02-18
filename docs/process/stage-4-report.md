# Stage 4 Report (Phase 2 Logic)

## Scope
Implement Phase 2 backend logic: adaptive meeting memory updates, replay mode for offline trigger diagnostics, diarization quality gates, and multi-profile loading.

## Delivered
1. Adaptive meeting memory updater:
   - `backend/meeting_memory.py`
   - event-driven update policy (`high score`, `alert severity`, `10 min timer`) + mandatory finalize on meeting end.
2. Diarization quality gates:
   - `backend/diarization_gate.py`
   - confidence threshold gate, thrashing detection (>5 speaker switches / 10s), temporary cooldown downgrade to `THEM`.
3. Replay mode (offline trigger debugging):
   - `backend/replay_mode.py`
   - loads exported session JSON, recomputes trigger decisions, outputs per-segment reason (`ok`, `threshold_miss`, `insufficient_context`, `duplicate`, `cooldown`).
4. Multi-profile loader for all 6 profiles:
   - `backend/profile_loader.py`
   - `load_profile(profile_id)`, `list_profiles()`.
5. Orchestrator integration:
   - `backend/orchestrator.py`
   - diarization gate applied before scoring,
   - transcript history tracked,
   - adaptive meeting memory updated during session,
   - finalized memory snapshot exported on session end.
6. Runtime integration:
   - `backend/main.py`
   - session start now accepts profile id,
   - final export uses orchestrator memory snapshot.
7. Replay/stress tooling updates:
   - `backend/tests/stress_test.py` now accepts profile id.

## Verification
- Python compile check:
  - `python3 -m py_compile ...` (pass)
- Test suite:
  - `PYTHONPATH=backend pytest -q backend/tests` -> `11 passed`
- Replay CLI smoke run:
  - `PYTHONPATH=backend python3 backend/replay_mode.py --session /tmp/aimc_replay_input.json --profile negotiation --out /tmp/aimc_replay_output.json`
  - report generated with expected decision row.

## Added tests
- `backend/tests/test_meeting_memory.py`
- `backend/tests/test_diarization_gate.py`
- `backend/tests/test_replay_mode.py`

## Known limitations
1. Semantic/emotion signals are still placeholders in scoring (keyword-first behavior remains default).
2. Full FluidAudio runtime is not wired yet; current diarization gate expects speaker labels from upstream.
3. Swift `swift build/test` remains blocked in this environment (SDK/toolchain mismatch + sandbox cache permissions).
