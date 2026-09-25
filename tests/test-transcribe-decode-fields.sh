#!/usr/bin/env bash
# Verifies the whisper.cpp decode fields: vad_filter, beam_size and the
# temperature fallback switch, with defaults and with everything turned off.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$ROOT/stt-transcribe.sh" "$tmp/"
cp "$ROOT/stt-runtime.sh" "$tmp/"
printf 'wav' > "$tmp/audio.wav"
mkdir -p "$tmp/bin"

# Fake curl: records every -F field name=value on its own line.
cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
prev=""
: > "$CAPTURE"
for arg in "$@"; do
    if [[ "$prev" == "-F" && "$arg" != file=* ]]; then
        printf '%s\n' "$arg" >> "$CAPTURE"
    fi
    prev="$arg"
done
printf '{"text":"ok"}\n200\n'
SH
chmod +x "$tmp/bin/curl"

run() {
    PATH="$tmp/bin:$PATH" CAPTURE="$tmp/fields.txt" STT_RUNTIME_DIR="$tmp/runtime" "$@" "$tmp/stt-transcribe.sh" "$tmp/audio.wav" >/dev/null
}
has() { grep -qxF "$1" "$tmp/fields.txt"; }

# 1. Defaults: VAD on, beam 5, no temperature fallback.
run env
for f in vad_filter=true beam_size=5 temperature=0 temperature_inc=0; do
    has "$f" || { echo "FAIL: default missing $f"; cat "$tmp/fields.txt"; exit 1; }
done

# 2. Everything off: none of the fields is sent.
run env STT_VAD_FILTER=0 STT_BEAM_SIZE="" STT_TEMPERATURE_FALLBACK=1
if grep -qE '^(vad_filter|beam_size|temperature|temperature_inc)=' "$tmp/fields.txt"; then
    echo "FAIL: fields sent although turned off"; cat "$tmp/fields.txt"; exit 1
fi

# 3. Invalid beam size is dropped, oversized is clamped to 8.
run env STT_BEAM_SIZE=abc
grep -q '^beam_size=' "$tmp/fields.txt" && { echo "FAIL: invalid beam sent"; exit 1; }
run env STT_BEAM_SIZE=99
has beam_size=8 || { echo "FAIL: beam not clamped"; exit 1; }
echo "PASS transcribe-decode-fields"
