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

STT_PID_FILE="/tmp/stt-recording.pid"

set_phase() {
    if [[ -n "${STT_PHASE_FILE:-}" ]]; then
        printf '%s\n' "$1" > "$STT_PHASE_FILE" 2>/dev/null || true
    fi
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
    [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null
}

if is_recording; then
    # --- STOP RECORDING & TRANSCRIBE & PASTE ---
    set_phase "whisper"
    notify "Transcribing..."

    audio_file="$("$SCRIPT_DIR/stt-record.sh" stop 2>/dev/null)" || true
    if [[ -z "$audio_file" ]]; then
        set_phase "error"
        notify "Recording failed or was empty."
        exit 1
    fi

    set +e
    text="$("$SCRIPT_DIR/stt-transcribe.sh" "$audio_file" 2>/dev/null)"
    rc=$?
    set -e
    rm -f "$audio_file"

    if [[ $rc -ne 0 ]] || [[ -z "$text" ]]; then
        set_phase "error"
        notify "Transcription failed. Is the whisper server running?"
        exit 1
    fi

    # STT_MODE selects how the transcript is processed:
    #   full    (default) -> LLM cleanup in the source language
    #   raw                -> no LLM; text replacements only (TSV, URLs, e-mail)
    #   english            -> LLM cleanup, output translated to English
    stt_mode="${STT_MODE:-full}"

    if [[ -x "$SCRIPT_DIR/stt-postprocess.sh" ]]; then
        if [[ "$stt_mode" == "raw" ]]; then
            # Skip the LLM but still apply the text replacements.
            export STT_POSTPROCESS_ENABLED=0
        else
            set_phase "llm"
            if [[ "$stt_mode" == "english" ]]; then
                export STT_POSTPROCESS_TRANSLATE="Englisch"
            fi
        fi

        set +e
        processed="$(printf '%s' "$text" | "$SCRIPT_DIR/stt-postprocess.sh" 2>/dev/null)"
        postprocess_rc=$?
        set -e

        if [[ $postprocess_rc -eq 0 ]] && [[ -n "$processed" ]]; then
            text="$processed"
        fi
    fi

    # Put text on clipboard (always — fallback for manual paste)
    printf '%s' "$text" | pbcopy

    # Paste into whatever field currently has focus.
    # skhd does not steal focus when triggering scripts, so the target
    # field is still active. Requires Accessibility permission for skhd.
    osascript -e 'tell application "System Events" to keystroke "v" using command down'

    set_phase "done"
    notify "$text"
else
    # --- START RECORDING ---
    if ! "$SCRIPT_DIR/stt-record.sh" start >/dev/null 2>&1; then
        set_phase "error"
        notify "Could not start recording. Is sox installed?"
        exit 1
    fi

    set_phase "recording"
    notify "Recording... (Cmd+Shift+Space to stop)"
fi
