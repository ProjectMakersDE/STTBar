#!/usr/bin/env bash
# Verifies STT_POSTPROCESS_PROMPT_FILE is honored, with correct precedence.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$SCRIPT_DIR/stt-postprocess.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Disable the LLM and replacements so we test prompt resolution in isolation.
prompt_file="$tmp/p.txt"
printf 'PROMPT_FROM_FILE_MARKER' > "$prompt_file"

# STT_POSTPROCESS_PRINT_PROMPT=1 makes the script print the resolved prompt
# and exit 0 without calling any model.
out="$(printf 'hello' | STT_POSTPROCESS_PRINT_PROMPT=1 \
    STT_POSTPROCESS_PROMPT_FILE="$prompt_file" \
    STT_POSTPROCESS_ENABLED=1 STT_REPLACEMENTS_ENABLED=0 STT_POSTPROCESS_LOG_ENABLED=0 \
    "$SUT")"
case "$out" in
    *PROMPT_FROM_FILE_MARKER*) echo "PASS file-prompt" ;;
    *) echo "FAIL file-prompt: got [$out]"; exit 1 ;;
esac

# Inline STT_POSTPROCESS_PROMPT must win over the file.
out="$(printf 'hello' | STT_POSTPROCESS_PRINT_PROMPT=1 \
    STT_POSTPROCESS_PROMPT='INLINE_WINS' \
    STT_POSTPROCESS_PROMPT_FILE="$prompt_file" \
    STT_POSTPROCESS_ENABLED=1 STT_REPLACEMENTS_ENABLED=0 STT_POSTPROCESS_LOG_ENABLED=0 \
    "$SUT")"
case "$out" in
    *INLINE_WINS*) echo "PASS inline-precedence" ;;
    *) echo "FAIL inline-precedence: got [$out]"; exit 1 ;;
esac
echo "ALL PASS"
