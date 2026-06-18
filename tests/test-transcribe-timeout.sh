#!/usr/bin/env bash
# Verifies STT_TRANSCRIBE_TIMEOUT is passed to curl --max-time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$ROOT/stt-transcribe.sh" "$tmp/"
cp "$ROOT/stt-runtime.sh" "$tmp/"
printf 'wav' > "$tmp/audio.wav"
mkdir -p "$tmp/bin"

cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
expected="${EXPECT_TIMEOUT:-7}"
found=0
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--max-time" && "$arg" == "$expected" ]]; then
        found=1
    fi
    prev="$arg"
done
if [[ "$found" != "1" ]]; then
    echo "missing expected --max-time $expected" >&2
    exit 9
fi
printf '{"text":"ok"}\n200\n'
SH
chmod +x "$tmp/bin/curl"

cat > "$tmp/bin/jq" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" -n "* ]]; then
    printf '{}\n'
else
    printf 'ok\n'
fi
SH
chmod +x "$tmp/bin/jq"

out="$(PATH="$tmp/bin:$PATH" EXPECT_TIMEOUT=7 STT_RUNTIME_DIR="$tmp/runtime" STT_TRANSCRIBE_TIMEOUT=7 "$tmp/stt-transcribe.sh" "$tmp/audio.wav")"
[[ "$out" == "ok" ]] || { echo "FAIL: got [$out]"; exit 1; }
echo "PASS transcribe-timeout"
