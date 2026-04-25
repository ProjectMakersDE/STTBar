# Global STT Hotkey & Whisper Model Persistence

**Date:** 2026-02-27
**Status:** Approved

## Problem

1. STT only works in ZSH terminals (ZLE widget). It does not work in Claude Code's console or any other application.
2. The Whisper model unloads from VRAM after 300s of inactivity (Speaches default), causing slow first-transcription after idle periods.

## Solution

### 1. Whisper Model Persistence

Add `STT_MODEL_TTL=-1` to the Docker container environment. This tells Speaches to never unload the STT model from VRAM.

- New `.env` variable: `STT_MODEL_TTL="-1"`
- Passed through `docker-compose.yml` as environment variable
- Values: `-1` (never unload), `0` (immediate unload), `>0` (seconds idle before unload)

### 2. System-wide STT Toggle Script (`stt-global.sh`)

A new script that provides the same toggle UX as the ZSH widget but works system-wide via X11.

**Flow:**
1. User presses Ctrl+T (first time) → recording starts, notification shown
2. User speaks
3. User presses Ctrl+T (second time) → recording stops, audio transcribed, text pasted into focused app

**Text injection:** Clipboard-based (`xclip -selection clipboard` + `xdotool key ctrl+shift+v`). Chosen over `xdotool type` for reliability with German keyboard layout and special characters (ä, ö, ü, ß).

**Visual feedback:** `notify-send` desktop notifications for recording state and transcription result.

**Reuses:** Existing `stt-record.sh` (recording) and `stt-transcribe.sh` (transcription) scripts.

**State management:** Same PID file mechanism (`/tmp/stt-recording.pid`) as existing scripts.

### 3. Hotkey Binding via GNOME Custom Shortcuts

The installer registers Ctrl+T as a GNOME custom shortcut pointing to `stt-global.sh`.

- Uses `gsettings` for registration/removal
- Replaces Ctrl+T in ALL applications (Browser New Tab, Claude Code Toggle Todos, etc.)
- The ZSH ZLE plugin is not removed but becomes redundant when the global hotkey is active

### 4. Additional Dependencies

- `xdotool` — keyboard simulation for paste
- `xclip` — clipboard access
- `libnotify` / `notify-send` — desktop notifications

### 5. Installer Changes

- `install.sh` checks for new dependencies (xdotool, xclip, notify-send)
- Registers GNOME custom shortcut for Ctrl+T
- Uninstall removes the shortcut

## Architecture

```
Ctrl+T (X11 global hotkey via GNOME)
  │
  ▼
stt-global.sh (toggle script)
  │
  ├─ 1st press: stt-record.sh start + notify-send "Recording..."
  │
  └─ 2nd press: stt-record.sh stop
                  │
                  ▼
              stt-transcribe.sh → Whisper API (Docker)
                  │
                  ▼
              xclip (clipboard) + xdotool key ctrl+shift+v (paste)
              + notify-send "Done: <text>"
```

## Constraints

- X11 only (no Wayland support in this iteration)
- German keyboard layout must be handled correctly (clipboard approach ensures this)
- System hotkey overrides Ctrl+T in all applications
