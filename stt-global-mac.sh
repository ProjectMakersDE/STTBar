#!/usr/bin/env bash
# stt-global-mac.sh — System-wide STT toggle for macOS
# Triggered by skhd global hotkey. First call starts recording, second
# call stops + transcribes + pastes into the focused text field.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_PID_FILE="/tmp/stt-recording.pid"

notify() {
    local body="$1"
    # Escape double quotes for osascript's double-quoted string literal
    local escaped="${body//\"/\\\"}"
    osascript -e "display notification \"$escaped\" with title \"STT\"" 2>/dev/null || true
}

is_recording() {
    [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null
}

if is_recording; then
    # --- STOP RECORDING & TRANSCRIBE & PASTE ---
    notify "Transcribing..."

    audio_file="$("$SCRIPT_DIR/stt-record.sh" stop 2>/dev/null)" || true
    if [[ -z "$audio_file" ]]; then
        notify "Recording failed or was empty."
        exit 1
    fi

    text="$("$SCRIPT_DIR/stt-transcribe.sh" "$audio_file" 2>/dev/null)"
    rc=$?
    rm -f "$audio_file"

    if [[ $rc -ne 0 ]] || [[ -z "$text" ]]; then
        notify "Transcription failed. Is the whisper server running?"
        exit 1
    fi

    # Put text on clipboard (always — fallback for manual paste)
    printf '%s' "$text" | pbcopy

    # Paste into whatever field currently has focus.
    # skhd does not steal focus when triggering scripts, so the target
    # field is still active. Requires Accessibility permission for skhd.
    osascript -e 'tell application "System Events" to keystroke "v" using command down'

    notify "$text"
else
    # --- START RECORDING ---
    if ! "$SCRIPT_DIR/stt-record.sh" start >/dev/null 2>&1; then
        notify "Could not start recording. Is sox installed?"
        exit 1
    fi

    notify "Recording... (Cmd+Shift+Space to stop)"
fi
