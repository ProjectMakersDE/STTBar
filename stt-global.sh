#!/usr/bin/env bash
# stt-global.sh — System-wide STT toggle for X11
# Triggered by global hotkey. First call starts recording, second call stops + transcribes + pastes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_PID_FILE="/tmp/stt-recording.pid"

notify() {
    local urgency="${1:-normal}"
    local timeout="${2:-3000}"
    local title="STT"
    local body="$3"
    notify-send -u "$urgency" -t "$timeout" "$title" "$body" 2>/dev/null || true
}

is_recording() {
    [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null
}

if is_recording; then
    # --- STOP RECORDING & TRANSCRIBE & PASTE ---
    notify normal 2000 "Transcribing..."

    audio_file="$("$SCRIPT_DIR/stt-record.sh" stop 2>/dev/null)" || true
    if [[ -z "$audio_file" ]]; then
        notify critical 3000 "Recording failed or was empty."
        exit 1
    fi

    text="$("$SCRIPT_DIR/stt-transcribe.sh" "$audio_file" 2>/dev/null)"
    rc=$?
    rm -f "$audio_file"

    if [[ $rc -ne 0 ]] || [[ -z "$text" ]]; then
        notify critical 3000 "Transcription failed. Is the whisper server running?"
        exit 1
    fi

    # Inject text via clipboard + paste
    printf '%s' "$text" | xclip -selection clipboard
    sleep 0.15
    xdotool key --clearmodifiers ctrl+shift+v

    notify normal 2000 "$text"
else
    # --- START RECORDING ---
    if ! "$SCRIPT_DIR/stt-record.sh" start >/dev/null 2>&1; then
        notify critical 3000 "Could not start recording. Is sox installed?"
        exit 1
    fi

    notify normal 5000 "Recording... (Ctrl+T to stop)"
fi
