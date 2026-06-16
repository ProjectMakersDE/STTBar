# STTBar — Native macOS Menu-Bar App (Design)

**Date:** 2026-06-16
**Status:** Approved-pending-review
**Supersedes (front-end only):** `hammerspoon-stt.lua`

## 1. Summary

Replace the Hammerspoon-based macOS front-end with a native Swift menu-bar app,
`STTBar.app`. The app owns the menu-bar icon, the global hotkeys, the recording
HUD overlay, and a native SwiftUI settings experience. The existing shell-script
backend (`stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh`,
`stt-global-mac.sh`) is reused unchanged except for one small additive feature in
`stt-postprocess.sh` (prompt-from-file). `.env` remains the single source of
truth for backend configuration.

## 2. Goals

1. Menu-bar status icon (like Hammerspoon's), reflecting app/recording state.
2. A native-looking macOS settings window that configures:
   - HUD position at one of 8 screen anchors + optional light-gray background.
   - The keyboard shortcuts with their function mapping (displayed **and**
     rebindable).
   - Live LLM-prompt editing without restarting: a seeded default prompt,
     multiple saved prompts, switching between them, and editing the active
     prompt in a separate window with a title bar.
   - LLM selection by entering an LM-Studio model ID (free-text).
   - Whisper-server IP/URL and LM-Studio-server IP/URL.
   - Whisper model selection (already a parameter — surfaced in the UI).
3. Optionally stand Hammerspoon down: the app takes over icon + hotkeys + HUD,
   and the installer comments out the Hammerspoon STT load.

## 3. Non-Goals

- No change to the Linux/X11 path or the in-terminal `stt.zsh` widget.
- No change to the Docker/Whisper server deployment.
- No rewrite of the transcription/recording/postprocess pipeline logic.
- No code signing / notarization / App Store distribution (local build only).

## 4. Architecture

```
┌──────────────────────── STTBar.app (Swift, LSUIElement) ────────────────────┐
│  MenuBarController   HotkeyManager     HudOverlay        SettingsWindow      │
│  (NSStatusItem)      (Carbon hotkeys)  (NSPanel + CALayer)  (SwiftUI)        │
│        │                  │                 │                   │            │
│        └──────────────────┴── spawns ───────┘                   │            │
│                           │                              EnvStore / PromptStore
└───────────────────────────┼─────────────────────────────────────┼──────────┘
                            │ Process(/bin/bash stt-global.sh)     │ read/write
                            ▼                                       ▼
        stt-global-mac.sh ─► stt-record.sh ─► stt-transcribe.sh        .env
                                            └► stt-postprocess.sh ◄── active-prompt.txt
                                                                       prompts.json
   Shared state files (already used by the Hammerspoon HUD):
     /tmp/stt-recording.pid   (is-recording)
     /tmp/stt-recording.wav   (live audio levels for the waveform)
     STT_PHASE_FILE           (recording|whisper|llm|done|error)
```

The app spawns the **same** command Hammerspoon spawns today:

```
STT_MODE=<full|raw|english> STT_NOTIFICATIONS=0 STT_PHASE_FILE=<path> \
  exec <INSTALL_DIR>/stt-global.sh
```

First trigger starts recording; second trigger (same or different mode — the
stopping press's mode wins) stops, transcribes, post-processes, and pastes. This
is the proven contract; the app reproduces Hammerspoon's task lifecycle,
watchdog, and phase-file watching.

### 4.1 Components (one clear purpose each)

- **AppDelegate** — lifecycle, wires components, owns the install/script dir.
- **MenuBarController** — `NSStatusItem`, state-driven icon, dropdown menu
  (Einstellungen…, Prompt bearbeiten…, Aufnahme-Modi, Beenden).
- **HotkeyManager** — registers up to 3 global hotkeys via Carbon
  `RegisterEventHotKey`; re-registers live when bindings change; emits a
  `(mode)` callback.
- **SttRunner** — owns the `Process` lifecycle, recording-state detection
  (`/tmp/stt-recording.pid`), the start-watchdog, and error flashes. Mirrors
  `launchSttToggle` from the Lua.
- **HudOverlay** — borderless click-through `NSPanel` at overlay window level,
  joins all spaces; a `CALayer`/`Canvas` port of the Lua animation (mic icon →
  live waveform from the wav tail → whisper/llm spinner → result/error icon).
  Reads anchor + background from settings; repositions live.
- **AudioLevelReader** — reads the tail of `/tmp/stt-recording.wav`, computes
  per-bucket RMS/peak levels (port of `readAudioLevels`).
- **EnvStore** — parses `.env` preserving comments and unknown keys; updates
  only managed keys; writes atomically (temp file + rename).
- **PromptStore** — loads/saves `prompts.json`; tracks the active prompt; writes
  the active body to `active-prompt.txt`; seeds the default agent prompt on first
  run.
- **SettingsModel (ObservableObject)** — single observable bridging EnvStore,
  PromptStore, and UserDefaults to the SwiftUI views.
- **SettingsWindow / PromptEditorWindow** — SwiftUI hosted in `NSWindow`s.

## 5. Configuration & Data

### 5.1 `.env` (single source of truth, app-managed keys)

| Key | UI field |
|-----|----------|
| `STT_SERVER_URL` | Whisper-Server IP/URL |
| `STT_MODEL` | Whisper-Modell (presets + free text; incl. `Systran/faster-whisper-large-v3-turbo`) |
| `STT_LANGUAGE` | Sprache |
| `STT_POSTPROCESS_ENABLED` | Postprocess on/off |
| `STT_POSTPROCESS_PROVIDER` | Provider (lmstudio/openai) |
| `STT_POSTPROCESS_URL` | LM-Studio IP/URL |
| `STT_POSTPROCESS_MODEL` | LLM-ID (free text) |
| `STT_POSTPROCESS_PROMPT_FILE` | (set by app → `active-prompt.txt`) |

The app preserves every other line in `.env` verbatim. It never writes
`STT_POSTPROCESS_PROMPT` (multi-line); it uses the file indirection instead.

### 5.2 Prompts

- `prompts.json` next to the scripts (in `INSTALL_DIR`):
  `{ "activeId": "<id>", "prompts": [ { "id", "title", "body" } ] }`.
- On first run, seed one prompt titled **"Agent-Standard (DE)"** whose body is
  the current default from `stt-postprocess.sh`.
- The active prompt's `body` is mirrored to `active-prompt.txt`.
- Switching the active prompt or editing the active body rewrites
  `active-prompt.txt` immediately → the **next** STT run uses it (live, no
  app/script restart).

### 5.3 App-owned settings (UserDefaults)

- `hudAnchor` ∈ {topCenter, topRight, bottomRight, bottomLeft, leftBottom,
  leftTop, rightBottom, rightTop} (the 8 anchors from the brief).
- `hudBackground` : Bool (light-gray panel backing).
- `hotkey.full`, `hotkey.raw`, `hotkey.english` : {keyCode, modifiers}.
  Defaults match today: Full = ⌘⇧Space, Raw = ⌃⇧Space, English = ⇧⌥Space.

### 5.4 Backend change (additive, low-risk)

`stt-postprocess.sh`: after sourcing `.env`, if `STT_POSTPROCESS_PROMPT` is unset
**and** `STT_POSTPROCESS_PROMPT_FILE` points to a readable file, load the prompt
from that file. Otherwise behavior is unchanged (built-in default still applies).

## 6. UI

### 6.1 Settings window (SwiftUI `TabView`, native form controls)

1. **Server** — Whisper IP/URL, Whisper-Modell (Picker w/ presets + custom),
   Sprache, Postprocess-Toggle, LM-Studio IP/URL, LLM-ID, Provider. Inline
   "Testen" buttons may verify reachability (best-effort, optional).
2. **Prompts** — List of saved prompts with an active selector; New / Duplicate /
   Delete; "Bearbeiten…" opens the separate titled editor window.
3. **Shortcuts** — 3 rows: function label + description + a key-recorder control.
   Conflicts are flagged; changes re-register hotkeys live.
4. **Anzeige** — 3×3 anchor grid (center disabled) for HUD position +
   gray-background toggle, with a live HUD preview trigger.
5. **Allgemein** — Autostart toggle (LaunchAgent), "Hammerspoon-HUD
   deaktivieren" action + status, Accessibility/Microphone permission status.

### 6.2 Prompt editor window

A separate `NSWindow` with a real title bar (shows the prompt title), a
multi-line editor for the body, and Save/Revert. Saving the active prompt
rewrites `active-prompt.txt`.

## 7. Build, Install, Autostart

- New `macos-app/` SwiftPM package: executable target `STTBar`, platform
  `macOS 13+`, depends only on system frameworks (AppKit, SwiftUI, Carbon,
  AVFoundation for mic permission).
- `install.sh` (macOS branch) gains a step:
  1. `swift build -c release` in `macos-app/`.
  2. Assemble `STTBar.app` (Info.plist: `LSUIElement=true`,
     `NSMicrophoneUsageDescription`, bundle id `de.projectmakers.sttbar`), copy
     the release binary into `Contents/MacOS/`.
  3. Install to `~/Applications/STTBar.app`.
  4. Write the script/install dir into the app config so it can find
     `stt-global.sh` + `.env`.
  5. Register `~/Library/LaunchAgents/de.projectmakers.sttbar.plist`
     (RunAtLoad + KeepAlive) and `launchctl` load it.
  6. **Stand Hammerspoon down:** comment out / remove the STT block in
     `~/.hammerspoon/init.lua` (the existing `unregister_hammerspoon_binding`
     already does this) and reload HS. `hammerspoon-stt.lua` stays in the repo as
     a fallback but is not loaded.
- Uninstall reverses: `launchctl` unload, remove the app + LaunchAgent.

## 8. Permissions

- **Microphone** — needed by the recording backend; declared in Info.plist.
- **Accessibility** — needed because the paste step (`osascript … keystroke "v"`)
  is spawned by the app; the app prompts and links to System Settings. Same
  requirement Hammerspoon had.
- Carbon hotkey **registration** needs no special permission.

## 9. Error Handling

- Mirror the Lua resilience: stale-task detection, a start watchdog (~4 s), and
  an error flash on non-zero exit or empty transcription.
- `.env` writes are atomic; on parse failure the app surfaces an error and does
  not clobber the file.
- If the Swift toolchain is missing at install time, the installer prints a clear
  message and offers to keep using the Hammerspoon front-end.

## 10. Testing

- **Shell:** a focused test that `stt-postprocess.sh` honors
  `STT_POSTPROCESS_PROMPT_FILE` (and still falls back to the built-in default).
- **Swift unit tests:** `EnvStore` round-trips (preserves comments/unknown keys,
  updates managed keys), `PromptStore` (seed, switch, mirror to file),
  `AudioLevelReader` bucket math on a synthetic wav.
- **Manual:** hotkey trigger → record → HUD waveform → whisper/llm spinner →
  paste; switch prompt and confirm the next run uses it; move HUD across the 8
  anchors; toggle gray background; rebind a hotkey.

## 11. Risks / Open Questions

- Porting the HUD animation is the largest single piece (mechanical translation
  of `hammerspoon-stt.lua` canvas drawing to `CALayer`/SwiftUI `Canvas`).
- LaunchAgent-launched apps run with a minimal `PATH`; the spawned shell already
  prepends Homebrew paths (`stt-global-mac.sh`), so this is covered.
- macOS may reset Accessibility trust when the app binary changes on reinstall;
  the installer should remind the user to re-grant if needed.

## 12. Rollout

Single implementation plan. Order: (1) backend prompt-file change + shell test,
(2) SwiftPM scaffold + EnvStore/PromptStore + tests, (3) menu bar + hotkeys +
SttRunner, (4) HUD port, (5) Settings + prompt-editor UI, (6) install/autostart +
Hammerspoon stand-down, (7) manual verification pass.
