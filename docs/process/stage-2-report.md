# Stage 2 Report (Swift <-> Python Orchestrator)

## Scope
Connect Swift realtime events to Python orchestration over Unix Domain Socket and deliver insight card behavior pipeline.

## Delivered
1. Python backend with UDS server:
   - `backend/main.py`
   - line-delimited JSON protocol
   - handlers for `mic_event`, `transcript_segment`, `panic_capture`
2. Trigger orchestration stack:
   - `backend/orchestrator.py`
   - `backend/trigger_scorer.py`
   - `backend/profile_loader.py`
   - `backend/raw_buffer.py`
   - `backend/llm_client.py`
   - `backend/models.py`
3. Implemented Stage-2 logic:
   - 5-minute raw buffer
   - keyword + negative rules scoring
   - cooldown, dedupe, per-window card limits
   - pending queue behavior on overlap
   - fallback card on 3s timeout
   - panic capture for last 30 seconds
4. Swift IPC/process integration:
   - backend process manager (`BackendProcessManager`)
   - UDS client (`UDSEventClient`)
   - event streaming from Swift to Python (mic + transcript)
   - insight card streaming from Python to Swift
5. Swift UI behavior:
   - active card pane with `Pin`, `Copy`, `Close`
   - collapse card on mic speech start (unless pinned)
   - recent 3 cards sidebar
   - panic capture action (`Cmd+Shift+Space` shortcut in-app)
6. New model:
   - `InsightCard` wire model in Swift

## Verification
- Python syntax check: `python3 -m py_compile ...` (pass)
- Backend tests: `PYTHONPATH=backend pytest -q backend/tests` (2 passed)

## Controlled limitations (known)
1. `WhisperKitProvider` remains mock-backed until real WhisperKit runtime wiring.
2. `SystemAudioCaptureService` remains diagnostic-level stub; full ScreenCaptureKit stream ingest is next integration step.
3. Swift build/tests are blocked in this environment by local SDK/toolchain mismatch and restricted cache path permissions.
