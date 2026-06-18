#!/usr/bin/env bash
# stt-global.sh — System-wide STT toggle for X11
# Triggered by global hotkey. First call starts recording, second call stops + transcribes + pastes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/stt-runtime.sh" ]] && source "$SCRIPT_DIR/stt-runtime.sh"
stt_runtime_init

STT_STATE_FILE="${STT_STATE_FILE:-$STT_RUNTIME_DIR/state}"

stt_state() {
    printf '%s' "$1" > "$STT_STATE_FILE" 2>/dev/null || true
}

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
    # --- STOP RECORDING & TRANSCRIBE & TYPE ---

    # Save focused window BEFORE any notifications or work
    target_window="$(xdotool getactivewindow 2>/dev/null)" || true

    stt_state "transcribing"

    audio_file="$("$SCRIPT_DIR/stt-record.sh" stop 2>/dev/null)" || true
    if [[ -z "$audio_file" ]]; then
        stt_state "idle"
        stt_status_event "recording_empty" "error" "error" "recording_empty" "Recording failed or was empty."
        notify critical 3000 "Recording failed or was empty."
        exit 1
    fi

    text="$("$SCRIPT_DIR/stt-transcribe.sh" "$audio_file" 2>/dev/null)"
    rc=$?
    rm -f "$audio_file"

    if [[ $rc -ne 0 ]] || [[ -z "$text" ]]; then
        stt_state "idle"
        stt_status_event "whisper_failed" "error" "error" "whisper_failed" "Transcription failed."
        notify critical 3000 "Transcription failed. Is the whisper server running?"
        exit 1
    fi

    if [[ -x "$SCRIPT_DIR/stt-postprocess.sh" ]]; then
        text="$(printf '%s' "$text" | "$SCRIPT_DIR/stt-postprocess.sh" 2>/dev/null || printf '%s' "$text")"
    fi

    # Also set clipboard as fallback for manual paste
    printf '%s' "$text" | xclip -selection clipboard 2>/dev/null || true

    # Restore focus to the original window and type text directly
    if [[ -n "$target_window" ]]; then
        xdotool windowfocus --sync "$target_window" 2>/dev/null || true
        sleep 0.1
    fi
    sleep 0.2
    xdotool key --clearmodifiers ctrl+v

    stt_state "idle"
else
    # --- START RECORDING ---
    if ! "$SCRIPT_DIR/stt-record.sh" start >/dev/null 2>&1; then
        stt_status_event "recording_start_failed" "error" "error" "recording_start_failed" "Could not start recording. Is sox installed?"
        notify critical 3000 "Could not start recording. Is sox installed?"
        exit 1
    fi

    stt_state "recording"
fi
