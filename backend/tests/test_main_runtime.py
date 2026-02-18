import asyncio

from main import BackendServer, run_healthcheck


def test_healthcheck_ok_on_writable_tmp(tmp_path) -> None:
    ok, payload = run_healthcheck(tmp_path / "exports")
    assert ok is True
    assert payload["checks"]["exports_writable"] is True
    assert payload["checks"]["default_profile_load"] is True
    assert payload["details"]["llm_mode"] in {"deepseek", "local_fallback"}


def test_healthcheck_detects_unwritable_path(tmp_path) -> None:
    locked = tmp_path / "locked"
    locked.write_text("x", encoding="utf-8")
    ok, payload = run_healthcheck(locked)
    assert ok is False
    assert payload["checks"]["exports_writable"] is False


def test_dispatch_unknown_event_returns_runtime_error(tmp_path) -> None:
    server = BackendServer(exports_dir=tmp_path)
    packets = asyncio.run(server._dispatch_message(msg_type="unknown_type", payload={}))
    assert packets[0]["type"] == "runtime_error"
    assert packets[0]["payload"]["category"] == "unknown_event"
