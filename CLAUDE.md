# STT-SpeachToTerminal

Speech-to-Text tool using a local Whisper server. Records audio via hotkey, transcribes via GPU-accelerated Whisper, and pastes the result into the active window.

## Docker Deployment

The Whisper server runs in Docker with GPU passthrough. Any changes to the docker-compose.yml or .env require a redeploy.

```bash
# Rebuild and restart
docker compose up -d --build

# View logs
docker compose logs -f

# Stop
docker compose down
```

- **Container:** `stt-whisper`
- **Image:** `ghcr.io/speaches-ai/speaches:0.9.0-rc.3-cuda`
- **Port:** 8014 (host) -> 8000 (container)
- **GPU:** NVIDIA CUDA required
- **API:** OpenAI-compatible at `http://localhost:8014/v1/audio/transcriptions`

## Autostart (systemd)

The service auto-starts on boot via systemd:

```bash
# Status
sudo systemctl status stt-whisper.service

# Restart
sudo systemctl restart stt-whisper.service

# Disable autostart
sudo systemctl disable stt-whisper.service
```

Service file: `/etc/systemd/system/stt-whisper.service`

After changes to docker-compose.yml or .env:
```bash
sudo systemctl restart stt-whisper.service
```

## Configuration (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| STT_SERVER_URL | http://localhost:8014/v1/audio/transcriptions | Whisper API endpoint |
| STT_LANGUAGE | de | ISO 639-1 language code, or "auto" |
| STT_MODEL | Systran/faster-whisper-medium | Whisper model to use |
| STT_DOCKER_PORT | 8014 | Host port for the Whisper server |
| STT_MODEL_TTL | -1 | VRAM unload timeout (-1 = never) |
| STT_HOTKEY | ^T | ZSH hotkey (^ = Ctrl) |
| STT_AUDIO_DEVICE | default | ALSA audio input device |

## Architecture

```
Hotkey (Ctrl+T) -> stt-global.sh
                    ├── stt-record.sh start  (sox recording)
                    └── stt-record.sh stop
                        └── stt-transcribe.sh (curl -> Docker Whisper -> text)
                            └── xdotool paste into active window
```

## macOS native app (STTBar)

On macOS the front-end is a native Swift menu-bar app, **STTBar.app**, that
**replaces Hammerspoon**. It owns the menu-bar icon, the global hotkeys
(rebindable), the recording HUD overlay (8 anchor positions + optional gray
background), and a native SwiftUI settings window. The shell backend
(`stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh`,
`stt-global-mac.sh`, `stt-runtime.sh`) remains the stable backend contract.
The app spawns `stt-global.sh` with `STT_MODE`, `STT_NOTIFICATIONS=0`,
`STT_APP_NATIVE_PASTE=1`, and namespaced runtime paths under
`${TMPDIR:-/tmp}/de.projectmakers.stt`. The shell writes status/events/metrics
without raw dictated text, and STTBar performs the final paste natively.

- **Source:** `macos-app/` (SwiftPM, target `STTBar`, macOS 14+).
- **Build/install:** `install.sh` runs `macos-app/build-app.sh`, installs to
  `/Applications/STTBar.app` when writable and falls back to
  `~/Applications/STTBar.app`, then registers LaunchAgent
  `de.projectmakers.sttbar` with `STT_INSTALL_DIR`.
- **Tests:** `swift test` in `macos-app/` plus the shell tests in `tests/`.
- **Settings → `.env`:** server/model values are draft-edited, validated, and
  applied with `.env` backups. Comments and unknown keys are preserved.
- **Prompts:** stored in `prompts.json` next to the scripts; the active prompt
  body is mirrored to `active-prompt.txt`, and `.env`'s
  `STT_POSTPROCESS_PROMPT_FILE` points at it. Switching/editing the active
  prompt is live — the next STT run picks it up, no restart.
- **Status & Diagnose:** STTBar exposes health checks, latest errors,
  privacy-safe metrics, test buttons, app logs, and a copyable diagnostic report.
- **Permissions:** Accessibility (native paste) + Microphone.
- Hammerspoon (`hammerspoon-stt.lua`) stays in the repo as a fallback for when
  the Swift toolchain is unavailable; `install.sh` removes its init.lua block
  when the native app installs.

## Important

- The shell scripts (stt-global.sh, stt-record.sh, stt-transcribe.sh) run on the host, NOT in Docker — only the Whisper server runs in Docker
- sox, jq, xdotool, xclip, and notify-send must be installed on the host
- The model is preloaded into VRAM on container start and stays loaded (TTL=-1)
- Volume `whisper-models` persists downloaded models across container restarts

# context-mode — MANDATORY routing rules

You have context-mode MCP tools available. These rules are NOT optional — they protect your context window from flooding. A single unrouted command can dump 56 KB into context and waste the entire session.

## BLOCKED commands — do NOT attempt these

### curl / wget — BLOCKED
Any Bash command containing `curl` or `wget` is intercepted and replaced with an error message. Do NOT retry.
Instead use:
- `ctx_fetch_and_index(url, source)` to fetch and index web pages
- `ctx_execute(language: "javascript", code: "const r = await fetch(...)")` to run HTTP calls in sandbox

### Inline HTTP — BLOCKED
Any Bash command containing `fetch('http`, `requests.get(`, `requests.post(`, `http.get(`, or `http.request(` is intercepted and replaced with an error message. Do NOT retry with Bash.
Instead use:
- `ctx_execute(language, code)` to run HTTP calls in sandbox — only stdout enters context

### WebFetch — BLOCKED
WebFetch calls are denied entirely. The URL is extracted and you are told to use `ctx_fetch_and_index` instead.
Instead use:
- `ctx_fetch_and_index(url, source)` then `ctx_search(queries)` to query the indexed content

## REDIRECTED tools — use sandbox equivalents

### Bash (>20 lines output)
Bash is ONLY for: `git`, `mkdir`, `rm`, `mv`, `cd`, `ls`, `npm install`, `pip install`, and other short-output commands.
For everything else, use:
- `ctx_batch_execute(commands, queries)` — run multiple commands + search in ONE call
- `ctx_execute(language: "shell", code: "...")` — run in sandbox, only stdout enters context

### Read (for analysis)
If you are reading a file to **Edit** it → Read is correct (Edit needs content in context).
If you are reading to **analyze, explore, or summarize** → use `ctx_execute_file(path, language, code)` instead. Only your printed summary enters context. The raw file content stays in the sandbox.

### Grep (large results)
Grep results can flood context. Use `ctx_execute(language: "shell", code: "grep ...")` to run searches in sandbox. Only your printed summary enters context.

## Tool selection hierarchy

1. **GATHER**: `ctx_batch_execute(commands, queries)` — Primary tool. Runs all commands, auto-indexes output, returns search results. ONE call replaces 30+ individual calls.
2. **FOLLOW-UP**: `ctx_search(queries: ["q1", "q2", ...])` — Query indexed content. Pass ALL questions as array in ONE call.
3. **PROCESSING**: `ctx_execute(language, code)` | `ctx_execute_file(path, language, code)` — Sandbox execution. Only stdout enters context.
4. **WEB**: `ctx_fetch_and_index(url, source)` then `ctx_search(queries)` — Fetch, chunk, index, query. Raw HTML never enters context.
5. **INDEX**: `ctx_index(content, source)` — Store content in FTS5 knowledge base for later search.

## Subagent routing

When spawning subagents (Agent/Task tool), the routing block is automatically injected into their prompt. Bash-type subagents are upgraded to general-purpose so they have access to MCP tools. You do NOT need to manually instruct subagents about context-mode.

## Output constraints

- Keep responses under 500 words.
- Write artifacts (code, configs, PRDs) to FILES — never return them as inline text. Return only: file path + 1-line description.
- When indexing content, use descriptive source labels so others can `ctx_search(source: "label")` later.

## ctx commands

| Command | Action |
|---------|--------|
| `ctx stats` | Call the `ctx_stats` MCP tool and display the full output verbatim |
| `ctx doctor` | Call the `ctx_doctor` MCP tool, run the returned shell command, display as checklist |
| `ctx upgrade` | Call the `ctx_upgrade` MCP tool, run the returned shell command, display as checklist |
