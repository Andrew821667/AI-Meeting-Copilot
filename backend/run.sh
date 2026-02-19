#!/bin/bash
# Launcher for AI Meeting Copilot backend with venv support.
DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_PYTHON="$DIR/.venv/bin/python3"
if [ -x "$VENV_PYTHON" ]; then
    exec "$VENV_PYTHON" "$DIR/main.py" "$@"
fi
exec python3 "$DIR/main.py" "$@"
