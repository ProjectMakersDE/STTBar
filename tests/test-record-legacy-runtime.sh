#!/usr/bin/env bash
# Verifies the namespaced runtime can still detect and stop legacy /tmp recordings.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'if [[ -n "${sleep_pid:-}" ]]; then kill "$sleep_pid" 2>/dev/null || true; fi; rm -rf "$tmp"' EXIT

cp "$ROOT/stt-record.sh" "$tmp/"
cp "$ROOT/stt-runtime.sh" "$tmp/"

legacy_pid="$tmp/legacy.pid"
legacy_wav="$tmp/legacy.wav"
printf '01234567890123456789012345678901234567890123456789' > "$legacy_wav"
perl -e '$SIG{INT}=sub{exit 0}; $SIG{TERM}=sub{exit 0}; sleep 60' &
sleep_pid=$!
printf '%s\n' "$sleep_pid" > "$legacy_pid"

status="$(STT_RUNTIME_DIR="$tmp/runtime" STT_LEGACY_PID_FILE="$legacy_pid" STT_LEGACY_RECORD_FILE="$legacy_wav" "$tmp/stt-record.sh" status)"
[[ "$status" == "recording" ]] || { echo "FAIL legacy status: [$status]"; exit 1; }

out="$(STT_RUNTIME_DIR="$tmp/runtime" STT_LEGACY_PID_FILE="$legacy_pid" STT_LEGACY_RECORD_FILE="$legacy_wav" "$tmp/stt-record.sh" stop)"
[[ "$out" == "$legacy_wav" ]] || { echo "FAIL legacy stop path: [$out]"; exit 1; }
for _ in 1 2 3 4 5; do
    if ! kill -0 "$sleep_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
if kill -0 "$sleep_pid" 2>/dev/null; then
    stat="$(ps -p "$sleep_pid" -o stat= 2>/dev/null || true)"
    if [[ "$stat" == *Z* || -z "$stat" ]]; then
        wait "$sleep_pid" 2>/dev/null || true
    else
        echo "FAIL legacy process still alive"
        exit 1
    fi
fi
sleep_pid=""

echo "PASS record-legacy-runtime"

legacy_wav2="$tmp/legacy-orphan.wav"
printf '01234567890123456789012345678901234567890123456789' > "$legacy_wav2"
bash -c 'exec -a rec perl -e '"'"'$SIG{INT}=sub{exit 0}; $SIG{TERM}=sub{exit 0}; sleep 60'"'"' "$@"' _ "$legacy_wav2" &
sleep_pid=$!

status="$(STT_RUNTIME_DIR="$tmp/runtime2" STT_LEGACY_PID_FILE="$tmp/missing.pid" STT_LEGACY_RECORD_FILE="$legacy_wav2" "$tmp/stt-record.sh" status)"
[[ "$status" == "recording" ]] || { echo "FAIL orphan legacy status: [$status]"; exit 1; }

STT_RUNTIME_DIR="$tmp/runtime2" STT_LEGACY_PID_FILE="$tmp/missing.pid" STT_LEGACY_RECORD_FILE="$legacy_wav2" "$tmp/stt-record.sh" cancel
for _ in 1 2 3 4 5; do
    if ! kill -0 "$sleep_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
if kill -0 "$sleep_pid" 2>/dev/null; then
    stat="$(ps -p "$sleep_pid" -o stat= 2>/dev/null || true)"
    if [[ "$stat" == *Z* || -z "$stat" ]]; then
        wait "$sleep_pid" 2>/dev/null || true
    else
        echo "FAIL orphan legacy process still alive"
        exit 1
    fi
fi
sleep_pid=""

echo "PASS record-legacy-orphan-runtime"
