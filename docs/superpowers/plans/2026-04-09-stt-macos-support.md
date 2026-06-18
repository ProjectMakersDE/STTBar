# STT macOS Support Implementation Plan

> Historical implementation plan: this skhd-based plan has been superseded by
> the native STTBar path. Keep it as background context only; current work
> should follow `CLAUDE.md`, `install.sh`, and the STTBar design/spec files.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add macOS support to the STT Terminal Tool alongside the existing Linux/X11 implementation, with a single installer that auto-detects the OS.

**Architecture:** Flat repo layout. A new `stt-global-mac.sh` uses `pbcopy` + `osascript` + `skhd`-triggered hotkey. `install.sh` gets an OS dispatch (`uname -s`) and per-OS install/uninstall functions. Shared files (`stt-record.sh`, `stt-transcribe.sh`, `stt.zsh`) stay single-source; `stt-record.sh` becomes AUDIODEV-conditional so CoreAudio defaults work on Mac.

**Tech Stack:** Bash, sox (`rec`), curl, jq, skhd (Homebrew), osascript, pbcopy, GNOME gsettings (Linux only), speaches Whisper server.

**Testing philosophy:** The spec explicitly calls out automated tests as out-of-scope — mocking TCC/skhd/CoreAudio is not worth the effort. Each task includes `bash -n` syntax checks plus targeted smoke tests the engineer can run manually. Full integration testing (Task 9) is a manual checklist the user runs on their Mac after install.

**Reference:** Design spec at `docs/superpowers/specs/2026-04-09-stt-macos-support-design.md`. Read it first.

---

## File Structure

| File | Change | Purpose |
|---|---|---|
| `install.sh` | modify | Add OS dispatch, refactor `install`/`uninstall` into `install_linux`/`install_macos` |
| `stt-record.sh` | modify | Conditional `AUDIODEV` export (empty → CoreAudio default on Mac) |
| `stt-global-mac.sh` | **create** | macOS variant of the global toggle (pbcopy + osascript + notifications) |
| `.env.example` | modify | Port 8000 → 8082, OS-specific comments, `STT_AUDIO_DEVICE` guidance |
| `docker-compose.yml` | modify | Default port 8000 → 8082 |
| `stt-global.sh` | **unchanged** | Linux/X11 version stays verbatim |
| `stt-transcribe.sh` | **unchanged** | OS-agnostic already |
| `stt.zsh` | **unchanged** | OS-agnostic already |

---

## Task 1: Conditional AUDIODEV in stt-record.sh

**Files:**
- Modify: `stt-record.sh:15-23`

**Why first:** Smallest shared change, verifiable in isolation. Linux default (`STT_AUDIO_DEVICE=default`) stays working; Mac gets the "empty → CoreAudio default" path.

- [ ] **Step 1: Read the current file to confirm line numbers**

Run: `sed -n '1,30p' stt-record.sh`
Expected: line 15 sets `STT_AUDIO_DEVICE="${STT_AUDIO_DEVICE:-default}"`, line 21-22 has `AUDIODEV="$STT_AUDIO_DEVICE" rec ...` in `start_recording()`.

- [ ] **Step 2: Change the default from "default" to empty string**

Edit `stt-record.sh`, change line 11:

```bash
# Before:
STT_AUDIO_DEVICE="${STT_AUDIO_DEVICE:-default}"

# After:
STT_AUDIO_DEVICE="${STT_AUDIO_DEVICE:-}"
```

**Note:** Existing Linux users have `STT_AUDIO_DEVICE="default"` in their `.env`, so they're unaffected. The shell default just becomes empty instead of `default` — which the next step handles.

- [ ] **Step 3: Make the AUDIODEV export conditional in start_recording()**

Replace the body of `start_recording()` around line 21-22:

```bash
start_recording() {
    if [[ -f "$STT_PID_FILE" ]] && kill -0 "$(cat "$STT_PID_FILE")" 2>/dev/null; then
        echo "ERROR: Recording already in progress" >&2
        return 1
    fi

    # Record: 16kHz, mono, 16-bit WAV
    # AUDIODEV only set if STT_AUDIO_DEVICE is non-empty (Linux/ALSA).
    # On macOS, leave empty to let sox use the CoreAudio default input.
    if [[ -n "$STT_AUDIO_DEVICE" ]]; then
        AUDIODEV="$STT_AUDIO_DEVICE" rec -q -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    else
        rec -q -r 16000 -c 1 -b 16 "$STT_RECORD_FILE" &
    fi
    local rec_pid=$!
    echo "$rec_pid" > "$STT_PID_FILE"
    echo "$STT_RECORD_FILE"
}
```

- [ ] **Step 4: Syntax check**

Run: `bash -n stt-record.sh`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add stt-record.sh
git commit -m "feat(record): make AUDIODEV conditional for macOS CoreAudio default

STT_AUDIO_DEVICE now defaults to empty instead of 'default'. When empty,
AUDIODEV is not exported, letting sox use the system default (CoreAudio
on macOS). Existing Linux .env files with STT_AUDIO_DEVICE=default are
unaffected."
```

---

## Task 2: Create stt-global-mac.sh

**Files:**
- Create: `stt-global-mac.sh`

- [ ] **Step 1: Create the file**

Create `stt-global-mac.sh` with this exact content:

```bash
#!/usr/bin/env bash
# stt-global-mac.sh — System-wide STT toggle for macOS
# Triggered by skhd global hotkey. First call starts recording, second
# call stops + transcribes + pastes into the focused text field.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

STT_PID_FILE="/tmp/stt-recording.pid"

notify() {
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
    notify "Transcribing..."

    audio_file="$("$SCRIPT_DIR/stt-record.sh" stop 2>/dev/null)" || true
    if [[ -z "$audio_file" ]]; then
        notify "Recording failed or was empty."
        exit 1
    fi

    text="$("$SCRIPT_DIR/stt-transcribe.sh" "$audio_file" 2>/dev/null)"
    rc=$?
    rm -f "$audio_file"

    if [[ $rc -ne 0 ]] || [[ -z "$text" ]]; then
        notify "Transcription failed. Is the whisper server running?"
        exit 1
    fi

    # Put text on clipboard (always — fallback for manual paste)
    printf '%s' "$text" | pbcopy

    # Paste into whatever field currently has focus.
    # skhd does not steal focus when triggering scripts, so the target
    # field is still active. Requires Accessibility permission for skhd.
    osascript -e 'tell application "System Events" to keystroke "v" using command down'

    notify "$text"
else
    # --- START RECORDING ---
    if ! "$SCRIPT_DIR/stt-record.sh" start >/dev/null 2>&1; then
        notify "Could not start recording. Is sox installed?"
        exit 1
    fi

    notify "Recording... (Cmd+Shift+Space to stop)"
fi
```

- [ ] **Step 2: Syntax check**

Run: `bash -n stt-global-mac.sh`
Expected: no output.

- [ ] **Step 3: Make it executable**

Run: `chmod +x stt-global-mac.sh`

- [ ] **Step 4: Verify osascript escaping works for a sample string**

Run:

```bash
body='Hello "world" with quotes'
escaped="${body//\"/\\\"}"
echo "$escaped"
```

Expected output: `Hello \"world\" with quotes`

(We're only confirming the shell substitution logic; actually running osascript is deferred to manual testing on the target Mac.)

- [ ] **Step 5: Commit**

```bash
git add stt-global-mac.sh
git commit -m "feat(macos): add stt-global-mac.sh for system-wide STT on macOS

Toggle script triggered by skhd hotkey. Uses pbcopy + osascript for
clipboard and Cmd+V keystroke injection. No focus save/restore needed —
skhd dispatches without stealing focus, so the target text field stays
active throughout the record/transcribe/paste cycle."
```

---

## Task 3: Refactor install.sh — OS dispatch skeleton

**Files:**
- Modify: `install.sh`

**Goal of this task:** Add `uname -s` detection and rename the existing `install` / `uninstall` functions to `install_linux` / `uninstall_linux`, while keeping Linux behavior byte-identical. No macOS logic yet — that comes in Task 4.

- [ ] **Step 1: Add OS detection near the top of install.sh**

After line 8 (`SCRIPT_DIR=...`), add:

```bash
OS="$(uname -s)"
```

- [ ] **Step 2: Rename `check_deps` → `check_deps_linux`**

Find the function `check_deps()` (line 19) and rename it:

```bash
# Before:
check_deps() {

# After:
check_deps_linux() {
```

Update the one call site inside `install` (currently `check_deps || exit 1`, line 121):

```bash
# Before:
    check_deps || exit 1

# After:
    check_deps_linux || exit 1
```

- [ ] **Step 3: Rename the top-level `install` function to `install_linux`**

Change line 116:

```bash
# Before:
install() {

# After:
install_linux() {
```

- [ ] **Step 4: Rename the top-level `uninstall` function to `uninstall_linux`**

Change line 187:

```bash
# Before:
uninstall() {

# After:
uninstall_linux() {
```

- [ ] **Step 5: Add thin dispatch wrappers `install()` and `uninstall()`**

After the `uninstall_linux` function closes (around line 208), add:

```bash
install() {
    case "$OS" in
        Linux)  install_linux ;;
        Darwin) install_macos ;;
        *) error "Unsupported OS: $OS"; exit 1 ;;
    esac
}

uninstall() {
    case "$OS" in
        Linux)  uninstall_linux ;;
        Darwin) uninstall_macos ;;
        *) error "Unsupported OS: $OS"; exit 1 ;;
    esac
}
```

**Note:** `install_macos` / `uninstall_macos` don't exist yet — they'll be added in Task 4. This is fine because the dispatch only calls them when `$OS == Darwin`, and we're on Linux or running the syntax check. If a Mac user runs this intermediate commit, they'll get a "command not found" error — acceptable for one commit between Task 3 and Task 4.

- [ ] **Step 6: Syntax check**

Run: `bash -n install.sh`
Expected: no output.

- [ ] **Step 7: Verify Linux path still works (dry-run the dispatch logic)**

Run:

```bash
bash -c 'OS=Linux; case "$OS" in Linux) echo linux ;; Darwin) echo mac ;; esac'
```
Expected: `linux`

Run:

```bash
bash -c 'OS=Darwin; case "$OS" in Linux) echo linux ;; Darwin) echo mac ;; esac'
```
Expected: `mac`

- [ ] **Step 8: Commit**

```bash
git add install.sh
git commit -m "refactor(install): add OS dispatch skeleton

Introduces uname -s detection. Renames the existing install/uninstall
functions to install_linux/uninstall_linux and adds thin wrappers that
dispatch by OS. Linux behavior is byte-identical. macOS branch will be
added in the next commit."
```

---

## Task 4: Add install_macos function

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add `check_deps_macos` function**

Insert after `check_deps_linux` (after its closing `}`, before `register_gnome_shortcut`):

```bash
check_deps_macos() {
    local missing=()
    for cmd in sox rec curl jq skhd; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "Install them with:"
        echo "  brew install sox jq skhd"
        return 1
    fi

    info "All dependencies found"
}
```

- [ ] **Step 2: Add `register_skhd_binding` function**

Insert after `check_deps_macos`:

```bash
register_skhd_binding() {
    local skhdrc="$HOME/.config/skhd/skhdrc"
    local binding_cmd="$INSTALL_DIR/stt-global.sh"
    local binding_line="cmd + shift - space : $binding_cmd"

    mkdir -p "$(dirname "$skhdrc")"
    touch "$skhdrc"

    if grep -qF "stt-global.sh" "$skhdrc"; then
        warn "skhd binding for stt-global.sh already present — not modifying $skhdrc"
        return 0
    fi

    # Append with a blank-line separator
    {
        echo ""
        echo "# STT Speech to Text"
        echo "$binding_line"
    } >> "$skhdrc"

    return 0
}

unregister_skhd_binding() {
    local skhdrc="$HOME/.config/skhd/skhdrc"
    [[ -f "$skhdrc" ]] || return 0

    # Remove the "# STT Speech to Text" comment line and any line containing
    # stt-global.sh. Uses BSD sed -i '' (macOS). Two passes keeps the regex
    # simple and avoids GNU/BSD sed portability traps.
    sed -i '' '/# STT Speech to Text/d' "$skhdrc" 2>/dev/null || true
    sed -i '' '/stt-global\.sh/d' "$skhdrc" 2>/dev/null || true

    return 0
}
```

- [ ] **Step 3: Add `install_macos` function**

Insert after `uninstall_linux`'s closing `}`, before the `install()` dispatch wrapper you added in Task 3:

```bash
install_macos() {
    echo "=== STT Terminal Tool Installer (macOS) ==="
    echo ""

    check_deps_macos || exit 1

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Copy shared files
    cp "$SCRIPT_DIR/stt.zsh"          "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-record.sh"    "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-transcribe.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/stt-record.sh"
    chmod +x "$INSTALL_DIR/stt-transcribe.sh"

    # Copy the macOS global script as stt-global.sh (OS-agnostic name
    # inside the install dir, so the skhd binding path doesn't depend
    # on the source filename).
    cp "$SCRIPT_DIR/stt-global-mac.sh" "$INSTALL_DIR/stt-global.sh"
    chmod +x "$INSTALL_DIR/stt-global.sh"

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
        echo "# STT Terminal Tool - Speech to Text" >> "$ZSHRC"
        echo "$SOURCE_LINE" >> "$ZSHRC"
        info "Added source line to $ZSHRC"
    else
        warn "Source line already in $ZSHRC"
    fi

    # Copy docker-compose for reference (the Mac doesn't run the container,
    # but keeping it in the install dir lets the user deploy it elsewhere).
    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"
        info "Copied docker-compose.yml to $INSTALL_DIR"
    fi

    # Register skhd binding
    if register_skhd_binding; then
        info "Registered Cmd+Shift+Space as global STT hotkey (skhd)"
    else
        warn "Could not register skhd binding automatically."
        echo "  Add manually to ~/.config/skhd/skhdrc:"
        echo "  cmd + shift - space : $INSTALL_DIR/stt-global.sh"
    fi

    # Start skhd service (idempotent — no-op if already running)
    if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q '^skhd'; then
        brew services start skhd >/dev/null 2>&1 || true
        info "skhd service started (or already running)"
    else
        warn "Could not start skhd via brew services. Start it manually:"
        echo "  brew services start skhd"
    fi

    echo ""
    info "Installation complete!"
    echo ""
    warn "macOS permissions required (one-time setup):"
    echo "  On the first Cmd+Shift+Space press, macOS will prompt to allow"
    echo "  skhd to control your computer and access the microphone."
    echo ""
    echo "  Grant these in System Settings:"
    echo "    - Privacy & Security -> Microphone      -> enable 'skhd'"
    echo "    - Privacy & Security -> Accessibility   -> enable 'skhd'"
    echo ""
    read -r -p "Open Accessibility settings now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    fi

    echo ""
    echo "Next steps:"
    echo "  1. Edit config:    nano $INSTALL_DIR/.env"
    echo "     (point STT_SERVER_URL at your whisper server, e.g. http://192.168.30.30:8082/v1/audio/transcriptions)"
    echo "  2. Reload shell:   source $ZSHRC"
    echo ""
    echo "Usage:"
    echo "  Terminal (ZSH):  Press Ctrl+T to start/stop recording"
    echo "  Anywhere:        Press Cmd+Shift+Space to start/stop recording"
}
```

- [ ] **Step 4: Add `uninstall_macos` function**

Insert right after `install_macos`:

```bash
uninstall_macos() {
    echo "=== STT Terminal Tool Uninstaller (macOS) ==="

    # Remove source line from .zshrc
    if [[ -f "$ZSHRC" ]]; then
        # BSD sed needs the empty-string arg to -i
        sed -i '' "\|$SOURCE_LINE|d" "$ZSHRC" 2>/dev/null || true
        sed -i '' '/# STT Terminal Tool/d' "$ZSHRC" 2>/dev/null || true
        info "Removed source line from $ZSHRC"
    fi

    # Remove skhd binding (leaves skhd service running — user may use it
    # for other bindings, so we don't touch brew services state)
    unregister_skhd_binding && info "Removed skhd binding" || true

    # Reload skhd config so the removed binding takes effect immediately
    if command -v brew &>/dev/null; then
        brew services restart skhd >/dev/null 2>&1 || true
    fi

    # Remove install directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        info "Removed $INSTALL_DIR"
    fi

    echo ""
    info "Uninstall complete. Restart your shell."
    warn "Note: skhd itself and any granted permissions (Accessibility, Microphone)"
    echo "      were not removed. Revoke those manually in System Settings if desired."
}
```

**Note on `sed -i`:** BSD sed (macOS) requires an explicit empty-string argument after `-i`: `sed -i '' 'expr' file`. GNU sed (Linux) does NOT take that argument. That's why the Linux `uninstall_linux` uses `sed -i` and the macOS version uses `sed -i ''`. Do not "fix" this — they are different binaries.

- [ ] **Step 5: Syntax check**

Run: `bash -n install.sh`
Expected: no output.

- [ ] **Step 6: Structural sanity check**

Run:

```bash
grep -n '^install_macos\|^uninstall_macos\|^check_deps_macos\|^register_skhd_binding\|^unregister_skhd_binding\|^install_linux\|^uninstall_linux\|^install()\|^uninstall()' install.sh
```
Expected output (order may vary slightly but all should be present):

```
check_deps_linux() {
check_deps_macos() {
register_skhd_binding() {
unregister_skhd_binding() {
install_linux() {
uninstall_linux() {
install_macos() {
uninstall_macos() {
install() {
uninstall() {
```

(Use `grep -E '^(install|uninstall|check_deps|register_skhd|unregister_skhd).*\(\) \{' install.sh` if you want a cleaner list.)

- [ ] **Step 7: Commit**

```bash
git add install.sh
git commit -m "feat(install): add macOS install/uninstall functions

Implements install_macos and uninstall_macos with:
- Dependency check (sox, rec, curl, jq, skhd) with brew install hint
- File copy including stt-global-mac.sh -> stt-global.sh rename
- skhd binding registration in ~/.config/skhd/skhdrc (cmd+shift-space)
- brew services start/restart for skhd
- Permissions guidance with optional 'open System Settings' prompt
- BSD sed compatibility (-i '')"
```

---

## Task 5: Update .env.example

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Replace the file contents**

Overwrite `.env.example` with:

```bash
# STT Terminal Tool Configuration

# Whisper server URL (speaches / faster-whisper OpenAI-compatible API).
# Point this at wherever you run the whisper container.
# Example remote server: http://192.168.30.30:8082/v1/audio/transcriptions
STT_SERVER_URL="http://localhost:8082/v1/audio/transcriptions"

# Language for transcription (ISO 639-1: "de", "en", or "auto" to auto-detect)
STT_LANGUAGE="de"

# ZSH in-terminal hotkey (^ = Ctrl). Used by stt.zsh widget. Cross-platform.
STT_HOTKEY="^T"

# Audio input device.
#   Linux (ALSA):      "default" (or a specific card like "hw:1,0")
#   macOS (CoreAudio): leave empty to use the system default input
STT_AUDIO_DEVICE="default"

# Whisper model (tiny, base, small, medium, large-v3)
STT_MODEL="Systran/faster-whisper-base"

# Docker host port for the whisper server (container always listens on 8000 internally)
STT_DOCKER_PORT="8082"

# Model TTL: seconds idle before unloading from VRAM (-1=never, 0=immediate, >0=seconds)
STT_MODEL_TTL="-1"
```

- [ ] **Step 2: Verify it parses as a valid shell file**

Run: `bash -n .env.example`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .env.example
git commit -m "chore(env): update defaults for port 8082 and macOS guidance

- STT_SERVER_URL port 8000 -> 8082 (matches current deployment)
- STT_DOCKER_PORT 8000 -> 8082
- Add per-OS notes for STT_AUDIO_DEVICE (ALSA vs CoreAudio)
- Mention remote server example in comments"
```

---

## Task 6: Update docker-compose.yml default port

**Files:**
- Modify: `docker-compose.yml:6`

- [ ] **Step 1: Read the file to confirm current content**

Run: `cat docker-compose.yml`
Expected: line 6 contains `- "${STT_DOCKER_PORT:-8000}:8000"`.

- [ ] **Step 2: Change the default**

Edit `docker-compose.yml`:

```yaml
# Before:
      - "${STT_DOCKER_PORT:-8000}:8000"

# After:
      - "${STT_DOCKER_PORT:-8082}:8000"
```

The container still listens on 8000 internally — only the host-side default changes.

- [ ] **Step 3: Verify YAML is still valid**

Run: `python3 -c 'import yaml, sys; yaml.safe_load(open("docker-compose.yml"))' && echo OK`
Expected: `OK`

(If `python3` or `pyyaml` isn't available, skip and rely on the next `docker compose config` check instead.)

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml
git commit -m "chore(compose): default host port 8000 -> 8082

Matches the existing deployment and the updated .env.example. Container
port stays at 8000 internally."
```

---

## Task 7: Linux regression check (syntax + structural)

**Why:** The spec explicitly lists cross-OS regression as a test case. We can't run a full Linux install from a Mac, but we can verify the refactored `install.sh` still loads and the Linux branch is intact.

- [ ] **Step 1: Syntax check on all shell files**

Run:

```bash
for f in install.sh stt-record.sh stt-transcribe.sh stt-global.sh stt-global-mac.sh stt.zsh; do
    echo "=== $f ==="
    bash -n "$f" && echo "  syntax OK"
done
```
Expected: each file prints `syntax OK`.

**Note on `stt.zsh`:** This is sourced by zsh, not executed by bash, and it uses zsh-specific syntax (`zle`, `bindkey`). `bash -n stt.zsh` may warn. If it fails, run `zsh -n stt.zsh` instead — expected: no output.

- [ ] **Step 2: Simulate Linux dispatch**

Run:

```bash
OS=Linux bash -c '
    # Load install.sh but stop before calling install() so we can poke at functions
    source ./install.sh --help 2>/dev/null || true
'
```

Actually, `install.sh` calls into its main case statement immediately. Instead, verify the Linux function is still defined:

```bash
grep -c '^install_linux()' install.sh
```
Expected: `1`

```bash
grep -c '^check_deps_linux()' install.sh
```
Expected: `1`

```bash
grep -c 'sudo apt install sox curl jq docker.io docker-compose-v2' install.sh
```
Expected: `1` (confirms Linux dep hint is still there)

```bash
grep -c 'register_gnome_shortcut' install.sh
```
Expected: at least `2` (definition + call in install_linux + uninstall_linux — so `3` or more is fine)

- [ ] **Step 3: Confirm `--help` still works**

Run: `bash install.sh --help`
Expected output:

```
Usage: ./install.sh [--uninstall]

  (no args)    Install STT Terminal Tool
  --uninstall  Remove STT Terminal Tool
```

- [ ] **Step 4: No commit (verification-only task)**

---

## Task 8: Update README note for macOS (if README exists)

**Files:**
- Modify or create: `README.md`

- [ ] **Step 1: Check if README exists**

Run: `ls -la README.md 2>/dev/null || echo "NO README"`

- [ ] **Step 2: If no README exists, skip this task**

The spec does not require a README. The install output already contains usage instructions. Skip to Task 9.

- [ ] **Step 3: If README exists, append a macOS section**

If `README.md` exists, add a `## macOS` section documenting:
- Prerequisite: `brew install sox jq skhd`
- Install: `./install.sh`
- Hotkey: `Cmd+Shift+Space`
- Permissions: Accessibility + Microphone for skhd

Exact content depends on the existing README style — read it first and match the tone. Do not add this if it would duplicate existing content.

- [ ] **Step 4: Commit (only if file was modified)**

```bash
git add README.md
git commit -m "docs(readme): add macOS installation section"
```

---

## Task 9: Final manual test checklist (user-executed)

**Why this task exists:** This is the test surface the spec marked as "manual, not worth automating". It cannot be run from the implementation session — the user has to exercise it on their Mac after the install runs for real. Present this checklist at the end of implementation so the user knows exactly what to verify.

- [ ] **Step 1: Present the checklist to the user**

Output the following to the user as a message (do not save as a file):

```
Implementation complete. Before merging, please run this checklist on your Mac:

A. Fresh install
   [ ] brew install sox jq skhd  (if not yet installed)
   [ ] ./install.sh    →  should detect Darwin, check deps, copy files,
                          register skhd binding, start skhd service
   [ ] Edit ~/.local/share/stt/.env and set STT_SERVER_URL to
       http://192.168.30.30:8082/v1/audio/transcriptions

B. Permissions (one-time)
   [ ] Grant skhd Accessibility permission (System Settings)
   [ ] Grant skhd Microphone permission (triggered on first recording)

C. ZSH widget (in-terminal, independent of skhd)
   [ ] Open a new terminal (or `source ~/.zshrc`)
   [ ] Press Ctrl+T, speak a sentence, press Ctrl+T again
   [ ] Expected: transcribed text appears at the cursor

D. Global hotkey (requires permissions granted)
   [ ] Open Notes.app, click into a note
   [ ] Press Cmd+Shift+Space, speak, press Cmd+Shift+Space again
   [ ] Expected: text pasted into the note
   [ ] Repeat in: Safari address bar, Slack, Claude Code terminal

E. Edge cases
   [ ] Double-tap Cmd+Shift+Space without speaking
       → notification: "Recording failed or was empty"
   [ ] Stop the whisper server, try again
       → notification: "Transcription failed. Is the whisper server running?"
   [ ] Kill the `rec` process manually, then press hotkey
       → should self-recover (stale PID file cleaned up)

F. Uninstall
   [ ] ./install.sh --uninstall
   [ ] Verify: ~/.config/skhd/skhdrc no longer contains stt-global.sh
   [ ] Verify: ~/.local/share/stt/ is gone
   [ ] Verify: ~/.zshrc no longer has the source line
   [ ] Cmd+Shift+Space should do nothing

G. Linux regression (on your working Linux box)
   [ ] git pull && ./install.sh
   [ ] Verify: Ctrl+T still works in terminal
   [ ] Verify: Ctrl+T still works globally (GNOME shortcut)
```

- [ ] **Step 2: Nothing to commit**

---

## Summary of commits

When this plan is executed, the git log should look roughly like:

```
feat(record): make AUDIODEV conditional for macOS CoreAudio default
feat(macos): add stt-global-mac.sh for system-wide STT on macOS
refactor(install): add OS dispatch skeleton
feat(install): add macOS install/uninstall functions
chore(env): update defaults for port 8082 and macOS guidance
chore(compose): default host port 8000 -> 8082
[docs(readme): add macOS installation section]  ← optional
```

Seven commits (or six if no README). Each is a small, reviewable, revertable unit.

---

## Notes for the implementing agent

- **You are editing a live repo** that the user is currently running on Linux. Do not break the Linux path. Task 7 exists specifically to catch regressions.
- **BSD vs GNU sed:** macOS `sed -i` needs `''` after `-i`. Linux `sed -i` does not. The two uninstall functions intentionally differ — don't unify them.
- **Do not push.** Leave commits local. The user will push or PR manually after the manual test checklist passes.
- **The repo has no tests directory and no test runner.** TDD with actual test frameworks is not appropriate here. Use `bash -n` (syntax check) + targeted smoke tests + the final manual checklist as your verification discipline.
- **Commit after each task**, not after each step.
