#!/usr/bin/env bash
# stt-global-mac.sh — System-wide STT toggle for macOS
# Triggered by Hammerspoon / skhd global hotkey. First call starts
# recording, second call stops + transcribes + pastes into the focused
# text field.
set -euo pipefail

# Hammerspoon launched from launchd (e.g. after a reboot) has a minimal
# PATH that does NOT include Homebrew, so `rec`, `sox`, `jq` etc. won't
# be found and the background `rec` dies immediately — which makes the
# toggle never reach the "stop" branch. Prepend the common Homebrew
# locations so the script works regardless of how Hammerspoon started.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/stt-runtime.sh" ]] && source "$SCRIPT_DIR/stt-runtime.sh"
stt_runtime_init

# macOS tools such as pbcopy and osascript decode stdin/argv using the
# process locale. Launch agents often run without one, and C.UTF-8 is not
# handled correctly by pbcopy on macOS, causing German umlauts to become
# mojibake like "√§" instead of "ä".
configure_utf8_locale() {
    local locale_candidate="${STT_LOCALE:-}"

    if [[ -z "$locale_candidate" ]]; then
        case "${LANG:-}" in
            *UTF-8|*utf-8|*utf8) locale_candidate="$LANG" ;;
        esac
    fi

    if [[ -z "$locale_candidate" ]]; then
        case "${LC_CTYPE:-}" in
            *UTF-8|*utf-8|*utf8) locale_candidate="$LC_CTYPE" ;;
        esac
    fi

    case "$locale_candidate" in
        ""|C|POSIX|C.UTF-8|*.US-ASCII|*ASCII*) locale_candidate="de_DE.UTF-8" ;;
    esac

    export LANG="$locale_candidate"
    export LC_CTYPE="$locale_candidate"
    export LC_ALL="$locale_candidate"
}

configure_utf8_locale

set_phase() {
    stt_set_phase "$1"
}

notify() {
    if [[ "${STT_NOTIFICATIONS:-1}" == "0" ]]; then
        return 0
    fi

    local body="$1"
    # Escape double quotes for osascript's double-quoted string literal
    local escaped="${body//\"/\\\"}"
    osascript -e "display notification \"$escaped\" with title \"STT\"" 2>/dev/null || true
}

is_recording() {
    [[ "$("$SCRIPT_DIR/stt-record.sh" status 2>/dev/null || true)" == "recording" ]]
}

duration_since_recording_start_ms() {
    local start
    start="$(cat "$STT_RECORDING_STARTED_FILE" 2>/dev/null || true)"
    if [[ "$start" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$(( $(stt_now_ms) - start ))"
    else
        printf '0\n'
    fi
}

append_run_metrics() {
    local mode="$1"
    local wav_bytes="$2"
    local recording_ms="$3"
    local whisper_ms="$4"
    local whisper_chars="$5"
    local postprocess_ms="$6"
    local output_chars="$7"
    local paste_status="$8"
    local timestamp run_id
    timestamp="$(stt_timestamp)"
    run_id="$(stt_current_run_id)"
    if command -v jq >/dev/null 2>&1; then
        stt_append_metrics_json "$(jq -n \
            --arg schema "1" \
            --arg timestamp "$timestamp" \
            --arg run_id "$run_id" \
            --arg mode "$mode" \
            --arg paste_status "$paste_status" \
            --argjson wav_bytes "${wav_bytes:-0}" \
            --argjson recording_ms "${recording_ms:-0}" \
            --argjson whisper_ms "${whisper_ms:-0}" \
            --argjson whisper_chars "${whisper_chars:-0}" \
            --argjson postprocess_ms "${postprocess_ms:-0}" \
            --argjson output_chars "${output_chars:-0}" \
            '{
                schema: ($schema | tonumber),
                timestamp: $timestamp,
                run_id: $run_id,
                mode: $mode,
                wav_bytes: $wav_bytes,
                recording_ms: $recording_ms,
                whisper_ms: $whisper_ms,
                whisper_text_chars: $whisper_chars,
                postprocess_ms: $postprocess_ms,
                output_chars: $output_chars,
                paste_status: $paste_status
            }')"
    fi
}

if is_recording; then
    # --- STOP RECORDING & TRANSCRIBE & PASTE ---
    set_phase "whisper"
    stt_status_event "recording_stop_requested" "whisper" "info" "" "Aufnahme wird gestoppt und transkribiert."
    notify "Transcribing..."

    audio_file="$("$SCRIPT_DIR/stt-record.sh" stop 2>/dev/null)" || true
    if [[ -z "$audio_file" ]]; then
        set_phase "error"
        stt_status_event "recording_empty" "error" "error" "recording_empty" "Aufnahme konnte nicht gestartet oder gestoppt werden." "Pruefe Mikrofon/sox."
        notify "Recording failed or was empty."
        exit 1
    fi

    wav_bytes="$(wc -c < "$audio_file" 2>/dev/null | tr -d '[:space:]' || echo 0)"
    recording_ms="$(duration_since_recording_start_ms)"
    whisper_started_ms="$(stt_now_ms)"
    set +e
    transcribe_error_file="$(mktemp)"
    text="$("$SCRIPT_DIR/stt-transcribe.sh" "$audio_file" 2>"$transcribe_error_file")"
    rc=$?
    transcribe_error="$(tr '\n' ' ' < "$transcribe_error_file" | cut -c 1-300)"
    rm -f "$transcribe_error_file"
    set -e
    whisper_ms=$(( $(stt_now_ms) - whisper_started_ms ))
    rm -f "$audio_file"

    if [[ $rc -ne 0 ]] || [[ -z "$text" ]]; then
        set_phase "error"
        stt_status_event "whisper_failed" "error" "error" "whisper_failed" "Transkription fehlgeschlagen." "$transcribe_error"
        notify "Transcription failed. Is the whisper server running?"
        exit 1
    fi

    # STT_MODE selects how the transcript is processed:
    #   full    (default) -> LLM cleanup in the source language
    #   raw                -> no LLM; text replacements only (TSV, URLs, e-mail)
    #   english            -> LLM cleanup, output translated to English
    stt_mode="${STT_MODE:-full}"
    postprocess_ms=0
    whisper_chars="${#text}"

    if [[ -x "$SCRIPT_DIR/stt-postprocess.sh" ]]; then
        if [[ "$stt_mode" == "raw" ]]; then
            # Skip the LLM but still apply the text replacements. Use the
            # dedicated force-raw override: stt-postprocess.sh sources .env,
            # which may set STT_POSTPROCESS_ENABLED=1 and clobber a plain
            # disable. STT_POSTPROCESS_FORCE_RAW is never in .env, so it wins.
            export STT_POSTPROCESS_FORCE_RAW=1
        else
            set_phase "llm"
            if [[ "$stt_mode" == "english" ]]; then
                export STT_POSTPROCESS_TRANSLATE="Englisch"
            fi
        fi

        postprocess_started_ms="$(stt_now_ms)"
        set +e
        processed="$(printf '%s' "$text" | "$SCRIPT_DIR/stt-postprocess.sh" 2>/dev/null)"
        postprocess_rc=$?
        set -e
        postprocess_ms=$(( $(stt_now_ms) - postprocess_started_ms ))

        if [[ $postprocess_rc -eq 0 ]] && [[ -n "$processed" ]]; then
            text="$processed"
        else
            if stt_truthy "${STT_AUTO_RAW_FALLBACK:-1}"; then
                stt_status_event "postprocess_fallback" "llm" "warning" "postprocess_failed" "Nachbearbeitung fehlgeschlagen, Rohtext/Ersatzwoerter verwendet."
            else
                set_phase "error"
                stt_status_event "postprocess_failed" "error" "error" "postprocess_failed" "Nachbearbeitung fehlgeschlagen und Raw-Fallback ist deaktiviert."
                notify "LLM cleanup failed and Raw fallback is disabled."
                exit 1
            fi
        fi
    fi

    if stt_truthy "${STT_APP_NATIVE_PASTE:-0}"; then
        umask 077
        printf '%s' "$text" > "$STT_RESULT_FILE"
        append_run_metrics "$stt_mode" "$wav_bytes" "$recording_ms" "$whisper_ms" "$whisper_chars" "$postprocess_ms" "${#text}" "native_pending"
        set_phase "done"
        stt_status_event "paste_native_pending" "done" "info" "" "Transkript fuer STTBar bereit." "output_chars=${#text}"
        rm -f "$STT_RECORDING_STARTED_FILE" "$STT_RUN_ID_FILE" 2>/dev/null || true
        exit 0
    fi

    # Put text on clipboard (always — fallback for manual paste)
    printf '%s' "$text" | pbcopy

    # Paste into whatever field currently has focus. The triggering app
    # (STTBar / Hammerspoon) does not steal focus, so the target field is
    # still active. Requires Accessibility permission for the triggering app.
    #
    # IMPORTANT: do not let a missing permission abort the script (set -e).
    # The text is already on the clipboard, so on failure we report a
    # distinct phase and tell the user to paste manually instead of flashing
    # a hard error and losing the result.
    if osascript -e 'tell application "System Events" to keystroke "v" using command down' 2>/dev/null; then
        set_phase "done"
        append_run_metrics "$stt_mode" "$wav_bytes" "$recording_ms" "$whisper_ms" "$whisper_chars" "$postprocess_ms" "${#text}" "osascript_ok"
        stt_status_event "done" "done" "info" "" "Transkript eingefuegt." "output_chars=${#text}"
        notify "$text"
    else
        set_phase "done"
        append_run_metrics "$stt_mode" "$wav_bytes" "$recording_ms" "$whisper_ms" "$whisper_chars" "$postprocess_ms" "${#text}" "clipboard_only"
        stt_status_event "paste_failed_clipboard_ok" "done" "warning" "paste_permission_missing" "Text liegt in der Zwischenablage, Einfuegen per Cmd+V oder Accessibility aktivieren."
        notify "Text liegt in der Zwischenablage — mit ⌘V einfügen. (Bedienungshilfen-Berechtigung fehlt)"
    fi
    rm -f "$STT_RECORDING_STARTED_FILE" "$STT_RUN_ID_FILE" 2>/dev/null || true
else
    # --- START RECORDING ---
    if ! "$SCRIPT_DIR/stt-record.sh" start >/dev/null 2>&1; then
        set_phase "error"
        stt_status_event "recording_start_failed" "error" "error" "recording_start_failed" "Aufnahme konnte nicht gestartet werden, pruefe Mikrofon/sox."
        notify "Could not start recording. Is sox installed?"
        exit 1
    fi

    set_phase "recording"
    notify "Recording... (Cmd+Shift+Space to stop)"
fi
