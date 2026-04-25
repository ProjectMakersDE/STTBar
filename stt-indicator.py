#!/usr/bin/env python3
"""STT Tray Indicator — shows recording state in the system tray."""

import gi
import os
import re
import signal
import subprocess

gi.require_version("Gtk", "3.0")
gi.require_version("AppIndicator3", "0.1")
from gi.repository import Gtk, AppIndicator3, GLib

STATE_FILE = "/tmp/stt-state"
PID_FILE = "/tmp/stt-recording.pid"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.path.join(SCRIPT_DIR, ".env")

ICON_IDLE = "microphone-sensitivity-muted-symbolic"
ICON_RECORDING = "audio-input-microphone-symbolic"
ICON_TRANSCRIBING = "emblem-synchronizing-symbolic"

INDICATOR_ID = "stt-indicator"

SERVER_REMOTE = "http://192.168.30.30:8082/v1/audio/transcriptions"
SERVER_LOCAL = "http://localhost:8014/v1/audio/transcriptions"


class STTIndicator:
    def __init__(self):
        self.indicator = AppIndicator3.Indicator.new(
            INDICATOR_ID,
            ICON_IDLE,
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("STT")

        self._current_state = "idle"
        self._build_menu()
        self._ensure_state_file()
        GLib.timeout_add(300, self._poll_state)

    def _get_current_server_url(self):
        try:
            with open(ENV_FILE, "r") as f:
                for line in f:
                    m = re.match(r'^STT_SERVER_URL="(.+)"', line.strip())
                    if m:
                        return m.group(1)
        except (FileNotFoundError, IOError):
            pass
        return SERVER_REMOTE

    def _is_remote(self):
        return "192.168.30.30" in self._get_current_server_url()

    def _set_server_url(self, new_url):
        try:
            with open(ENV_FILE, "r") as f:
                lines = f.readlines()
            with open(ENV_FILE, "w") as f:
                for line in lines:
                    if line.strip().startswith("STT_SERVER_URL="):
                        f.write(f'STT_SERVER_URL="{new_url}"\n')
                    else:
                        f.write(line)
        except (FileNotFoundError, IOError):
            pass

    def _build_menu(self):
        menu = Gtk.Menu()

        is_remote = self._is_remote()
        label = "Server (192.168.30.30)" if is_remote else "Lokal (localhost)"
        self.item_server = Gtk.MenuItem(label=f"Whisper: {label}")
        self.item_server.connect("activate", self._toggle_server)
        menu.append(self.item_server)

        menu.append(Gtk.SeparatorMenuItem())

        item_reset = Gtk.MenuItem(label="Reset")
        item_reset.connect("activate", self._reset)
        menu.append(item_reset)

        menu.append(Gtk.SeparatorMenuItem())

        item_quit = Gtk.MenuItem(label="Beenden")
        item_quit.connect("activate", self._quit)
        menu.append(item_quit)

        menu.show_all()
        self.indicator.set_menu(menu)

    def _toggle_server(self, _):
        if self._is_remote():
            self._set_server_url(SERVER_LOCAL)
        else:
            self._set_server_url(SERVER_REMOTE)
        self._build_menu()
        label = "Server" if self._is_remote() else "Lokal"
        subprocess.Popen(
            ["notify-send", "-t", "2000", "STT", f"Whisper: {label}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def _reset(self, _):
        try:
            with open(PID_FILE, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, signal.SIGINT)
        except (FileNotFoundError, IOError, ValueError, ProcessLookupError, OSError):
            pass
        try:
            os.remove(PID_FILE)
        except OSError:
            pass
        with open(STATE_FILE, "w") as f:
            f.write("idle")
        self._current_state = "idle"
        self.indicator.set_icon_full(ICON_IDLE, "Idle")
        subprocess.Popen(
            ["notify-send", "-t", "2000", "STT", "Reset durchgeführt"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def _ensure_state_file(self):
        if not os.path.exists(STATE_FILE):
            with open(STATE_FILE, "w") as f:
                f.write("idle")

    def _poll_state(self):
        try:
            with open(STATE_FILE, "r") as f:
                state = f.read().strip()
        except (FileNotFoundError, IOError):
            state = "idle"

        if state != self._current_state:
            self._current_state = state
            if state == "recording":
                self.indicator.set_icon_full(ICON_RECORDING, "Recording")
            elif state == "transcribing":
                self.indicator.set_icon_full(ICON_TRANSCRIBING, "Transcribing")
            else:
                self.indicator.set_icon_full(ICON_IDLE, "Idle")

        return True  # keep polling

    def _quit(self, _):
        try:
            os.remove(STATE_FILE)
        except OSError:
            pass
        Gtk.main_quit()


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, lambda *_: Gtk.main_quit())
    STTIndicator()
    Gtk.main()


if __name__ == "__main__":
    main()
