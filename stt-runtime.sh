#!/usr/bin/env bash
# Shared runtime paths, status, and metrics helpers for the STT shell backend.

stt_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

stt_runtime_init() {
    STT_RUNTIME_DIR="${STT_RUNTIME_DIR:-${TMPDIR:-/tmp}/de.projectmakers.stt}"
    STT_RUNTIME_DIR="${STT_RUNTIME_DIR%/}"
    mkdir -p "$STT_RUNTIME_DIR" 2>/dev/null || true

    STT_PID_FILE="${STT_PID_FILE:-$STT_RUNTIME_DIR/recording.pid}"
    STT_RECORD_FILE="${STT_RECORD_FILE:-$STT_RUNTIME_DIR/recording.wav}"
    STT_LOCK_FILE="${STT_LOCK_FILE:-$STT_RUNTIME_DIR/recording.lock}"
    STT_PHASE_FILE="${STT_PHASE_FILE:-$STT_RUNTIME_DIR/phase}"
    STT_STATUS_FILE="${STT_STATUS_FILE:-$STT_RUNTIME_DIR/status.json}"
    STT_EVENTS_FILE="${STT_EVENTS_FILE:-$STT_RUNTIME_DIR/events.jsonl}"
    STT_METRICS_FILE="${STT_METRICS_FILE:-$STT_RUNTIME_DIR/metrics.jsonl}"
    STT_RESULT_FILE="${STT_RESULT_FILE:-$STT_RUNTIME_DIR/last-transcript.txt}"
    STT_RUN_ID_FILE="${STT_RUN_ID_FILE:-$STT_RUNTIME_DIR/run-id}"
    STT_RECORDING_STARTED_FILE="${STT_RECORDING_STARTED_FILE:-$STT_RUNTIME_DIR/recording-started-ms}"
}

stt_now_ms() {
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000' 2>/dev/null || {
        printf '%s000\n' "$(date +%s)"
    }
}

stt_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date
}

stt_current_run_id() {
    stt_runtime_init
    if [[ -n "${STT_RUN_ID:-}" ]]; then
        printf '%s\n' "$STT_RUN_ID"
    elif [[ -r "$STT_RUN_ID_FILE" ]]; then
        head -n 1 "$STT_RUN_ID_FILE"
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        printf 'stt-%s\n' "$(stt_now_ms)"
    fi
}

stt_new_run_id() {
    stt_runtime_init
    local run_id
    if command -v uuidgen >/dev/null 2>&1; then
        run_id="$(uuidgen)"
    else
        run_id="stt-$(stt_now_ms)"
    fi
    printf '%s\n' "$run_id" > "$STT_RUN_ID_FILE" 2>/dev/null || true
    printf '%s\n' "$run_id"
}

stt_set_phase() {
    stt_runtime_init
    printf '%s\n' "$1" > "$STT_PHASE_FILE" 2>/dev/null || true
}

stt_status_event() {
    stt_runtime_init
    local event="${1:-status}"
    local phase="${2:-$event}"
    local severity="${3:-info}"
    local code="${4:-}"
    local message="${5:-}"
    local detail="${6:-}"
    local timestamp run_id tmp
    timestamp="$(stt_timestamp)"
    run_id="$(stt_current_run_id)"
    tmp="$STT_STATUS_FILE.tmp.$$"

    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg schema "1" \
            --arg timestamp "$timestamp" \
            --arg run_id "$run_id" \
            --arg event "$event" \
            --arg phase "$phase" \
            --arg severity "$severity" \
            --arg code "$code" \
            --arg message "$message" \
            --arg detail "$detail" \
            --arg audio_file "${STT_RECORD_FILE:-}" \
            --arg result_file "${STT_RESULT_FILE:-}" \
            '{
                schema: ($schema | tonumber),
                timestamp: $timestamp,
                run_id: $run_id,
                event: $event,
                phase: $phase,
                severity: $severity,
                code: $code,
                message: $message,
                detail: $detail,
                audio_file: $audio_file,
                result_file: $result_file
            }' > "$tmp" 2>/dev/null && mv "$tmp" "$STT_STATUS_FILE" 2>/dev/null || rm -f "$tmp"
        [[ -f "$STT_STATUS_FILE" ]] && cat "$STT_STATUS_FILE" >> "$STT_EVENTS_FILE" 2>/dev/null || true
    else
        printf '{"schema":1,"timestamp":"%s","run_id":"%s","event":"%s","phase":"%s","severity":"%s","code":"%s","message":"%s"}\n' \
            "$timestamp" "$run_id" "$event" "$phase" "$severity" "$code" "$message" > "$tmp" 2>/dev/null \
            && mv "$tmp" "$STT_STATUS_FILE" 2>/dev/null || rm -f "$tmp"
        [[ -f "$STT_STATUS_FILE" ]] && cat "$STT_STATUS_FILE" >> "$STT_EVENTS_FILE" 2>/dev/null || true
    fi
}

stt_append_metrics_json() {
    stt_runtime_init
    printf '%s\n' "$1" >> "$STT_METRICS_FILE" 2>/dev/null || true
}
