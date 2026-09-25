#!/usr/bin/env bash
# stt-transcribe.sh — Send audio file to Whisper server and return text
# Usage: stt-transcribe.sh <audio-file>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/stt-runtime.sh" ]] && source "$SCRIPT_DIR/stt-runtime.sh"
stt_runtime_init

STT_SERVER_URL="${STT_SERVER_URL:-http://localhost:8000/v1/audio/transcriptions}"
STT_LANGUAGE="${STT_LANGUAGE:-de}"
STT_MODEL="${STT_MODEL:-Systran/faster-whisper-base}"
STT_TRANSCRIBE_TIMEOUT="${STT_TRANSCRIBE_TIMEOUT:-30}"
STT_PROMPT="${STT_PROMPT:-}"
# Decode fields for the whisper.cpp server (ignored by servers that lack them).
STT_VAD_FILTER="${STT_VAD_FILTER:-1}"
STT_BEAM_SIZE="${STT_BEAM_SIZE-5}"
STT_TEMPERATURE_FALLBACK="${STT_TEMPERATURE_FALLBACK:-0}"

# Whisper "prompt": a well-formed sentence the decoder sees as preceding
# context. It steers casing and punctuation on poor audio and is never part of
# the returned text. Empty = built-in default for the language, "off" = none.
stt_default_prompt() {
    case "$1" in
        de) printf '%s' "Guten Tag, das ist ein Diktat. Ich spreche jetzt einen Text mit Satzzeichen, Groß- und Kleinschreibung ein." ;;
        en) printf '%s' "Hello, this is a dictation. I am now speaking a text with punctuation and proper capitalization." ;;
        *) printf '' ;;
    esac
}
stt_resolve_prompt() {
    local value trimmed
    value="$1"
    trimmed="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')" in
        off) printf '' ;;
        "") stt_default_prompt "$2" ;;
        *) printf '%s' "$trimmed" ;;
    esac
}
# Drops a leading copy of the prompt some servers echo back into the transcript.
stt_strip_echoed_prompt() {
    local text prompt head
    text="$1"; prompt="$2"
    [[ -n "$prompt" ]] || { printf '%s' "$text"; return; }
    head="${text:0:${#prompt}}"
    if [[ "$(printf '%s' "$head" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')" ]]; then
        text="${text:${#prompt}}"
        text="$(printf '%s' "$text" | sed -e 's/^[[:space:]]*//')"
    fi
    printf '%s' "$text"
}
whisper_prompt="$(stt_resolve_prompt "$STT_PROMPT" "$STT_LANGUAGE")"

audio_file="${1:-}"

if [[ -z "$audio_file" ]]; then
    echo "Usage: $0 <audio-file>" >&2
    exit 1
fi

if [[ ! -f "$audio_file" ]]; then
    echo "ERROR: File not found: $audio_file" >&2
    stt_status_event "recording_file_missing" "error" "error" "recording_file_missing" "Audio file missing." "$audio_file"
    exit 1
fi

stt_status_event "whisper_request_started" "whisper" "info" "" "Whisper request started." "timeout=${STT_TRANSCRIBE_TIMEOUT}s model=$STT_MODEL"

# Build curl args — omit language for auto-detection
curl_args=(
    -sS -w "\n%{http_code}"
    --max-time "$STT_TRANSCRIBE_TIMEOUT"
    -X POST "$STT_SERVER_URL"
    -F "file=@$audio_file"
    -F "model=$STT_MODEL"
    -F "response_format=json"
)

# Only send language param if it's not "auto" (omitting it triggers auto-detection)
if [[ "$STT_LANGUAGE" != "auto" ]]; then
    curl_args+=(-F "language=$STT_LANGUAGE")
fi

if [[ -n "$whisper_prompt" ]]; then
    curl_args+=(-F "prompt=$whisper_prompt")
fi

# Silero VAD trims silence and noise before decoding.
if [[ "$STT_VAD_FILTER" == "1" ]]; then
    curl_args+=(-F "vad_filter=true")
fi
# Beam search instead of greedy decoding; empty or invalid = server default.
beam_size="$(printf '%s' "$STT_BEAM_SIZE" | tr -d '[:space:]')"
if [[ "$beam_size" =~ ^[0-9]+$ ]] && (( beam_size >= 1 )); then
    (( beam_size > 8 )) && beam_size=8
    curl_args+=(-F "beam_size=$beam_size")
fi
# Without fallback the decoder never re-samples at higher temperatures, which
# is where the lowercase, unpunctuated style tends to appear.
if [[ "$STT_TEMPERATURE_FALLBACK" != "1" ]]; then
    curl_args+=(-F "temperature=0" -F "temperature_inc=0")
fi

# POST to OpenAI-compatible transcription endpoint
curl_error_file="$(mktemp)"
if ! response="$(curl "${curl_args[@]}" 2>"$curl_error_file")"; then
    curl_error="$(tr '\n' ' ' < "$curl_error_file" | cut -c 1-300)"
    rm -f "$curl_error_file"
    stt_status_event "whisper_unreachable" "error" "error" "whisper_unreachable" "Whisper server unreachable." "$curl_error"
    echo "ERROR: Could not connect to server at $STT_SERVER_URL" >&2
    echo "$curl_error" >&2
    exit 1
fi
rm -f "$curl_error_file"

http_code="$(echo "$response" | tail -n1)"
body="$(echo "$response" | sed '$d')"

if [[ "$http_code" == "000" ]]; then
    stt_status_event "whisper_unreachable" "error" "error" "whisper_unreachable" "Whisper server unreachable." "$STT_SERVER_URL"
    echo "ERROR: Could not connect to server at $STT_SERVER_URL" >&2
    echo "Is the whisper server running? Try: docker compose up -d" >&2
    exit 1
fi

if [[ "$http_code" -ne 200 ]]; then
    stt_status_event "whisper_http_error" "error" "error" "whisper_http_error" "Whisper returned HTTP $http_code." "$(printf '%s' "$body" | cut -c 1-300)"
    echo "ERROR: Server returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
fi

# Extract text from JSON response {"text": "..."}
text="$(echo "$body" | jq -r '.text // empty')"
text="$(stt_strip_echoed_prompt "$text" "$whisper_prompt")"

if [[ -z "$text" ]]; then
    stt_status_event "whisper_empty_text" "error" "error" "whisper_empty_text" "Whisper returned no text."
    echo "ERROR: Empty transcription result" >&2
    exit 1
fi

stt_status_event "whisper_success" "llm" "info" "" "Whisper transcript received." "chars=${#text}"
echo "$text"
