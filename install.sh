#!/usr/bin/env bash
# install.sh — Install/uninstall STTBar
set -euo pipefail

INSTALL_DIR="${STT_INSTALL_DIR:-$HOME/.local/share/stt}"
ZSHRC="$HOME/.zshrc"
SOURCE_LINE="source \"$INSTALL_DIR/stt.zsh\""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

check_deps_linux() {
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

    # Check for docker compose v2 plugin
    if command -v docker &>/dev/null && ! docker compose version &>/dev/null; then
        missing+=("docker-compose-v2")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "Install them with:"
        echo "  sudo apt install sox curl jq docker.io docker-compose-v2"
        echo "  # or on Arch: sudo pacman -S sox curl jq docker docker-compose"
        return 1
    fi

    info "All dependencies found"

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
}

check_deps_macos() {
    local missing=()
    for cmd in sox rec curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "Install them with:"
        echo "  brew install sox jq"
        return 1
    fi

    info "Required STTBar dependencies found"

    if ! command -v swift &>/dev/null && [[ ! -d "$SCRIPT_DIR/macos-app/STTBar.app" ]]; then
        warn "Swift toolchain not found and no prebuilt STTBar.app bundle is present."
        echo "  STTBar needs either Xcode/Swift or a prebuilt macos-app/STTBar.app."
    fi

}

# Build and install the native STTBar.app menu-bar front-end, then register a
# login LaunchAgent that starts it (with STT_INSTALL_DIR pointing at the
# install dir so it finds stt-global.sh + .env).
install_native_app() {
    # Prefer /Applications (the standard location the macOS file pickers — e.g.
    # the Accessibility "+" dialog — open by default) when it is writable;
    # otherwise fall back to the per-user ~/Applications.
    local app_dest="/Applications"
    [[ -w "$app_dest" ]] || app_dest="$HOME/Applications"

    if command -v swift >/dev/null 2>&1; then
        info "Building STTBar.app (native menu-bar front-end) -> $app_dest …"
        if ! STT_INSTALL_DIR="$INSTALL_DIR" bash "$SCRIPT_DIR/macos-app/build-app.sh" "$app_dest"; then
            warn "STTBar.app build failed."
            return 1
        fi
    elif [[ -d "$SCRIPT_DIR/macos-app/STTBar.app" ]]; then
        info "Installing prebuilt STTBar.app -> $app_dest …"
        mkdir -p "$app_dest"
        rm -rf "$app_dest/STTBar.app"
        cp -R "$SCRIPT_DIR/macos-app/STTBar.app" "$app_dest/STTBar.app"
    else
        warn "No Swift toolchain or prebuilt STTBar.app found."
        return 1
    fi
    local app_path="$app_dest/STTBar.app"

    local plist="$HOME/Library/LaunchAgents/de.projectmakers.sttbar.plist"
    mkdir -p "$(dirname "$plist")"
    cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>de.projectmakers.sttbar</string>
  <key>ProgramArguments</key><array>
    <string>$app_path/Contents/MacOS/STTBar</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>STT_INSTALL_DIR</key><string>$INSTALL_DIR</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <!-- Restart after crashes only. An unconditional KeepAlive would also undo
       a clean "Quit STTBar" (and fight the app's single-instance guard). -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict></plist>
PL
    launchctl unload "$plist" 2>/dev/null || true
    launchctl load "$plist" 2>/dev/null || true
    info "STTBar.app installed to $app_dest and started."
    return 0
}

register_gnome_shortcut() {
    if ! command -v gsettings &>/dev/null; then
        return 1
    fi

    local shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/stt/"
    local shortcut_key="<Control>t"

    local current
    current="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)" || return 1

    if echo "$current" | grep -q "stt"; then
        warn "GNOME shortcut already registered"
        return 0
    fi

    if [[ "$current" == "@as []" ]]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$shortcut_path']"
    else
        local new_list="${current%]*}, '$shortcut_path']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list"
    fi

    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" name 'STTBar'
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

    local new_list
    new_list="$(echo "$current" | sed "s|'$shortcut_path', ||g; s|, '$shortcut_path'||g; s|'$shortcut_path'||g")"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list" 2>/dev/null || true

    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" name 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" command 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" binding 2>/dev/null || true

    return 0
}

install_linux() {
    echo "=== STTBar Installer ==="
    echo ""

    # Check dependencies
    check_deps_linux || exit 1

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Copy files
    cp "$SCRIPT_DIR/stt.zsh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-runtime.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-record.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-transcribe.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-postprocess.sh" "$INSTALL_DIR/"
    if [[ ! -f "$INSTALL_DIR/stt-replacements.tsv" ]]; then
        cp "$SCRIPT_DIR/stt-replacements.tsv" "$INSTALL_DIR/"
    fi
    chmod +x "$INSTALL_DIR/stt-record.sh"
    chmod +x "$INSTALL_DIR/stt-runtime.sh"
    chmod +x "$INSTALL_DIR/stt-transcribe.sh"
    chmod +x "$INSTALL_DIR/stt-postprocess.sh"
    cp "$SCRIPT_DIR/stt-global.sh" "$INSTALL_DIR/"
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
        echo "# STTBar - Speech to Text via Ctrl+T" >> "$ZSHRC"
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

    echo ""
    info "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit config:    nano $INSTALL_DIR/.env"
    echo "  2. Start whisper:  cd $INSTALL_DIR && docker compose up -d"
    echo "  3. Reload shell:   source $ZSHRC"
    echo ""
    echo "Usage:"
    echo "  Terminal (ZSH):  Press Ctrl+T to start/stop recording"
    echo "  Anywhere (X11):  Ctrl+T via global hotkey (Claude Code, any app)"
}

uninstall_linux() {
    echo "=== STTBar Uninstaller ==="

    # Remove source line from .zshrc
    if [[ -f "$ZSHRC" ]]; then
        sed -i "\|$SOURCE_LINE|d" "$ZSHRC"
        sed -i '/# STTBar/d' "$ZSHRC"
        info "Removed source line from $ZSHRC"
    fi

    # Remove global hotkey
    unregister_gnome_shortcut 2>/dev/null && info "Removed GNOME shortcut" || true

    # Remove install directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        info "Removed $INSTALL_DIR"
    fi

    echo ""
    info "Uninstall complete. Restart your shell."
}

install_macos() {
    echo "=== STTBar Installer (macOS) ==="
    echo ""

    check_deps_macos || exit 1

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Copy shared files
    cp "$SCRIPT_DIR/stt.zsh"          "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-runtime.sh"   "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-record.sh"    "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-transcribe.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-postprocess.sh" "$INSTALL_DIR/"
    if [[ ! -f "$INSTALL_DIR/stt-replacements.tsv" ]]; then
        cp "$SCRIPT_DIR/stt-replacements.tsv" "$INSTALL_DIR/"
    fi
    chmod +x "$INSTALL_DIR/stt-record.sh"
    chmod +x "$INSTALL_DIR/stt-runtime.sh"
    chmod +x "$INSTALL_DIR/stt-transcribe.sh"
    chmod +x "$INSTALL_DIR/stt-postprocess.sh"

    # Copy the macOS global script as stt-global.sh (OS-agnostic name
    # inside the install dir, so front-end bindings do not depend on
    # the source filename).
    cp "$SCRIPT_DIR/stt-global-mac.sh" "$INSTALL_DIR/stt-global.sh"
    chmod +x "$INSTALL_DIR/stt-global.sh"
    local legacy_frontend="$INSTALL_DIR/hammer""spoon-stt.lua"
    rm -f "$legacy_frontend" 2>/dev/null || true

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
        echo "# STTBar - Speech to Text" >> "$ZSHRC"
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

    if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        {
            printf 'commit=%s\n' "$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
            printf 'source_repo=%s\n' "$SCRIPT_DIR"
            printf 'installed_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
        } > "$INSTALL_DIR/installed-version.txt" 2>/dev/null || true
    fi

    # Front-end: the native STTBar.app owns icon, hotkeys and HUD.
    if ! install_native_app; then
        error "STTBar.app could not be installed. Install Xcode/Swift or provide a prebuilt macos-app/STTBar.app."
        exit 1
    fi

    echo ""
    info "Installation complete!"
    echo ""
    echo "=============================================================="
    echo "  WHAT'S NEXT"
    echo "=============================================================="
    echo ""

    info "STTBar.app is running in the menu bar — Cmd+Shift+Space is live."
    echo ""
    echo "  First-time permissions:"
    echo "    - Privacy & Security > Accessibility -> enable 'STTBar'"
    echo "      (needed to paste the transcribed text into the focused field)"
    echo "    - Microphone access is requested automatically on first recording."
    echo ""
    echo "  Open the menu bar mic icon -> 'Einstellungen…' to configure"
    echo "  servers, models, prompts, shortcuts and the HUD position."

    echo ""
    echo "  Configure the whisper server:"
    echo "       nano $INSTALL_DIR/.env"
    echo "     Set STT_SERVER_URL to your whisper endpoint, e.g."
    echo "     http://192.168.30.30:8082/v1/audio/transcriptions"
    echo ""
    echo "  Reload your shell for the in-terminal Ctrl+T widget:"
    echo "       source $ZSHRC"
    echo ""
    echo "=============================================================="
    echo "  USAGE"
    echo "=============================================================="
    echo ""
    echo "  In any app:     Cmd+Shift+Space   (start/stop — LLM cleanup,"
    echo "                                     pastes into the focused field)"
    echo "                  Ctrl+Shift+Space  (start/stop — raw transcript,"
    echo "                                     no LLM; replacements still apply)"
    echo "                  Shift+Option+Spc  (start/stop — LLM cleanup,"
    echo "                                     translated to English)"
    echo "  In zsh prompt:  Ctrl+T            (start/stop — text inserts"
    echo "                                     at the cursor)"
    echo ""
    echo "  Auto-start: STTBar starts at login via LaunchAgent de.projectmakers.sttbar."
    echo ""
}

uninstall_macos() {
    echo "=== STTBar Uninstaller (macOS) ==="

    # Remove source line from .zshrc (BSD sed needs '' after -i)
    if [[ -f "$ZSHRC" ]]; then
        sed -i '' "\|$SOURCE_LINE|d" "$ZSHRC" 2>/dev/null || true
        sed -i '' '/# STTBar/d' "$ZSHRC" 2>/dev/null || true
        info "Removed source line from $ZSHRC"
    fi

    # Remove the native STTBar.app front-end + its login LaunchAgent.
    local plist="$HOME/Library/LaunchAgents/de.projectmakers.sttbar.plist"
    if [[ -f "$plist" ]]; then
        launchctl unload "$plist" 2>/dev/null || true
        rm -f "$plist"
        info "Removed STTBar LaunchAgent"
    fi
    for app in "/Applications/STTBar.app" "$HOME/Applications/STTBar.app"; do
        if [[ -d "$app" ]]; then
            rm -rf "$app"
            info "Removed $app"
        fi
    done

    # Remove install directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        info "Removed $INSTALL_DIR"
    fi

    echo ""
    info "Uninstall complete. Restart your shell."
}

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

case "${1:-}" in
    --uninstall|-u)
        uninstall
        ;;
    --help|-h)
        echo "Usage: $0 [--uninstall]"
        echo ""
        echo "  (no args)    Install STTBar"
        echo "  --uninstall  Remove STTBar"
        ;;
    *)
        install
        ;;
esac
