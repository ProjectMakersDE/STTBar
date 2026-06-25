# Spec: Audio Input Selection (Package 1)

Date: 2026-06-21 · Branch: `develop`

## Goal

Let the user choose the recording input device: **Automatic** (current default) or a
**fixed** CoreAudio input device.

## Background

The shell backend already honors `STT_AUDIO_DEVICE` (`stt-record.sh`):
empty / `default` → auto-resolve (with Bluetooth-mic avoidance); any other value →
`sox -t coreaudio "<name>"`. So this is an app-side picker that writes `STT_AUDIO_DEVICE`
into `.env` via the existing `EnvStore` buffered-apply flow (same as `STT_SERVER_URL`).

## Design

- **Pure logic (TDD):** `AudioInputCatalog.options(available:current:)` builds the picker
  options from the enumerated device names + the current env value: index 0 is always
  `Automatic` (env value `""`); each available device maps to an option whose id IS its
  CoreAudio name; if `current` is a non-empty name not in `available` (device unplugged),
  it is still appended so the selection is never silently lost.
- **System edge (not unit-tested):** `AudioInputDevices.available()` enumerates input
  device names via `AVCaptureDevice.DiscoverySession` (`.microphone` + known external
  types, `.audio`). `localizedName` is the value passed to `sox -t coreaudio`.
- **Model:** `SettingsModel.audioInputDevice: String` — env-backed draft, loaded in
  `loadEnvDraft()` from `STT_AUDIO_DEVICE` (default `""`), written in `applyEnvChanges()`.
- **UI:** new "Audio" section in the Server tab with a `Picker` bound to a computed
  `Binding` over `audioInputDevice`, options from `AudioInputCatalog`. Applied via the
  existing "Anwenden" button. No new validation (any string is allowed; empty = auto).

## Out of scope (YAGNI)

No live device hot-plug monitoring, no per-profile device, no output device.
