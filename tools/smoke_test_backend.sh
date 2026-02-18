#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/.tmp"
SOCKET_PATH="$ROOT_DIR/.tmp/aimc-smoke-$$.sock"
EXPORTS_DIR="$(mktemp -d)"
LOG_FILE="$(mktemp)"

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    kill -TERM "$BACKEND_PID" >/dev/null 2>&1 || true
    wait "$BACKEND_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$SOCKET_PATH" "$LOG_FILE"
  rm -rf "$EXPORTS_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
python3 backend/main.py --socket "$SOCKET_PATH" --exports-dir "$EXPORTS_DIR" >"$LOG_FILE" 2>&1 &
BACKEND_PID=$!

for _ in {1..50}; do
  [[ -S "$SOCKET_PATH" ]] && break
  sleep 0.1
done

if [[ ! -S "$SOCKET_PATH" ]]; then
  echo "Smoke test failed: backend socket не поднялся"
  cat "$LOG_FILE"
  exit 1
fi

python3 - "$SOCKET_PATH" <<'PY'
import json
import socket
import sys
import time

socket_path = sys.argv[1]

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(socket_path)
stream = sock.makefile("rwb", buffering=0)

def send(packet: dict) -> None:
    stream.write((json.dumps(packet, ensure_ascii=False) + "\n").encode("utf-8"))

def recv_until(expected_type: str, timeout: float = 3.0) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = stream.readline()
        if not line:
            break
        payload = json.loads(line.decode("utf-8"))
        if payload.get("type") == expected_type:
            return payload
    raise RuntimeError(f"Не получен пакет {expected_type}")

send({"type": "session_control", "payload": {"event": "start", "session_id": "smoke-1", "profile": "negotiation"}})
recv_until("session_ack")

send({"type": "panic_capture", "payload": {}})
card = recv_until("insight_card")
assert card["payload"]["trigger_reason"] == "Ручной захват момента"

send({"type": "session_control", "payload": {"event": "end"}})
summary = recv_until("session_summary")
assert summary["payload"]["session_id"] == "smoke-1"
PY

echo "Smoke test OK"
