#!/usr/bin/env bash
# Verifies legacy and extended replacement rows, including disabled entries.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

replacements="$tmp/replacements.tsv"
cat > "$replacements" <<'TSV'
horizon	horizOn
0	foo	bar	Allgemein	disabled
1	body seasons	BodySeasons	Projekt	brand
TSV

out="$(printf 'horizon foo body seasons' | \
    STT_RUNTIME_DIR="$tmp/runtime" \
    STT_REPLACEMENTS_FILE="$replacements" \
    STT_POSTPROCESS_FORCE_RAW=1 \
    STT_POSTPROCESS_LOG_ENABLED=0 \
    "$ROOT/stt-postprocess.sh")"

[[ "$out" == "horizOn foo BodySeasons" ]] || { echo "FAIL replacements: [$out]"; exit 1; }
echo "PASS replacements-extended-tsv"
