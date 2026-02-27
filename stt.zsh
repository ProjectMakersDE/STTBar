# stt.zsh — ZSH Plugin for Speech-to-Text via Whisper
# Source this file in your .zshrc: source /path/to/stt.zsh

# Resolve plugin directory
STT_PLUGIN_DIR="${0:A:h}"

# Load config
[[ -f "$STT_PLUGIN_DIR/.env" ]] && source "$STT_PLUGIN_DIR/.env"

# State tracking
typeset -g _stt_recording=0

stt-widget() {
    if (( _stt_recording == 0 )); then
        # --- START RECORDING ---
        _stt_recording=1
        zle -M "Recording... (${STT_HOTKEY:-^T} to stop)"

        # Start recording in background
        "$STT_PLUGIN_DIR/stt-record.sh" start >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            _stt_recording=0
            zle -M "ERROR: Could not start recording. Is sox installed?"
            return 1
        fi
    else
        # --- STOP RECORDING & TRANSCRIBE ---
        _stt_recording=0
        zle -M "Transcribing..."

        # Stop recording, get file path
        local audio_file
        audio_file="$("$STT_PLUGIN_DIR/stt-record.sh" stop 2>/dev/null)"
        if [[ $? -ne 0 ]] || [[ -z "$audio_file" ]]; then
            zle -M "ERROR: Recording failed or was empty."
            return 1
        fi

        # Transcribe
        local text
        text="$("$STT_PLUGIN_DIR/stt-transcribe.sh" "$audio_file" 2>/dev/null)"
        local exit_code=$?

        # Cleanup temp file
        rm -f "$audio_file" /tmp/stt-record-file

        if [[ $exit_code -ne 0 ]] || [[ -z "$text" ]]; then
            zle -M "ERROR: Transcription failed. Is the whisper server running?"
            return 1
        fi

        # Insert text at cursor position
        LBUFFER+="$text"
        zle -M ""
    fi

    zle reset-prompt
}

# Register as ZLE widget
zle -N stt-widget

# Bind to hotkey
bindkey "${STT_HOTKEY:-^T}" stt-widget
