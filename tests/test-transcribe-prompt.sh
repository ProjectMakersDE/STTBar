#!/usr/bin/env bash
# Verifies STT_PROMPT is sent as the Whisper `prompt` form field, that "off"
# suppresses it, and that an echoed prompt is stripped from the transcript.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$ROOT/stt-transcribe.sh" "$tmp/"
cp "$ROOT/stt-runtime.sh" "$tmp/"
printf 'wav' > "$tmp/audio.wav"
mkdir -p "$tmp/bin"

# Fake curl: records the prompt form field and answers with $FAKE_TEXT.
cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
prev=""
: > "$CAPTURE"
for arg in "$@"; do
    if [[ "$prev" == "-F" && "$arg" == prompt=* ]]; then
        printf '%s' "${arg#prompt=}" > "$CAPTURE"
    fi
    prev="$arg"
done
printf '{"text":"%s"}\n200\n' "$FAKE_TEXT"
SH
chmod +x "$tmp/bin/curl"

run() {
    PATH="$tmp/bin:$PATH" CAPTURE="$tmp/prompt.txt" STT_RUNTIME_DIR="$tmp/runtime" "$@" "$tmp/stt-transcribe.sh" "$tmp/audio.wav"
}

# 1. Explicit prompt is sent.
out="$(run env STT_PROMPT="Hallo, das ist ein Test." FAKE_TEXT="Bitte Milch kaufen.")"
[[ "$(cat "$tmp/prompt.txt")" == "Hallo, das ist ein Test." ]] || { echo "FAIL: prompt not sent: [$(cat "$tmp/prompt.txt")]"; exit 1; }
[[ "$out" == "Bitte Milch kaufen." ]] || { echo "FAIL: got [$out]"; exit 1; }

# 2. Unset prompt falls back to a punctuated language default.
out="$(run env STT_LANGUAGE=de FAKE_TEXT="ok")"
[[ "$(cat "$tmp/prompt.txt")" == *.* ]] || { echo "FAIL: no default prompt for de: [$(cat "$tmp/prompt.txt")]"; exit 1; }
out="$(run env STT_LANGUAGE=auto FAKE_TEXT="ok")"
[[ -z "$(cat "$tmp/prompt.txt")" ]] || { echo "FAIL: prompt sent for auto language"; exit 1; }

# 3. "off" suppresses the field.
out="$(run env STT_PROMPT=off FAKE_TEXT="ok")"
[[ -z "$(cat "$tmp/prompt.txt")" ]] || { echo "FAIL: prompt sent despite off"; exit 1; }

# 4. An echoed prompt is stripped from the transcript (case-insensitive).
out="$(run env STT_PROMPT="Hallo, das ist ein Test." FAKE_TEXT="hallo, das ist ein test. Bitte Milch kaufen.")"
[[ "$out" == "Bitte Milch kaufen." ]] || { echo "FAIL: echoed prompt not stripped: [$out]"; exit 1; }

# 5. A transcript consisting only of the prompt counts as empty.
if run env STT_PROMPT="Hallo, das ist ein Test." FAKE_TEXT="Hallo, das ist ein Test." >/dev/null 2>&1; then
    echo "FAIL: prompt-only transcript should fail as empty"; exit 1
fi
echo "PASS transcribe-prompt"
