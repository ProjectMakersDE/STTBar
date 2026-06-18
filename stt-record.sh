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
STT_LEGACY_PID_FILE="${STT_LEGACY_PID_FILE:-/tmp/stt-recording.pid}"
STT_LEGACY_RECORD_FILE="${STT_LEGACY_RECORD_FILE:-/tmp/stt-recording.wav}"

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

legacy_recording_pids() {
    [[ "$STT_LEGACY_RECORD_FILE" != "$STT_RECORD_FILE" ]] || return 0
    ps ax -o pid=,args= 2>/dev/null | awk -v file="$STT_LEGACY_RECORD_FILE" '
        index($0, file) > 0 && $0 ~ /(^|[[:space:]])rec([[:space:]]|$)/ {
            print $1
        }
    '
}

first_legacy_recording_pid() {
    legacy_recording_pids | head -n 1
}

start_recording() {
    if [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null; then
        echo "ERROR: Recording already in progress" >&2
        stt_status_event "recording_already_running" "recording" "warning" "recording_already_running" "Eine Aufnahme läuft bereits."
        return 1
    fi
    if [[ "$STT_LEGACY_PID_FILE" != "$STT_PID_FILE" ]] && [[ -f "$STT_LEGACY_PID_FILE" ]] && kill -0 "$(cat "$STT_LEGACY_PID_FILE")" 2>/dev/null; then
        echo "ERROR: Legacy recording already in progress" >&2
        stt_status_event "legacy_recording_running" "recording" "warning" "legacy_recording_running" "Eine alte /tmp-Aufnahme läuft bereits." "$STT_LEGACY_PID_FILE"
        return 1
    fi
    if [[ -n "$(first_legacy_recording_pid)" ]]; then
        echo "ERROR: Legacy orphan recording already in progress" >&2
        stt_status_event "legacy_recording_running" "recording" "warning" "legacy_recording_running" "Eine alte /tmp-Aufnahme ohne PID-Datei läuft bereits." "$STT_LEGACY_RECORD_FILE"
        return 1
    fi
    rm -f "$STT_PID_FILE" "$STT_LOCK_FILE" "$STT_RECORD_FILE" 2>/dev/null || true
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
    echo "$rec_pid" > "$STT_PID_FILE"
    stt_status_event "recording_started" "recording" "info" "" "Aufnahme läuft." "device=$audio_device"
    echo "$STT_RECORD_FILE"
}

stop_recording() {
    local pid_file="$STT_PID_FILE"
    local record_file="$STT_RECORD_FILE"
    if [[ ! -f "$pid_file" ]] && [[ "$STT_LEGACY_PID_FILE" != "$STT_PID_FILE" ]] && [[ -f "$STT_LEGACY_PID_FILE" ]] && kill -0 "$(cat "$STT_LEGACY_PID_FILE")" 2>/dev/null; then
        pid_file="$STT_LEGACY_PID_FILE"
        record_file="$STT_LEGACY_RECORD_FILE"
        stt_status_event "legacy_recording_stop_requested" "whisper" "warning" "legacy_recording" "Alte /tmp-Aufnahme wird gestoppt." "$STT_LEGACY_PID_FILE"
    fi

    local rec_pid
    if [[ -f "$pid_file" ]]; then
        rec_pid="$(cat "$pid_file")"
    else
        rec_pid="$(first_legacy_recording_pid)"
        if [[ -n "$rec_pid" ]]; then
            record_file="$STT_LEGACY_RECORD_FILE"
            stt_status_event "legacy_recording_stop_requested" "whisper" "warning" "legacy_recording" "Alte /tmp-Aufnahme ohne PID-Datei wird gestoppt." "$STT_LEGACY_RECORD_FILE"
        fi
    fi

    if [[ -z "${rec_pid:-}" ]]; then
        echo "ERROR: No recording in progress" >&2
        stt_status_event "recording_missing" "idle" "warning" "recording_missing" "Keine laufende Aufnahme gefunden."
        return 1
    fi

    if kill -0 "$rec_pid" 2>/dev/null; then
        kill -SIGINT "$rec_pid" 2>/dev/null
        # Wait for rec process to actually exit
        local i=0
        while kill -0 "$rec_pid" 2>/dev/null && (( i++ < 20 )); do
            sleep 0.1
        done
    fi

    rm -f "$pid_file" "$STT_LOCK_FILE"

    # Check if file exists and has audio content (> 44 bytes = WAV header only)
    if [[ ! -f "$record_file" ]] || [[ "$(wc -c < "$record_file" 2>/dev/null || echo 0)" -le 44 ]]; then
        echo "ERROR: Recording is empty" >&2
        rm -f "$record_file"
        stt_status_event "recording_empty" "error" "error" "recording_empty" "Aufnahme war leer." "Prüfe Mikrofon, sox/rec und Eingabegerät."
        return 1
    fi

    stt_status_event "recording_stopped" "whisper" "info" "" "Aufnahme beendet."
    echo "$record_file"
}

cancel_recording() {
    for pid_file in "$STT_PID_FILE" "$STT_LEGACY_PID_FILE"; do
        [[ -f "$pid_file" ]] || continue
        local rec_pid
        rec_pid="$(cat "$pid_file" 2>/dev/null || true)"
        if [[ -n "$rec_pid" ]] && kill -0 "$rec_pid" 2>/dev/null; then
            kill -SIGINT "$rec_pid" 2>/dev/null || true
            local i=0
            while kill -0 "$rec_pid" 2>/dev/null && (( i++ < 20 )); do
                sleep 0.1
            done
            kill "$rec_pid" 2>/dev/null || true
        fi
    done
    while read -r rec_pid; do
        [[ -n "$rec_pid" ]] || continue
        if kill -0 "$rec_pid" 2>/dev/null; then
            kill -SIGINT "$rec_pid" 2>/dev/null || true
            local i=0
            while kill -0 "$rec_pid" 2>/dev/null && (( i++ < 20 )); do
                sleep 0.1
            done
            kill "$rec_pid" 2>/dev/null || true
        fi
    done < <(legacy_recording_pids)
    rm -f "$STT_PID_FILE" "$STT_LEGACY_PID_FILE" "$STT_LOCK_FILE" "$STT_RECORD_FILE" "$STT_LEGACY_RECORD_FILE" "$STT_RECORDING_STARTED_FILE" 2>/dev/null || true
    stt_set_phase "idle"
    stt_status_event "recording_cancelled" "idle" "info" "" "Aufnahme abgebrochen."
}

get_status() {
    if [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null; then
        echo "recording"
    elif [[ "$STT_LEGACY_PID_FILE" != "$STT_PID_FILE" ]] && [[ -f "$STT_LEGACY_PID_FILE" ]] && kill -0 "$(cat "$STT_LEGACY_PID_FILE")" 2>/dev/null; then
        echo "recording"
    elif [[ -n "$(first_legacy_recording_pid)" ]]; then
        echo "recording"
    else
        rm -f "$STT_PID_FILE"
        if [[ "$STT_LEGACY_PID_FILE" != "$STT_PID_FILE" ]] && [[ -f "$STT_LEGACY_PID_FILE" ]] && ! kill -0 "$(cat "$STT_LEGACY_PID_FILE")" 2>/dev/null; then
            rm -f "$STT_LEGACY_PID_FILE"
        fi
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
