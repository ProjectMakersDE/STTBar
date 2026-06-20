#!/usr/bin/env bash
# Verifies the explicit STT_ACTION start/stop contract and the force-start
# clean-up that the app relies on, so a press with no live audio always starts
# fresh and a stop with nothing recording is a quiet no-op (not an error).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
cleanup() {
    for p in "${rec1:-}" "${rec2:-}"; do
        [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
    done
    rm -rf "$tmp"
}
trap cleanup EXIT

# Isolated copy of the backend (no .env, so nothing external is sourced).
cp "$ROOT/stt-global-mac.sh" "$ROOT/stt-record.sh" "$ROOT/stt-runtime.sh" "$tmp/"

# Fake `rec`: write a WAV-sized file (last arg) and block until signalled.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/rec" <<'EOF'
#!/usr/bin/env bash
out="${@: -1}"
head -c 200 /dev/zero > "$out" 2>/dev/null || printf '%200s' '' > "$out"
trap 'exit 0' INT TERM
while :; do sleep 0.2; done
EOF
chmod +x "$tmp/bin/rec"

runtime="$tmp/runtime"
record_env=(
    STT_RUNTIME_DIR="$runtime"
    STT_LEGACY_PID_FILE="$tmp/legacy.pid"
    STT_LEGACY_RECORD_FILE="$tmp/legacy.wav"
    STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH=0
    STT_AUDIO_DEVICE=""
    PATH="$tmp/bin:$PATH"
)

pidfile="$runtime/recording.pid"

# --- 1) Force start with no prior state: clean start. ---
env "${record_env[@]}" STT_FORCE_START=1 "$tmp/stt-record.sh" start >/dev/null
rec1="$(cat "$pidfile")"
kill -0 "$rec1" 2>/dev/null || { echo "FAIL: first force start did not launch rec"; exit 1; }
status="$(env "${record_env[@]}" "$tmp/stt-record.sh" status)"
[[ "$status" == "recording" ]] || { echo "FAIL: expected recording, got [$status]"; exit 1; }

# --- 2) Force start AGAIN: must abort the old recording and start fresh,
#        never flip to a stop. This is the user's "no live audio => start" rule. ---
env "${record_env[@]}" STT_FORCE_START=1 "$tmp/stt-record.sh" start >/dev/null
rec2="$(cat "$pidfile")"
[[ "$rec2" != "$rec1" ]] || { echo "FAIL: force start reused the old rec pid"; exit 1; }
for _ in 1 2 3 4 5; do kill -0 "$rec1" 2>/dev/null || break; sleep 0.1; done
kill -0 "$rec1" 2>/dev/null && { echo "FAIL: old rec was not aborted by force start"; exit 1; }
kill -0 "$rec2" 2>/dev/null || { echo "FAIL: second force start did not launch a new rec"; exit 1; }
echo "PASS global-force-start-restarts-cleanly"

# --- 3) Clean up the live recording. ---
env "${record_env[@]}" "$tmp/stt-record.sh" cancel >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do kill -0 "$rec2" 2>/dev/null || break; sleep 0.1; done
rec1=""; rec2=""

# --- 4) STT_ACTION=stop with nothing recording: quiet no-op, exit 0, phase idle. ---
global_env=(
    STT_RUNTIME_DIR="$runtime"
    STT_LEGACY_PID_FILE="$tmp/legacy.pid"
    STT_LEGACY_RECORD_FILE="$tmp/legacy.wav"
    STT_NOTIFICATIONS=0
    PATH="$tmp/bin:$PATH"
)
rc=0
env "${global_env[@]}" STT_ACTION=stop "$tmp/stt-global-mac.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || { echo "FAIL: stop no-op exited non-zero ($rc)"; exit 1; }
phase="$(cat "$runtime/phase" 2>/dev/null || true)"
[[ "$phase" == "idle" ]] || { echo "FAIL: expected phase idle after stop no-op, got [$phase]"; exit 1; }
[[ ! -f "$pidfile" ]] || { echo "FAIL: stop no-op left a pid file"; exit 1; }
echo "PASS global-stop-noop-when-idle"
