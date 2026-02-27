# STT Terminal Tool — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a ZSH-integrated speech-to-text tool that records audio via Ctrl+T toggle and transcribes it using a local faster-whisper (speaches) server in Docker.

**Architecture:** Pure shell scripts. A ZLE widget (`stt.zsh`) acts as the entry point, calling helper scripts for recording (`stt-record.sh`) and transcription (`stt-transcribe.sh`). The Whisper server runs as a Docker container with CUDA GPU acceleration. Configuration lives in `.env`.

**Tech Stack:** ZSH (ZLE widgets), Bash, sox, curl, jq, Docker Compose, speaches (faster-whisper)

---

### Task 1: Initialize Git Repository and Create .env Configuration

**Files:**
- Create: `.env`
- Create: `.env.example`
- Create: `.gitignore`

**Step 1: Initialize git repo**

Run: `cd /home/projectmakers/Dokumente/GitHub/STT-SpeachToTerminal && git init`

**Step 2: Create .gitignore**

```gitignore
.env
*.wav
/tmp/
```

**Step 3: Create .env.example with documented defaults**

```bash
# STT Terminal Tool Configuration

# Whisper server URL (speaches/faster-whisper OpenAI-compatible API)
STT_SERVER_URL="http://localhost:8000/v1/audio/transcriptions"

# Language for transcription (ISO 639-1: "de", "en", "auto" for auto-detect)
STT_LANGUAGE="de"

# ZSH hotkey binding (^ = Ctrl)
STT_HOTKEY="^T"

# ALSA audio input device
STT_AUDIO_DEVICE="default"

# Whisper model (tiny, base, small, medium, large-v3)
STT_MODEL="Systran/faster-whisper-base"
```

**Step 4: Create .env from example**

Run: `cp .env.example .env`

**Step 5: Commit**

```bash
git add .gitignore .env.example docs/
git commit -m "init: project structure with config and design docs"
```

---

### Task 2: Create Docker Compose for Speaches (faster-whisper) Server

**Files:**
- Create: `docker-compose.yml`

**Step 1: Write docker-compose.yml**

```yaml
services:
  whisper:
    image: ghcr.io/speaches-ai/speaches:latest-cuda
    container_name: stt-whisper
    ports:
      - "8000:8000"
    volumes:
      - whisper-models:/home/ubuntu/.cache/huggingface/hub
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped

volumes:
  whisper-models:
```

**Step 2: Verify Docker Compose is valid**

Run: `docker compose config`
Expected: YAML output of the resolved config, no errors.

**Step 3: Start the server and verify API is reachable**

Run: `docker compose up -d && sleep 10 && curl -s http://localhost:8000/health || curl -s http://localhost:8000/v1/models`
Expected: Server starts, API responds (may take longer on first run due to model download).

Note: First start will download the default model. This may take a few minutes. If the health check fails, wait and retry: `curl -s http://localhost:8000/v1/models`

**Step 4: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose for speaches whisper server (CUDA)"
```

---

### Task 3: Create Audio Recording Helper Script

**Files:**
- Create: `stt-record.sh`

**Step 1: Write stt-record.sh**

This script starts or stops a sox recording process. It uses a PID file to track the recording state.

```bash
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
```

**Step 2: Make executable**

Run: `chmod +x stt-record.sh`

**Step 3: Test recording manually**

Run: `./stt-record.sh start && sleep 2 && ./stt-record.sh stop`
Expected: Prints the path to a WAV file. Speak into mic during the 2 seconds. File should be > 44 bytes.

Verify: `file /tmp/stt-recording-*.wav`
Expected: `RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 16000 Hz`

**Step 4: Commit**

```bash
git add stt-record.sh
git commit -m "feat: add audio recording helper using sox"
```

---

### Task 4: Create Transcription Helper Script

**Files:**
- Create: `stt-transcribe.sh`

**Step 1: Write stt-transcribe.sh**

```bash
#!/usr/bin/env bash
# stt-transcribe.sh — Send audio file to Whisper server and return text
# Usage: stt-transcribe.sh <audio-file>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_SERVER_URL="${STT_SERVER_URL:-http://localhost:8000/v1/audio/transcriptions}"
STT_LANGUAGE="${STT_LANGUAGE:-de}"
STT_MODEL="${STT_MODEL:-Systran/faster-whisper-base}"

audio_file="${1:-}"

if [[ -z "$audio_file" ]]; then
    echo "Usage: $0 <audio-file>" >&2
    exit 1
fi

if [[ ! -f "$audio_file" ]]; then
    echo "ERROR: File not found: $audio_file" >&2
    exit 1
fi

# POST to OpenAI-compatible transcription endpoint
response="$(curl -s -w "\n%{http_code}" \
    --max-time 30 \
    -X POST "$STT_SERVER_URL" \
    -F "file=@$audio_file" \
    -F "model=$STT_MODEL" \
    -F "language=$STT_LANGUAGE" \
    -F "response_format=json" \
    )"

http_code="$(echo "$response" | tail -n1)"
body="$(echo "$response" | sed '$d')"

if [[ "$http_code" -ne 200 ]]; then
    echo "ERROR: Server returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
fi

# Extract text from JSON response {"text": "..."}
text="$(echo "$body" | jq -r '.text // empty')"

if [[ -z "$text" ]]; then
    echo "ERROR: Empty transcription result" >&2
    exit 1
fi

echo "$text"
```

**Step 2: Make executable**

Run: `chmod +x stt-transcribe.sh`

**Step 3: Test with the recording from Task 3**

Prerequisite: Docker whisper server running (`docker compose up -d`).

Run: `./stt-transcribe.sh /tmp/stt-recording-*.wav`
Expected: Prints the transcribed text to stdout.

**Step 4: Commit**

```bash
git add stt-transcribe.sh
git commit -m "feat: add transcription helper using curl/jq"
```

---

### Task 5: Create ZSH Plugin (ZLE Widget)

**Files:**
- Create: `stt.zsh`

**Step 1: Write stt.zsh**

This is the main ZSH plugin file. It defines a ZLE widget that toggles recording and inserts transcribed text.

```zsh
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
```

**Step 2: Test by sourcing in a terminal**

Run (in a fresh zsh): `source /home/projectmakers/Dokumente/GitHub/STT-SpeachToTerminal/stt.zsh`

Then:
1. Press Ctrl+T → should show "Recording..."
2. Speak something
3. Press Ctrl+T again → should show "Transcribing..." then insert text

**Step 3: Commit**

```bash
git add stt.zsh
git commit -m "feat: add ZSH plugin with ZLE widget for speech-to-text"
```

---

### Task 6: Create Install Script

**Files:**
- Create: `install.sh`

**Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
# install.sh — Install/uninstall STT Terminal Tool
set -euo pipefail

INSTALL_DIR="${STT_INSTALL_DIR:-$HOME/.local/share/stt}"
ZSHRC="$HOME/.zshrc"
SOURCE_LINE="source \"$INSTALL_DIR/stt.zsh\""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

check_deps() {
    local missing=()
    for cmd in sox curl jq docker; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Check for rec (part of sox)
    if ! command -v rec &>/dev/null; then
        missing+=("sox (rec command)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "Install them with:"
        echo "  sudo apt install sox curl jq docker.io docker-compose-v2"
        echo "  # or on Arch: sudo pacman -S sox curl jq docker docker-compose"
        return 1
    fi

    info "All dependencies found"
}

install() {
    echo "=== STT Terminal Tool Installer ==="
    echo ""

    # Check dependencies
    check_deps || exit 1

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Copy files
    cp "$SCRIPT_DIR/stt.zsh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-record.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-transcribe.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/stt-record.sh"
    chmod +x "$INSTALL_DIR/stt-transcribe.sh"

    # Copy .env if not exists
    if [[ ! -f "$INSTALL_DIR/.env" ]]; then
        if [[ -f "$SCRIPT_DIR/.env" ]]; then
            cp "$SCRIPT_DIR/.env" "$INSTALL_DIR/"
        elif [[ -f "$SCRIPT_DIR/.env.example" ]]; then
            cp "$SCRIPT_DIR/.env.example" "$INSTALL_DIR/.env"
        fi
        info "Created config at $INSTALL_DIR/.env"
    else
        warn "Config already exists at $INSTALL_DIR/.env (not overwritten)"
    fi

    # Add source line to .zshrc
    if ! grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
        echo "" >> "$ZSHRC"
        echo "# STT Terminal Tool - Speech to Text via Ctrl+T" >> "$ZSHRC"
        echo "$SOURCE_LINE" >> "$ZSHRC"
        info "Added source line to $ZSHRC"
    else
        warn "Source line already in $ZSHRC"
    fi

    # Copy docker-compose for reference
    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"
        info "Copied docker-compose.yml to $INSTALL_DIR"
    fi

    echo ""
    info "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit config:    nano $INSTALL_DIR/.env"
    echo "  2. Start whisper:  cd $INSTALL_DIR && docker compose up -d"
    echo "  3. Reload shell:   source $ZSHRC"
    echo "  4. Press Ctrl+T to start recording!"
}

uninstall() {
    echo "=== STT Terminal Tool Uninstaller ==="

    # Remove source line from .zshrc
    if [[ -f "$ZSHRC" ]]; then
        sed -i "\|$SOURCE_LINE|d" "$ZSHRC"
        sed -i '/# STT Terminal Tool/d' "$ZSHRC"
        info "Removed source line from $ZSHRC"
    fi

    # Remove install directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        info "Removed $INSTALL_DIR"
    fi

    echo ""
    info "Uninstall complete. Restart your shell."
}

case "${1:-}" in
    --uninstall|-u)
        uninstall
        ;;
    --help|-h)
        echo "Usage: $0 [--uninstall]"
        echo ""
        echo "  (no args)    Install STT Terminal Tool"
        echo "  --uninstall  Remove STT Terminal Tool"
        ;;
    *)
        install
        ;;
esac
```

**Step 2: Make executable**

Run: `chmod +x install.sh`

**Step 3: Test install (dry verification)**

Run: `bash -n install.sh`
Expected: No syntax errors.

Run: `./install.sh --help`
Expected: Shows usage text.

**Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add install/uninstall script"
```

---

### Task 7: End-to-End Integration Test

**Files:** None (manual testing)

**Step 1: Ensure whisper server is running**

Run: `cd /home/projectmakers/Dokumente/GitHub/STT-SpeachToTerminal && docker compose up -d`
Wait for model download if first run: `docker compose logs -f whisper`

**Step 2: Verify server is responding**

Run: `curl -s http://localhost:8000/v1/models | jq .`
Expected: JSON listing available models.

**Step 3: Test recording + transcription pipeline standalone**

Run:
```bash
./stt-record.sh start && sleep 3 && ./stt-record.sh stop | xargs ./stt-transcribe.sh
```
Speak during the 3 seconds. Expected: Transcribed text printed to stdout.

**Step 4: Test full ZSH integration**

Open a new zsh terminal, then:
```bash
source ./stt.zsh
```
1. Press Ctrl+T → see "Recording..."
2. Say something (e.g., "Hallo Welt")
3. Press Ctrl+T → see "Transcribing...", then text appears at prompt

**Step 5: Test install script**

Run: `./install.sh`
Verify: `ls ~/.local/share/stt/` shows all files.
Verify: `grep -c "stt.zsh" ~/.zshrc` returns 1.

**Step 6: Commit final state**

```bash
git add -A
git commit -m "docs: finalize project, all components tested"
```

---

## Summary

| Task | Component | ~Duration |
|------|-----------|-----------|
| 1 | Git init + .env config | 2 min |
| 2 | Docker Compose | 3 min (+model download) |
| 3 | stt-record.sh | 5 min |
| 4 | stt-transcribe.sh | 5 min |
| 5 | stt.zsh (ZLE widget) | 5 min |
| 6 | install.sh | 5 min |
| 7 | E2E integration test | 5 min |

**Total:** 7 tasks, each self-contained and independently testable.
