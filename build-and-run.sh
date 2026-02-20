#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Building ==="
swift build

BINARY=".build/arm64-apple-macosx/debug/AIMeetingCopilot"
BUNDLE_ID="com.andrew821667.ai-meeting-copilot"

echo "=== Signing with $BUNDLE_ID ==="
codesign --force --sign - --identifier "$BUNDLE_ID" "$BINARY"

echo "=== Stopping old instances ==="
pkill -f AIMeetingCopilot 2>/dev/null || true
pkill -f "backend/main.py" 2>/dev/null || true
sleep 1

echo "=== Launching ==="
open "$BINARY"
echo "Done."
