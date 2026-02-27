#!/usr/bin/env bash
# stt-record.sh — Start/stop audio recording via sox
# Usage: stt-record.sh start|stop|status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_AUDIO_DEVICE="${STT_AUDIO_DEVICE:-default}"
STT_RECORD_FILE="${STT_RECORD_FILE:-/tmp/stt-recording-$$.wav}"
STT_PID_FILE="/tmp/stt-recording.pid"

start_recording() {
    if [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null; then
        echo "ERROR: Recording already in progress" >&2
        return 1
    fi

    # Record: 16kHz, mono, 16-bit WAV
    rec -q -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    local rec_pid=$!
    echo "$rec_pid" > "$STT_PID_FILE"
    echo "$STT_RECORD_FILE"
}

stop_recording() {
    if [[ ! -f "$STT_PID_FILE" ]]; then
        echo "ERROR: No recording in progress" >&2
        return 1
    fi

    local rec_pid
    rec_pid="$(cat "$STT_PID_FILE")"

    if kill -0 "$rec_pid" 2>/dev/null; then
        kill -SIGINT "$rec_pid" 2>/dev/null
        wait "$rec_pid" 2>/dev/null || true
    fi

    rm -f "$STT_PID_FILE"

    # Check if file exists and has audio content (> 44 bytes = WAV header only)
    local file
    file="$(cat /tmp/stt-record-file 2>/dev/null || echo "$STT_RECORD_FILE")"
    if [[ ! -f "$file" ]] || [[ "$(stat -c%s "$file" 2>/dev/null || echo 0)" -le 44 ]]; then
        echo "ERROR: Recording is empty" >&2
        rm -f "$file" /tmp/stt-record-file
        return 1
    fi

    echo "$file"
}

get_status() {
    if [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null; then
        echo "recording"
    else
        rm -f "$STT_PID_FILE"
        echo "idle"
    fi
}

case "${1:-}" in
    start)
        local_file="$(start_recording)"
        echo "$local_file" > /tmp/stt-record-file
        echo "$local_file"
        ;;
    stop)
        stop_recording
        ;;
    status)
        get_status
        ;;
    *)
        echo "Usage: $0 start|stop|status" >&2
        exit 1
        ;;
esac
