#!/usr/bin/env bash
# install.sh — Install/uninstall STT Terminal Tool
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

    local new_list
    new_list="$(echo "$current" | sed "s|'$shortcut_path', ||g; s|, '$shortcut_path'||g; s|'$shortcut_path'||g")"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list" 2>/dev/null || true

    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" name 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" command 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$shortcut_path" binding 2>/dev/null || true

    return 0
}

install_linux() {
    echo "=== STT Terminal Tool Installer ==="
    echo ""

    # Check dependencies
    check_deps_linux || exit 1

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Copy files
    cp "$SCRIPT_DIR/stt.zsh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-record.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/stt-transcribe.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/stt-record.sh"
    chmod +x "$INSTALL_DIR/stt-transcribe.sh"
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
    echo "=== STT Terminal Tool Uninstaller ==="

    # Remove source line from .zshrc
    if [[ -f "$ZSHRC" ]]; then
        sed -i "\|$SOURCE_LINE|d" "$ZSHRC"
        sed -i '/# STT Terminal Tool/d' "$ZSHRC"
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
        echo "  (no args)    Install STT Terminal Tool"
        echo "  --uninstall  Remove STT Terminal Tool"
        ;;
    *)
        install
        ;;
esac
