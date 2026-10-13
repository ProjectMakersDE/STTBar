#!/usr/bin/env bash
# Shared legacy PID files and guessed process names must never authorize signals.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'if [[ -n "${child_pid:-}" ]]; then kill "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; fi; rm -rf "$tmp"' EXIT
cp "$ROOT/stt-record.sh" "$ROOT/stt-runtime.sh" "$tmp/"
legacy_pid="$tmp/legacy.pid"
legacy_wav="$tmp/legacy.wav"
printf '%100s' '' > "$legacy_wav"
perl -e '$SIG{INT}=sub{exit 0}; $SIG{TERM}=sub{exit 0}; sleep 60' &
child_pid=$!
sleep 0.1
printf '%s\n' "$child_pid" > "$legacy_pid"
record_env=(STT_RUNTIME_DIR="$tmp/runtime" STT_LEGACY_PID_FILE="$legacy_pid" STT_LEGACY_RECORD_FILE="$legacy_wav")
status="$(env "${record_env[@]}" "$tmp/stt-record.sh" status)"
[[ "$status" == idle ]] || { echo "FAIL: untrusted legacy PID reported recording"; exit 1; }
if env "${record_env[@]}" "$tmp/stt-record.sh" stop >/dev/null 2>&1; then
    echo "FAIL: stop accepted unrelated legacy PID"; exit 1
fi
env "${record_env[@]}" "$tmp/stt-record.sh" cancel >/dev/null
kill -0 "$child_pid" 2>/dev/null || { echo "FAIL: legacy PID caused a signal to unrelated process"; exit 1; }
[[ -f "$legacy_pid" && -f "$legacy_wav" ]] || { echo "FAIL: changed legacy files outside this runtime"; exit 1; }
# Even a PID copied into this runtime does not identify a rec/sox child.
printf '%s\n' "$child_pid" > "$tmp/runtime/recording.pid"
env "${record_env[@]}" "$tmp/stt-record.sh" cancel >/dev/null
kill -0 "$child_pid" 2>/dev/null || { echo "FAIL: unrelated current PID was signalled"; exit 1; }
# Invalid PIDs must not be interpreted as process-group signal targets.
printf '%s\n' '-1' > "$tmp/runtime/recording.pid"
[[ "$(env "${record_env[@]}" "$tmp/stt-record.sh" status)" == idle ]] || exit 1
# Simulate the launch window after identity is written but before PID is stored.
# Status polling must not remove launch metadata and orphan the real recorder.
rm -f "$tmp/runtime/recording.pid"
printf '%s\n' 'synthetic recorder identity' > "$tmp/runtime/recording.pid.identity"
[[ "$(env "${record_env[@]}" "$tmp/stt-record.sh" status)" == idle ]] || exit 1
[[ "$(cat "$tmp/runtime/recording.pid.identity" 2>/dev/null || true)" == 'synthetic recorder identity' ]] \
    || { echo "FAIL: status removed identity during recorder launch"; exit 1; }
echo "PASS record-refuses-untrusted-pids"
