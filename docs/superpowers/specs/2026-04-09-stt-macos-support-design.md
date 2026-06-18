# STT macOS Support — Design

> Historical design note: this document describes the old skhd-based macOS
> support design from April 2026. Current macOS operation is STTBar-first; use
> `docs/superpowers/specs/2026-06-16-sttbar-native-macos-app-design.md`,
> `CLAUDE.md`, and `install.sh` for current behavior.

**Date:** 2026-04-09
**Status:** Approved (ready for implementation plan)
**Scope:** Add macOS support to the STT Terminal Tool alongside the existing Linux/X11 implementation. Single installer auto-detects the OS and wires up the right platform backend.

## Goal

Enable the existing STT workflow — press hotkey → record mic → Whisper server → paste transcribed text into the focused input — on macOS, without regressing the working Linux implementation. The Linux variant stays unchanged in behavior; shared code paths remain shared.

## Non-Goals

- Auto-installing Homebrew dependencies (stays opt-in manual, consistent with Linux behavior)
- Alternative macOS hotkey backends (Hammerspoon, Karabiner, Raycast) — skhd only
- Windows support
- Changing the ZSH in-terminal widget (`stt.zsh`) — it is already cross-platform

## Architecture Overview

The repo stays flat. No `linux/` or `macos/` subdirectories. Two parallel `stt-global-*.sh` scripts share the underlying `stt-record.sh` / `stt-transcribe.sh` / `stt.zsh`. The installer detects the OS via `uname -s` and routes to one of two install functions.

```
stt-record.sh        shared   — audio capture via sox rec
stt-transcribe.sh    shared   — POST to Whisper server (speaches)
stt.zsh              shared   — ZLE widget for in-terminal use
stt-global.sh        Linux    — X11 toggle (xdotool, xclip, notify-send)
stt-global-mac.sh    macOS    — NEW: toggle (pbcopy, osascript, skhd-triggered)
install.sh           shared   — OS dispatch, per-OS setup functions
docker-compose.yml   shared   — speaches CUDA reference (port 8082)
.env.example         shared   — per-OS comments for Linux vs macOS specifics
```

At install time, the macOS installer copies `stt-global-mac.sh` to `$INSTALL_DIR/stt-global.sh` so that the skhd binding path is OS-agnostic. Only one `stt-global.sh` ever exists in the install directory.

## Components

### `stt-global-mac.sh` (new)

Mirrors the control flow of `stt-global.sh` (toggle via `/tmp/stt-recording.pid`) with macOS primitives:

| Concern          | Linux                                   | macOS                                                                    |
|------------------|-----------------------------------------|--------------------------------------------------------------------------|
| Notifications    | `notify-send`                           | `osascript -e 'display notification "..." with title "STT"'`             |
| Clipboard        | `xclip -selection clipboard`            | `pbcopy`                                                                 |
| Paste keystroke  | `xdotool key --clearmodifiers ctrl+v`   | `osascript -e 'tell application "System Events" to keystroke "v" using command down'` |
| Focus tracking   | `xdotool getactivewindow` + restore     | none needed — skhd does not steal focus                                  |
| Pre-paste sleep  | 0.2s                                    | not needed                                                               |

The script is deliberately shorter than the Linux version because the focus-save/restore dance is unnecessary: skhd dispatches scripts as a background daemon, so the target text field remains focused throughout the record → transcribe → paste cycle.

Notification body interpolation escapes double quotes (`${body//\"/\\\"}`) since `osascript` uses double-quoted strings.

### `stt-record.sh` (modified)

Current behavior always sets `AUDIODEV="$STT_AUDIO_DEVICE"` (default: `default`), which is ALSA-specific. On macOS, sox is built against CoreAudio and should use the system default input when `AUDIODEV` is unset.

**Change:** only export `AUDIODEV` if `STT_AUDIO_DEVICE` is non-empty.

```bash
if [[ -n "${STT_AUDIO_DEVICE:-}" ]]; then
    AUDIODEV="$STT_AUDIO_DEVICE" rec -q -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
else
    rec -q -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
fi
```

This is backward compatible with Linux (`.env` default `STT_AUDIO_DEVICE="default"` still works) and lets macOS users leave the variable empty.

### `stt-transcribe.sh`, `stt.zsh` (unchanged)

Both are already OS-agnostic. The zsh widget uses only ZLE primitives and calls the record/transcribe scripts. The transcribe script is pure `curl` + `jq`.

### `install.sh` (restructured)

Top-level dispatch added near the top:

```bash
OS="$(uname -s)"
case "$OS" in
    Linux)  ;;
    Darwin) ;;
    *) error "Unsupported OS: $OS"; exit 1 ;;
esac
```

Existing install/uninstall logic is refactored into:

- `install_linux` / `uninstall_linux` — current behavior verbatim (dep check with apt/pacman hints, GNOME shortcut registration, file copy, `.zshrc` source line)
- `install_macos` / `uninstall_macos` — new (see below)
- Shared helpers: `copy_shared_files`, `ensure_zshrc_source_line`, `notify`/`info`/`warn`/`error` color helpers

The top-level `install` function becomes a thin wrapper that dispatches by OS:

```bash
install() {
    case "$OS" in
        Linux)  install_linux ;;
        Darwin) install_macos ;;
    esac
}
```

Same for `uninstall`.

### `install_macos` — steps

1. **Dependency check** — required: `sox` (providing `rec`), `curl`, `jq`, `skhd`. On missing:
   ```
   Missing dependencies: sox, skhd
   Install with:
     brew install sox jq skhd
   ```
   Exit non-zero. No auto-install.
2. **Create `$INSTALL_DIR`** (`~/.local/share/stt` by default, same as Linux).
3. **Copy files:**
   - `stt-record.sh`, `stt-transcribe.sh`, `stt.zsh`, `docker-compose.yml` → as-is
   - `stt-global-mac.sh` → renamed to `$INSTALL_DIR/stt-global.sh`
   - `.env.example` → `.env` if no existing `.env` (with warning otherwise, matching Linux)
   - chmod +x on all `.sh`
4. **`.zshrc` source line** — identical to Linux path.
5. **skhd config registration** — ensure `~/.config/skhd/skhdrc` exists and contains:
   ```
   # STT Speech to Text
   cmd + shift - space : $HOME/.local/share/stt/stt-global.sh
   ```
   Detection: grep for `stt-global.sh` in existing skhdrc. If present → warn and skip. If absent → append with a blank line separator.
6. **Start skhd service** — `brew services start skhd` (no-op if already running). If `brew services` is unavailable, print a manual-start hint and continue.
7. **Permissions guidance** — print instructions and offer to open System Settings:
   ```
   warn "macOS permissions required (one-time):"
     1. First Cmd+Shift+Space → macOS prompts to allow skhd
     2. Grant these permissions manually in System Settings:
        • Privacy & Security → Microphone → enable 'skhd'
        • Privacy & Security → Accessibility → enable 'skhd'
   ```
   Then prompt `Open Accessibility settings now? [y/N]`. On yes:
   ```
   open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
   ```

### `uninstall_macos` — steps

1. Remove `.zshrc` source line (shared logic with Linux).
2. Remove the STT block from `~/.config/skhd/skhdrc` (sed: delete the comment line and the binding line).
3. Restart skhd: `brew services restart skhd` (only if skhdrc exists and brew services is available).
4. Remove `$INSTALL_DIR`.
5. Do **not** touch granted TCC permissions or `brew services` state for skhd itself — the user may be using skhd for other bindings. Out of scope to revoke.

## Configuration Changes

### `.env.example`

Port default updated to match the user's deployment and docker-compose. The file now flags which settings are OS-specific.

```bash
# STT Terminal Tool Configuration

# Whisper server URL (speaches / faster-whisper OpenAI-compatible API).
# Point this at wherever you run the whisper container.
STT_SERVER_URL="http://localhost:8082/v1/audio/transcriptions"

# Language for transcription (ISO 639-1: "de", "en", or "auto").
STT_LANGUAGE="de"

# ZSH in-terminal hotkey (^ = Ctrl). Used by stt.zsh widget. Cross-platform.
STT_HOTKEY="^T"

# Audio input device.
#   Linux (ALSA):   "default" (or a specific card like "hw:1,0")
#   macOS (CoreAudio): leave empty to use the system default input
STT_AUDIO_DEVICE="default"

# Whisper model (see speaches docs for available IDs).
STT_MODEL="Systran/faster-whisper-base"

# Docker host port for the whisper server (container listens on 8000 internally).
STT_DOCKER_PORT="8082"

# Model TTL in seconds: -1=never unload, 0=unload immediately, >0=seconds idle.
STT_MODEL_TTL="-1"
```

### `docker-compose.yml`

Only change: default `STT_DOCKER_PORT` from `8000` to `8082` (matches the user's running deployment on `192.168.30.30:8082`). Compose file is deployed on the AI server, not the Mac — on macOS it is only copied as reference.

## Data Flow

```
┌──────────────┐  Cmd+Shift+Space   ┌─────────┐    exec     ┌──────────────────┐
│ Any macOS app│ ───────────────▶  │  skhd   │ ──────────▶ │ stt-global.sh    │
│ (focused tf) │                    └─────────┘              │ (formerly        │
└──────────────┘                                             │  stt-global-mac) │
        ▲                                                    └────────┬─────────┘
        │                                                             │
        │                              ┌──────────────────────────────┼─────────┐
        │ Cmd+V (osascript)            │                              │         │
        │                              ▼                              ▼         │
        │                    ┌──────────────────┐          ┌─────────────────┐  │
        │                    │ stt-record.sh    │          │ stt-transcribe  │  │
        │                    │ sox rec → /tmp   │          │ curl POST       │  │
        │                    └──────────────────┘          └────────┬────────┘  │
        │                                                           │           │
        │                                                           ▼           │
        │                                               ┌──────────────────┐    │
        └────────── pbcopy ◀──────── text ──────────── │ Whisper server   │    │
                                                       │ 192.168.30.30:   │    │
                                                       │ 8082 (speaches)  │    │
                                                       └──────────────────┘    │
```

First call: start recording branch (record.sh start, notify "Recording..."). Second call: stop + transcribe + paste branch.

## Error Handling

Same taxonomy as the Linux script, all surfaced via `osascript display notification`:

| Condition                                 | Notification                                         | Exit |
|-------------------------------------------|------------------------------------------------------|------|
| `stt-record.sh start` fails               | "Could not start recording. sox installed?"          | 1    |
| Empty recording (double-tap)              | "Recording failed or empty."                          | 1    |
| Whisper server unreachable or non-200     | "Transcription failed. Whisper server up?"           | 1    |
| Empty transcription result                | Same as above                                        | 1    |
| Stale PID file from crash                 | `stt-record.sh status` self-heals (existing logic)   | —    |

No retries. The user can just re-trigger the hotkey.

## Testing Strategy

Manual, since the feature is pure shell + OS integration. Automated tests would require mocking TCC, skhd, and CoreAudio — not worth the effort.

### Isolated components (no permissions needed)

1. **Dep check dry run:** Rename `skhd` in PATH temporarily or run in a shell without it. `install.sh` must abort with the `brew install` hint.
2. **ZSH widget (`Ctrl+T` in terminal):** validates `stt-record.sh` + `stt-transcribe.sh` against `192.168.30.30:8082`. Completely independent of skhd / permissions. This is the first thing to verify after install — if it works, the audio + API chain is healthy.

### Full integration (after permissions granted)

3. **Fresh install on a clean account** (or after `./install.sh --uninstall`). Verify:
   - Files land in `~/.local/share/stt/`
   - `stt-global.sh` is the macOS variant
   - skhdrc contains the binding
   - `.zshrc` has the source line
4. **Global hotkey** in multiple app types:
   - Notes.app (native text field)
   - Safari/Chrome address bar (web input)
   - Slack or Discord (Electron input)
   - Claude Code CLI (terminal running interactive prompt)
5. **Edge cases:**
   - Hotkey double-tap without speech → "Recording failed or empty"
   - Whisper server offline → "Transcription failed"
   - Kill `rec` manually → stale PID → next hotkey press should self-recover
6. **Uninstall:**
   - skhdrc block is gone
   - install dir removed
   - `.zshrc` source line removed
   - `Cmd+Shift+Space` no longer triggers anything

### Cross-OS regression

7. **Linux sanity check:** Run the updated `install.sh` on your working Linux box. Verify:
   - OS dispatch picks `install_linux`
   - GNOME shortcut still registers
   - `stt-record.sh` modification does not break ALSA capture (`AUDIODEV=default` still set)
   - ZSH widget still works
   - `.env.example` changes (port 8082) don't break existing `.env` files (which are preserved)

## Risks & Mitigations

| Risk                                                      | Mitigation                                                                                           |
|-----------------------------------------------------------|------------------------------------------------------------------------------------------------------|
| User denies Accessibility permission → paste silently fails | Text is already on clipboard via `pbcopy`. User can manually Cmd+V. Add a clarifying notification on the *first* paste attempt ("text copied — grant Accessibility to auto-paste")? Out of scope for v1; document in install output. |
| skhd not running as a service                             | Installer runs `brew services start skhd`. Fallback: print manual-start instructions.               |
| Existing user skhdrc with unrelated bindings              | Installer appends, does not overwrite. Uninstall uses targeted sed, not file deletion.              |
| `Cmd+Shift+Space` already bound (e.g., Raycast)           | skhd silently loses the race. Documented in install output as a troubleshooting hint.               |
| sox not on Homebrew PATH because it was installed via another manager | Dep check uses `command -v rec`, which works regardless of source.                                  |

## Open Questions

None. All decisions captured above.

## Rollout

Single PR against `master`. No feature flag. Linux behavior is unchanged; macOS support is additive. Merge order:

1. Refactor `install.sh` into `install_linux` / `install_macos` dispatch (Linux still works identically).
2. Modify `stt-record.sh` to conditionally set `AUDIODEV`.
3. Add `stt-global-mac.sh`.
4. Implement `install_macos` + `uninstall_macos`.
5. Update `.env.example` and `docker-compose.yml` (port + OS comments).
6. Manual test on macOS, regression test on Linux.
