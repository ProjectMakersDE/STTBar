# STTBar Developer Notes

STTBar is a native macOS menu-bar app for speech-to-text dictation. It records
audio locally, sends it to a Whisper-compatible transcription endpoint, can run
an optional LLM cleanup pass, and pastes the final text into the focused app.

## Main Paths

- `macos-app/`: SwiftPM app target `STTBar`.
- `stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh`,
  `stt-global-mac.sh`, `stt-runtime.sh`: shell backend used by the app.
- `install.sh`: builds/installs `STTBar.app`, copies scripts to
  `~/.local/share/stt`, and registers the LaunchAgent.
- `tests/`: shell backend tests.

## Local Development

```bash
swift test --package-path macos-app
for t in tests/*.sh; do bash "$t"; done
bash macos-app/build-app.sh /tmp/sttbar-build-check
```

Install the current checkout locally:

```bash
bash install.sh
```

## Prompts

Prompt presets are seeded by `DefaultPrompt.swift`. The active prompt is stored
in `prompts.json` and mirrored to `active-prompt.txt`; `.env` points
`STT_POSTPROCESS_PROMPT_FILE` at that mirror so the next dictation run uses the
selected prompt without restarting the app.

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
