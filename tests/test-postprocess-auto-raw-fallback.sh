#!/usr/bin/env bash
# Verifies STT_AUTO_RAW_FALLBACK controls LLM failure fallback behavior.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

out="$(printf 'hello horizon' | \
    STT_RUNTIME_DIR="$tmp/runtime-ok" \
    STT_POSTPROCESS_ENABLED=1 \
    STT_POSTPROCESS_PROVIDER=unknown \
    STT_POSTPROCESS_LOG_ENABLED=0 \
    "$ROOT/stt-postprocess.sh")"
[[ "$out" == *"horizOn"* ]] || { echo "FAIL fallback default: [$out]"; exit 1; }

if printf 'hello' | \
    STT_RUNTIME_DIR="$tmp/runtime-fail" \
    STT_POSTPROCESS_ENABLED=1 \
    STT_POSTPROCESS_PROVIDER=unknown \
    STT_AUTO_RAW_FALLBACK=0 \
    STT_POSTPROCESS_LOG_ENABLED=0 \
    "$ROOT/stt-postprocess.sh" >/tmp/stt-postprocess-fallback-test.out 2>/dev/null; then
    echo "FAIL fallback disabled still succeeded"
    exit 1
fi

echo "PASS postprocess-auto-raw-fallback"
