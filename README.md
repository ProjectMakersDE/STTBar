# STTBar

Native macOS menu-bar speech-to-text for local or self-hosted Whisper servers.
STTBar records audio, transcribes it through a Whisper-compatible endpoint,
optionally cleans the transcript with an LLM, and pastes the result into the
focused app.

## Features

- Global hotkeys for full cleanup, raw transcript, and English output.
- Native menu-bar app with HUD, settings, prompt editor, profiles, diagnostics,
  history/privacy controls, and vocabulary replacements.
- Works with local or remote Whisper-compatible servers.
- Optional LLM cleanup via LM Studio or OpenAI-compatible chat endpoints.
- Built-in Agent V4 prompts for German and English-output workflows.

## Install

```bash
git clone https://github.com/ProjectMakersDE/STTBar.git
cd STTBar
bash install.sh
```

The installer builds `STTBar.app`, installs it to `/Applications` when
possible, copies the backend scripts to `~/.local/share/stt`, and starts the
LaunchAgent.

## Configure

Open the menu-bar microphone icon and choose `Einstellungen...`.

Key settings:

- Whisper URL, for example `http://localhost:8082/v1/audio/transcriptions`.
- Whisper model, for example `Systran/faster-whisper-large-v3-turbo`.
- Optional LLM cleanup URL, model, provider, and timeout.
- Prompt presets and active prompt.
- Hotkeys and HUD position.

The same values are stored in `~/.local/share/stt/.env`.

## Local Whisper Server

The included `docker-compose.yml` starts a Speaches/faster-whisper server:

```bash
docker compose up -d
```

Set `STT_DOCKER_PORT` and `STT_MODEL` in `.env` if needed.

## Updates

`Einstellungen -> Allgemein -> Nach Updates suchen` checks the latest GitHub
Release in `ProjectMakersDE/STTBar`. Release builds attach `STTBar.app.zip` and
a SHA256 file.

## Development

```bash
swift test --package-path macos-app
for t in tests/*.sh; do bash "$t"; done
bash macos-app/build-app.sh /tmp/sttbar-build-check
```

Releases use Conventional Commits and Semantic Release on `master`.
