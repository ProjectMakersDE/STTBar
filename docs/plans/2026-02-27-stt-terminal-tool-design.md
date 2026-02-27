# STT Terminal Tool — Design Document

**Date:** 2026-02-27
**Status:** Approved

## Summary

A ZSH-integrated speech-to-text tool that records audio via hotkey toggle and transcribes it using a local faster-whisper server running in Docker. The transcribed text is inserted at the cursor position in the terminal prompt.

## Decisions

- **Language:** Pure Shell (Bash/ZSH)
- **Integration:** ZLE Widget bound to Ctrl+T
- **Server:** faster-whisper in Docker (CUDA, OpenAI-compatible API)
- **Recording mode:** Toggle (press to start, press again to stop)
- **Dependencies:** sox, curl, jq, docker/docker-compose

## Project Structure

```
STT-SpeachToTerminal/
├── docker-compose.yml          # faster-whisper Server
├── stt.zsh                     # ZSH Plugin (ZLE Widget + Keybinding)
├── stt-record.sh               # Audio recording helper
├── stt-transcribe.sh           # API call to Whisper Server
├── install.sh                  # Setup script
└── .env                        # Configuration
```

## Configuration (.env)

```bash
STT_SERVER_URL="http://localhost:8000/v1/audio/transcriptions"
STT_LANGUAGE="de"
STT_HOTKEY="^T"               # Ctrl+T
STT_AUDIO_DEVICE="default"
STT_MODEL="base"
```

## Docker Setup

- Image: `fedirz/faster-whisper-server:latest-cuda`
- Port: 8000 → OpenAI-compatible API at `/v1/audio/transcriptions`
- Model cache persisted via Docker volume
- GPU acceleration via CUDA

## Core Flow

1. User presses Ctrl+T → ZLE widget activates
2. State changes to `recording`, status message shown
3. `sox` records audio to `/tmp/stt-recording.wav` (16kHz, mono, 16bit)
4. User presses Ctrl+T again → recording stops
5. State changes to `transcribing`, status message updated
6. `curl` POSTs wav file to faster-whisper server
7. `jq` extracts text from JSON response
8. Text inserted at cursor position via `LBUFFER+=`
9. Temp files cleaned up, state returns to `idle`

## Error Handling

- Server unreachable → error message via `zle -M`, cleanup temp files
- Empty recording → abort with hint message
- Always cleanup temp files (even on error)

## Installation

`install.sh` performs:
1. Check dependencies (sox, curl, jq, docker)
2. Copy scripts to `~/.local/share/stt/`
3. Add `source` line to `~/.zshrc`
4. Create `.env` with defaults
5. Optionally start Docker container

Uninstall via `install.sh --uninstall`.
