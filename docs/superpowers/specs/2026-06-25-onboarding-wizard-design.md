# Onboarding Wizard — Design

Date: 2026-06-25
Status: approved (brainstorming), implementing
Branch: feature/app-store-phase3-local-whisper

## Problem

A fresh App Store user launches STTBar into a menu-bar-only app with no guidance.
The default transcription source is `server` with no URL, so the first dictation
fails ("Could not connect to the server" → red). There is no first-run flow.

## Goal

A guided first-run wizard that walks a new user through a working setup, defaulting
to the offline local (WhisperKit) path, with self-hosted/server available as an
advanced choice. The wizard doubles as a self-healing recovery surface: if the
config is unusable it reopens.

## Decisions (from brainstorming)

- **Default path:** local (WhisperKit, offline). Server/self-host is an in-wizard
  advanced option.
- **Steps:** Welcome → Source → Permissions (mic + accessibility) → Configure
  (local model download *or* server endpoint) → Hotkey (incl. F5 option) →
  Test dictation → Done.
- **Trigger:** first launch *and* self-heal — reopens when config is unusable
  (no mic, local model not downloaded, or server URL invalid). Also manually
  re-openable from the menu ("Einrichtung erneut starten…").
- **Accessibility** missing is a *warning only*, never a hard re-trigger (text
  falls back to clipboard, which still "works").
- **Approach A:** dedicated wizard window with its own step views, binding to the
  existing `SettingsModel`. Settings UI untouched. Each step is a small unit.

## Architecture

New, isolated units:

- `OnboardingReadiness` (pure + thin live wrapper) — completion flag in
  UserDefaults (`onboardingCompletedAt`); a pure `blockingReasons(Inputs)` /
  `isUsable(Inputs)` predicate; `needsOnboarding(model:)`; `localModelDownloaded(in:)`
  (scans the WhisperKit models dir for a `.mlmodelc`); `isValidHTTPURL`.
- `OnboardingModel` (ObservableObject) — the step list + `next()/back()/progress`,
  plus live `liveState`/`lastTestTranscript` for the Test step.
- `OnboardingView` (SwiftUI) — header (title + progress), per-step content,
  footer (Back / Next / Finish). Reuses `WhisperModelManager`, `Permissions`,
  `HotkeyRecorder`, the existing source/model controls.
- `OnboardingWindow` — hosts the view (mirrors `SettingsWindow`).

Reused / lightly extended:

- `Hotkey.keyName` extended with F1–F20 names; `Hotkey.rawF5` convenience.
- `WhisperModelManager` gains a success result so the wizard knows the download
  finished.
- `MenuBarController` gains `onOpenOnboarding` + a menu item.
- `AppDelegate` gates onboarding at the end of `applicationDidFinishLaunching`,
  reopens on a transcription problem when the config is unusable, forwards runner
  state/transcript to the wizard for the Test step, and wires the menu item.

## Data flow

The wizard binds to `SettingsModel`. Advancing past Source/Configure calls
`model.applyEnvChanges()` so `STT_SOURCE`/`STT_LOCAL_MODEL`/`STT_SERVER_URL` reach
`.env` (defaults satisfy `validateDraft` even for local). Finishing calls
`OnboardingReadiness.markCompleted()`.

## Error handling

- Mic denied / model not downloaded / server URL invalid: shown inline per step
  with status dots; never traps navigation. Finish always completes; self-heal
  catches a still-broken config on the next failed dictation or relaunch (no tight
  loop — only reopens on an actual failure or new launch).
- Model download failure surfaces the WhisperKit error string; the user can retry.
- Accessibility missing: warning row + deep link, non-blocking.

## Testing

Unit tests (pure logic): `blockingReasons` per source, `localModelDownloaded`
scan (temp dir), step-machine `next/back/progress`, `Hotkey.keyName(kVK_F5) == "F5"`.
UI verified by launching the app with a fresh container and confirming the wizard
appears and a configured run no longer reopens it.

## Out of scope (separate follow-ups)

- The perceived hotkey "hang" during the LLM-cleanup busy window (behavior
  decision, needs more new-build data).
- Deeper F5/global-media-key registration edge cases beyond binding it.
