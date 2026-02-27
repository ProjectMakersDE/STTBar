#!/usr/bin/env bash
# stt-transcribe.sh — Send audio file to Whisper server and return text
# Usage: stt-transcribe.sh <audio-file>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_SERVER_URL="${STT_SERVER_URL:-http://localhost:8000/v1/audio/transcriptions}"
STT_LANGUAGE="${STT_LANGUAGE:-de}"
STT_MODEL="${STT_MODEL:-Systran/faster-whisper-base}"

audio_file="${1:-}"

if [[ -z "$audio_file" ]]; then
    echo "Usage: $0 <audio-file>" >&2
    exit 1
fi

if [[ ! -f "$audio_file" ]]; then
    echo "ERROR: File not found: $audio_file" >&2
    exit 1
fi

# POST to OpenAI-compatible transcription endpoint
response="$(curl -s -w "\n%{http_code}" \
    --max-time 30 \
    -X POST "$STT_SERVER_URL" \
    -F "file=@$audio_file" \
    -F "model=$STT_MODEL" \
    -F "language=$STT_LANGUAGE" \
    -F "response_format=json" \
    )"

http_code="$(echo "$response" | tail -n1)"
body="$(echo "$response" | sed '$d')"

if [[ "$http_code" -ne 200 ]]; then
    echo "ERROR: Server returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
fi

# Extract text from JSON response {"text": "..."}
text="$(echo "$body" | jq -r '.text // empty')"

if [[ -z "$text" ]]; then
    echo "ERROR: Empty transcription result" >&2
    exit 1
fi

echo "$text"
