#!/usr/bin/env bash
# stt-record.sh — Start/stop audio recording via sox
# Usage: stt-record.sh start|stop|status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/stt-runtime.sh" ]] && source "$SCRIPT_DIR/stt-runtime.sh"
stt_runtime_init

STT_AUDIO_DEVICE="${STT_AUDIO_DEVICE:-}"
STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH="${STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH:-1}"
STT_REC_IDENTITY_FILE="$STT_PID_FILE.identity"

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

# A PID alone is not a recording identity. Only a recorder launched into this
# private runtime, with its owner/start time and recorder command verified, may
# be signalled. Interpreter exec (env -> bash in tests) preserves that identity.
# Shared /tmp legacy PID files and process-name scans are deliberately ignored.
recorder_identity() {
    local pid="$1" owner args
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$pid" != 1 ]] || return 1
    owner="$(ps -p "$pid" -o uid= 2>/dev/null | tr -d '[:space:]')"
    [[ "$owner" == "$(id -u)" ]] || return 1
    args="$(ps -p "$pid" -o args= 2>/dev/null)"
    [[ "$args" =~ (^|[[:space:]])([^[:space:]]*/)?(rec|sox)([[:space:]]|$) ]] || return 1
    [[ "$args" == *" $STT_RECORD_FILE" ]] || return 1
    ps -p "$pid" -o uid=,lstart= 2>/dev/null
}

trusted_recording_pid() {
    [[ -f "$STT_PID_FILE" && ! -L "$STT_PID_FILE" && -O "$STT_PID_FILE" ]] || return 1
    [[ -f "$STT_REC_IDENTITY_FILE" && ! -L "$STT_REC_IDENTITY_FILE" && -O "$STT_REC_IDENTITY_FILE" ]] || return 1
    local pid identity
    pid="$(cat "$STT_PID_FILE" 2>/dev/null)"
    identity="$(recorder_identity "$pid")" || return 1
    [[ -n "$identity" && "$identity" == "$(cat "$STT_REC_IDENTITY_FILE" 2>/dev/null)" ]] || return 1
    printf '%s\n' "$pid"
}

start_recording() {
    # A force start (the app decided this press is unambiguously a start because
    # no recording was live) tears down the trusted recorder and this runtime's
    # stale files first, so the toggle cannot get stuck on leftovers.
    if is_truthy "${STT_FORCE_START:-0}"; then
        force_clear_recordings
    fi
    if trusted_recording_pid >/dev/null; then
        echo "ERROR: Recording already in progress" >&2
        stt_status_event "recording_already_running" "recording" "warning" "recording_already_running" "A recording is already running."
        return 1
    fi
    rm -f "$STT_PID_FILE" "$STT_REC_IDENTITY_FILE" "$STT_LOCK_FILE" "$STT_RECORD_FILE" 2>/dev/null || true
    printf '%s\n' "$$" > "$STT_LOCK_FILE" 2>/dev/null || true
    stt_new_run_id >/dev/null
    stt_now_ms > "$STT_RECORDING_STARTED_FILE" 2>/dev/null || true

    # Record: 16kHz, mono, 16-bit WAV
    # AUDIODEV can be an ALSA device on Linux or a CoreAudio device name on macOS.
    local audio_device
    audio_device="$(resolve_audio_device)"
    local record_buffer_bytes="${STT_RECORD_BUFFER_BYTES:-1024}"
    if [[ -n "$audio_device" ]] && [[ "$audio_device" != "default" ]] && [[ "$(uname -s)" == "Darwin" ]]; then
        sox -q --buffer "$record_buffer_bytes" -t coreaudio "$audio_device" -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    elif [[ -n "$audio_device" ]]; then
        AUDIODEV="$audio_device" rec -q --buffer "$record_buffer_bytes" -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    else
        rec -q --buffer "$record_buffer_bytes" -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    fi
    local rec_pid=$!
    local identity="" i
    # Allow the launched child to exec rec/sox before capturing its identity.
    for i in 1 2 3 4 5 6 7 8 9 10; do
        identity="$(recorder_identity "$rec_pid" || true)"
        [[ -n "$identity" ]] && break
        sleep 0.05
    done
    if [[ -z "$identity" ]]; then
        kill "$rec_pid" 2>/dev/null || true
        rm -f "$STT_LOCK_FILE"
        echo "ERROR: Recorder did not start" >&2
        return 1
    fi
    printf '%s\n' "$identity" > "$STT_REC_IDENTITY_FILE"
    echo "$rec_pid" > "$STT_PID_FILE"
    stt_status_event "recording_started" "recording" "info" "" "Recording." "device=$audio_device"
    echo "$STT_RECORD_FILE"
}

stop_recording() {
    local rec_pid record_file="$STT_RECORD_FILE"
    rec_pid="$(trusted_recording_pid || true)"
    if [[ -z "$rec_pid" ]]; then
        echo "ERROR: No trusted recording in progress" >&2
        stt_status_event "recording_missing" "idle" "warning" "recording_missing" "No active recording found."
        return 1
    fi
    kill -SIGINT "$rec_pid" 2>/dev/null || true
    local i=0
    while trusted_recording_pid >/dev/null && (( i++ < 20 )); do
        sleep 0.1
    done
    # A recorder still writing must not be passed to transcription.
    if trusted_recording_pid >/dev/null; then
        echo "ERROR: Recorder did not stop" >&2
        return 1
    fi
    rm -f "$STT_PID_FILE" "$STT_REC_IDENTITY_FILE" "$STT_LOCK_FILE"

    # Check if file exists and has audio content (> 44 bytes = WAV header only)
    if [[ ! -f "$record_file" ]] || [[ "$(wc -c < "$record_file" 2>/dev/null || echo 0)" -le 44 ]]; then
        echo "ERROR: Recording is empty" >&2
        rm -f "$record_file"
        stt_status_event "recording_empty" "error" "error" "recording_empty" "Recording was empty." "Check microphone, sox/rec and input device."
        return 1
    fi

    stt_status_event "recording_stopped" "whisper" "info" "" "Recording stopped."
    echo "$record_file"
}

# Stop only the recorder identified by this runtime, then remove its files.
force_clear_recordings() {
    local rec_pid
    rec_pid="$(trusted_recording_pid || true)"
    if [[ -n "$rec_pid" ]]; then
        kill -SIGINT "$rec_pid" 2>/dev/null || true
        local i=0
        while trusted_recording_pid >/dev/null && (( i++ < 20 )); do
            sleep 0.1
        done
        if trusted_recording_pid >/dev/null; then
            kill "$rec_pid" 2>/dev/null || true
        fi
    fi
    rm -f "$STT_PID_FILE" "$STT_REC_IDENTITY_FILE" "$STT_LOCK_FILE" "$STT_RECORD_FILE" "$STT_RECORDING_STARTED_FILE" 2>/dev/null || true
}

cancel_recording() {
    force_clear_recordings
    stt_set_phase "idle"
    stt_status_event "recording_cancelled" "idle" "info" "" "Recording cancelled."
}

get_status() {
    if trusted_recording_pid >/dev/null; then
        echo "recording"
    else
        # A reader can observe launch between the identity and PID writes.
        # Only start/stop/cancel may clean files, so polling cannot orphan rec.
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
    cancel|abort)
        cancel_recording
        ;;
    status)
        get_status
        ;;
    *)
        echo "Usage: $0 start|stop|cancel|status" >&2
        exit 1
        ;;
esac
