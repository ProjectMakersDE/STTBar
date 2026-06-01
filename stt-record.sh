#!/usr/bin/env bash
# stt-record.sh — Start/stop audio recording via sox
# Usage: stt-record.sh start|stop|status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_AUDIO_DEVICE="${STT_AUDIO_DEVICE:-}"
STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH="${STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH:-1}"
STT_RECORD_FILE="${STT_RECORD_FILE:-/tmp/stt-recording.wav}"
STT_PID_FILE="/tmp/stt-recording.pid"

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

macos_non_bluetooth_input_device() {
    local system_profiler_bin
    if system_profiler_bin="$(command -v system_profiler 2>/dev/null)"; then
        :
    elif [[ -x /usr/sbin/system_profiler ]]; then
        system_profiler_bin="/usr/sbin/system_profiler"
    else
        return 0
    fi

    "$system_profiler_bin" SPAudioDataType 2>/dev/null | awk '
        function flush_device() {
            if (name == "") {
                return
            }

            if (is_input && is_default && transport == "Bluetooth") {
                default_is_bluetooth = 1
            }

            if (is_input && transport != "Bluetooth") {
                if (transport == "Built-in" && built_in == "") {
                    built_in = name
                } else if (transport == "USB" && usb == "") {
                    usb = name
                } else if (other == "") {
                    other = name
                }
            }

            name = ""
            is_input = 0
            is_default = 0
            transport = ""
        }

        /^        [^ ].*:$/ {
            flush_device()
            name = $0
            sub(/^[[:space:]]+/, "", name)
            sub(/:$/, "", name)
            next
        }

        /Input Channels:/ { is_input = 1 }
        /Default Input Device: Yes/ { is_default = 1 }
        /Transport:/ {
            transport = $0
            sub(/^.*Transport:[[:space:]]*/, "", transport)
            sub(/[[:space:]]+$/, "", transport)
        }

        END {
            flush_device()

            if (!default_is_bluetooth) {
                exit
            }

            if (built_in != "") {
                print built_in
            } else if (usb != "") {
                print usb
            } else if (other != "") {
                print other
            }
        }
    '
}

resolve_audio_device() {
    local audio_device="$STT_AUDIO_DEVICE"

    if [[ "$(uname -s)" == "Darwin" ]] && is_truthy "$STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH"; then
        case "$audio_device" in
            ""|default)
                # If the current default input is a Bluetooth headset mic,
                # opening it forces macOS into the low-quality bidirectional
                # profile. Prefer a non-Bluetooth input so music output keeps
                # its high-quality profile while recording speech.
                local macos_device
                macos_device="$(macos_non_bluetooth_input_device || true)"
                if [[ -n "$macos_device" ]]; then
                    audio_device="$macos_device"
                fi
                ;;
        esac
    fi

    printf '%s\n' "$audio_device"
}

start_recording() {
    if [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null; then
        echo "ERROR: Recording already in progress" >&2
        return 1
    fi

    # Record: 16kHz, mono, 16-bit WAV
    # AUDIODEV can be an ALSA device on Linux or a CoreAudio device name on macOS.
    local audio_device
    audio_device="$(resolve_audio_device)"
    if [[ -n "$audio_device" ]] && [[ "$audio_device" != "default" ]] && [[ "$(uname -s)" == "Darwin" ]]; then
        sox -q -t coreaudio "$audio_device" -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    elif [[ -n "$audio_device" ]]; then
        AUDIODEV="$audio_device" rec -q -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    else
        rec -q -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    fi
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
        # Wait for rec process to actually exit
        local i=0
        while kill -0 "$rec_pid" 2>/dev/null && (( i++ < 20 )); do
            sleep 0.1
        done
    fi

    rm -f "$STT_PID_FILE"

    # Check if file exists and has audio content (> 44 bytes = WAV header only)
    if [[ ! -f "$STT_RECORD_FILE" ]] || [[ "$(wc -c < "$STT_RECORD_FILE" 2>/dev/null || echo 0)" -le 44 ]]; then
        echo "ERROR: Recording is empty" >&2
        rm -f "$STT_RECORD_FILE"
        return 1
    fi

    echo "$STT_RECORD_FILE"
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
        start_recording
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
