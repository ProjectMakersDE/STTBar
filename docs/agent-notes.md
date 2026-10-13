# STTBar Developer Notes

STTBar is a native macOS menu-bar app for speech-to-text dictation. It records
audio locally, transcribes on-device with Parakeet (FluidAudio) or WhisperKit or through a Whisper-compatible endpoint, can run
an optional LLM cleanup pass, and pastes the final text into the focused app.

## Main Paths

- `macos-app/`: SwiftPM app target `STTBar`.
- `stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh`,
  `stt-global-mac.sh`, `stt-runtime.sh`: optional legacy shell tools. The native
  app uses `Core/Transcription/` and does not execute these scripts.
- `install.sh`: builds/installs `STTBar.app`, copies scripts to
  `~/.local/share/stt`, and registers the LaunchAgent.
- `macos-app/Tests/STTBarTests/`: native tests. Inject isolated settings,
  Keychain collaborators and runtime paths; never mutate user defaults, access
  actual microphone data, or paste into the focused app from tests.
- `tests/`: optional shell tool tests.

## Local Development

```bash
swift test --package-path macos-app
for t in tests/*.sh; do bash "$t"; done
bash macos-app/build-app.sh /tmp/sttbar-build-check
```

For a review on a real user account, build tests first and run the produced
XCTest bundle directly with `STT_RUNTIME_DIR` / `STT_INSTALL_DIR` pointing to
temporary directories. Add a `sandbox-exec` profile that denies network,
Keychain access and writes to the user's Library. `swift test` inside this
additional sandbox attempts a nested SwiftPM compiler sandbox and can fail
before tests run. Do not install the app as part of an automated test run.

Install the current checkout locally:

```bash
bash install.sh
```

## Local models

`LocalModels` maps a model name to its engine: `parakeet-ultra` (default) and
`parakeet-v3` run through FluidAudio, every other name is a WhisperKit model.
`LocalTranscriber.shared` keeps one model in memory. It loads, downloads and
warms the model at launch and after a settings save when `STT_LOCAL_PRELOAD`
is on (default). The first CoreML inference compiles for the Neural Engine,
which took 90 to 110 s for Parakeet on an M1 Max; afterwards three minutes of
speech transcribe in about one second. `LocalModelStatus` drives the menu-bar
hourglass and the status line in settings and onboarding.

## Prompts

Prompt presets are seeded by `DefaultPrompt.swift`. The active prompt is stored
in `prompts.json` and mirrored to `active-prompt.txt`; `.env` points
`STT_POSTPROCESS_PROMPT_FILE` at that mirror so the next dictation run uses the
selected prompt without restarting the app.

## Privacy and recordings

Each native run owns `runtime/recording-<UUID>.wav`. The backend deletes it on
every terminal path; startup removes orphaned native recording files. The HUD
reads the active backend URL. The sensitive flag is captured at recording start
and remains effective for that result even if disabled during the run.
`TranscriptHistoryStore` purges on load, privacy changes and the app watchdog;
it writes only when entries actually change.

## App Store

`macos-app/build-appstore.sh` compiles with `APPSTORE`, embeds the supplied
provisioning profile and signs the app and installer. `STT_BUILD_NUMBER` changes
only the generated artifact's build number. Semantic-release owns source
versions and the changelog; do not edit them manually. Distribution availability
and review notes must be checked in App Store Connect independently of the build.

Current built-ins:

- `Agent V4 (DE)`: German agent-ready cleanup.
- `Agent V4 (EN output)`: cleanup plus English output.

## Releases

Use Conventional Commits. Semantic Release runs on pushes to `master`, computes
the next semantic version, updates `Info.plist`, builds `STTBar.app.zip`, and
publishes the archive as a GitHub Release asset.

Examples:

```bash
git commit -m "feat(prompts): add english agent prompt"
git commit -m "fix(hud): soften waveform release"
git commit -m "docs: refresh public readme"
```
