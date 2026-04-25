# Global STT Hotkey & Whisper Model Persistence — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make STT work system-wide (including Claude Code) via X11 global hotkey, and keep the Whisper model permanently loaded in VRAM.

**Architecture:** New `stt-global.sh` script reuses existing `stt-record.sh` and `stt-transcribe.sh`. Text injection via clipboard (`xclip`) + paste simulation (`xdotool`). Hotkey bound via GNOME custom shortcuts with fallback instructions for other DEs.

**Tech Stack:** Bash, xdotool, xclip, notify-send, gsettings (GNOME), sox, curl, jq (existing)

---

### Task 1: Add STT_MODEL_TTL to configuration

**Files:**
- Modify: `.env:19` (add new variable after STT_DOCKER_PORT)
- Modify: `.env.example:19` (add new variable after STT_DOCKER_PORT)
- Modify: `docker-compose.yml:8` (add environment variable)

**Step 1: Add STT_MODEL_TTL to `.env`**

Append after line 19 (STT_DOCKER_PORT):

```bash
# Model TTL: seconds idle before unloading from VRAM (-1=never, 0=immediate, >0=seconds)
STT_MODEL_TTL="-1"
```

**Step 2: Add STT_MODEL_TTL to `.env.example`**

Same addition as `.env`.

**Step 3: Pass STT_MODEL_TTL through docker-compose.yml**

Add to the `environment:` section after the PRELOAD_MODELS line (line 8):

```yaml
    environment:
      - PRELOAD_MODELS=["${STT_MODEL:-Systran/faster-whisper-base}"]
      - STT_MODEL_TTL=${STT_MODEL_TTL:--1}
```

**Step 4: Verify docker-compose config is valid**

Run: `cd /home/projectmakers/Dokumente/GitHub/STT-SpeachToTerminal && docker compose config`
Expected: Valid YAML output with both environment variables visible.

**Step 5: Commit**

```bash
git add .env .env.example docker-compose.yml
git commit -m "feat: add STT_MODEL_TTL to keep whisper model in VRAM"
```

---

### Task 2: Create stt-global.sh

**Files:**
- Create: `stt-global.sh`

**Step 1: Create the global STT toggle script**

Create `stt-global.sh`:

```bash
#!/usr/bin/env bash
# stt-global.sh — System-wide STT toggle for X11
# Triggered by global hotkey. First call starts recording, second call stops + transcribes + pastes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_PID_FILE="/tmp/stt-recording.pid"

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
    # --- STOP RECORDING & TRANSCRIBE & PASTE ---
    notify normal 2000 "Transcribing..."

    audio_file="$("$SCRIPT_DIR/stt-record.sh" stop 2>/dev/null)" || true
    if [[ -z "$audio_file" ]]; then
        notify critical 3000 "Recording failed or was empty."
        exit 1
    fi

    text="$("$SCRIPT_DIR/stt-transcribe.sh" "$audio_file" 2>/dev/null)"
    rc=$?
    rm -f "$audio_file"

    if [[ $rc -ne 0 ]] || [[ -z "$text" ]]; then
        notify critical 3000 "Transcription failed. Is the whisper server running?"
        exit 1
    fi

    # Inject text via clipboard + paste
    printf '%s' "$text" | xclip -selection clipboard
    sleep 0.15
    xdotool key --clearmodifiers ctrl+shift+v

    notify normal 2000 "$text"
else
    # --- START RECORDING ---
    if ! "$SCRIPT_DIR/stt-record.sh" start >/dev/null 2>&1; then
        notify critical 3000 "Could not start recording. Is sox installed?"
        exit 1
    fi

    notify normal 5000 "Recording... (Ctrl+T to stop)"
fi
```

**Step 2: Make it executable and test manually**

Run: `chmod +x stt-global.sh`
Run: `./stt-global.sh` (should start recording, show notification)
Run: `./stt-global.sh` (should stop, transcribe, paste — verify whisper container is up)

**Step 3: Commit**

```bash
git add stt-global.sh
git commit -m "feat: add system-wide STT toggle script for X11"
```

---

### Task 3: Update install.sh with global hotkey support

**Files:**
- Modify: `install.sh`

**Step 1: Add new dependencies to check_deps()**

In `check_deps()` (line 19-46), add checks for `xdotool`, `xclip`, and `notify-send` after the existing checks but mark them as optional (for global mode only):

```bash
    # Optional deps for global hotkey mode
    local missing_global=()
    for cmd in xdotool xclip notify-send; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_global+=("$cmd")
        fi
    done

    if [[ ${#missing_global[@]} -gt 0 ]]; then
        warn "Missing optional dependencies for global hotkey: ${missing_global[*]}"
        echo "  Install for system-wide STT (Claude Code, any app):"
        echo "  sudo apt install xdotool xclip libnotify-bin"
        echo "  # or on Arch: sudo pacman -S xdotool xclip libnotify"
    else
        info "Global hotkey dependencies found (xdotool, xclip, notify-send)"
    fi
```

**Step 2: Copy stt-global.sh in install()**

After line 63 (chmod stt-transcribe.sh), add:

```bash
    cp "$SCRIPT_DIR/stt-global.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/stt-global.sh"
```

**Step 3: Add GNOME shortcut registration function**

Add before the `install()` function:

```bash
register_gnome_shortcut() {
    # Only attempt if gsettings and GNOME settings daemon are available
    if ! command -v gsettings &>/dev/null; then
        return 1
    fi

    local shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/stt/"
    local shortcut_key="<Control>t"

    # Get current custom keybindings list
    local current
    current="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)" || return 1

    # Check if already registered
    if echo "$current" | grep -q "stt"; then
        warn "GNOME shortcut already registered"
        return 0
    fi

    # Append our shortcut to the list
    if [[ "$current" == "@as []" ]]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$shortcut_path']"
    else
        local new_list="${current%]*}, '$shortcut_path']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list"
    fi

    # Set shortcut properties
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" name 'STT Speech to Text'
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" command "$INSTALL_DIR/stt-global.sh"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" binding "$shortcut_key"

    return 0
}

unregister_gnome_shortcut() {
    if ! command -v gsettings &>/dev/null; then
        return 1
    fi

    local shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/stt/"

    local current
    current="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)" || return 1

    # Remove our entry from the list
    local new_list
    new_list="$(echo "$current" | sed "s|'$shortcut_path', ||g; s|, '$shortcut_path'||g; s|'$shortcut_path'||g")"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list" 2>/dev/null || true

    # Reset shortcut properties
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" name 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" command 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" binding 2>/dev/null || true

    return 0
}
```

**Step 4: Call shortcut registration in install()**

After the docker-compose copy block (line 91), add:

```bash
    # Register global hotkey
    if command -v xdotool &>/dev/null && command -v xclip &>/dev/null; then
        if register_gnome_shortcut; then
            info "Registered Ctrl+T as global STT hotkey (GNOME)"
        else
            warn "Could not register GNOME shortcut automatically."
            echo "  Register Ctrl+T manually in your desktop settings:"
            echo "  Command: $INSTALL_DIR/stt-global.sh"
        fi
    fi
```

**Step 5: Call shortcut removal in uninstall()**

In `uninstall()`, before the directory removal (line 114), add:

```bash
    # Remove global hotkey
    unregister_gnome_shortcut 2>/dev/null && info "Removed GNOME shortcut" || true
```

**Step 6: Update post-install instructions**

Replace the "Next steps" block (lines 96-100) with:

```bash
    echo "Next steps:"
    echo "  1. Edit config:    nano $INSTALL_DIR/.env"
    echo "  2. Start whisper:  cd $INSTALL_DIR && docker compose up -d"
    echo "  3. Reload shell:   source $ZSHRC"
    echo ""
    echo "Usage:"
    echo "  Terminal (ZSH):  Press Ctrl+T to start/stop recording"
    echo "  Anywhere (X11):  Ctrl+T via global hotkey (Claude Code, any app)"
```

**Step 7: Test install and uninstall**

Run: `./install.sh`
Expected: All files copied, shortcut registered, instructions printed.

Run: `./install.sh --uninstall`
Expected: Files removed, shortcut unregistered.

**Step 8: Commit**

```bash
git add install.sh
git commit -m "feat: install global STT hotkey with GNOME shortcut support"
```

---

### Task 4: Manual end-to-end test

**Step 1: Ensure whisper container is running**

Run: `cd ~/.local/share/stt && docker compose up -d`
Verify: `curl -s http://localhost:8000/v1/models | jq .`
Expected: JSON with model info.

**Step 2: Test global hotkey in a non-ZSH app**

1. Open a text editor (gedit, Kate, or any GUI app)
2. Press Ctrl+T
3. Verify notification "Recording..." appears
4. Speak a sentence in German
5. Press Ctrl+T again
6. Verify notification "Transcribing..." appears
7. Verify transcribed text is pasted into the text editor

**Step 3: Test in Claude Code**

1. Start Claude Code in terminal: `claude`
2. Press Ctrl+T
3. Verify notification "Recording..." appears
4. Speak
5. Press Ctrl+T
6. Verify text appears in Claude Code's chat input

**Step 4: Verify model persistence**

Run: `docker logs stt-whisper 2>&1 | grep -i "unload\|ttl\|model"`
Expected: No "unloading model" messages. STT_MODEL_TTL=-1 visible in config.

**Step 5: Final commit (if any test-driven fixes)**

```bash
git add -A
git commit -m "fix: address issues found during end-to-end testing"
```
