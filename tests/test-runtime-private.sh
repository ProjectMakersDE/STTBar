#!/usr/bin/env bash
# Private runtime defaults and refusal of symlinks use only temporary fixtures.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
source "$ROOT/stt-runtime.sh"
TMPDIR="$tmp"
unset STT_RUNTIME_DIR
stt_runtime_init
[[ "$STT_RUNTIME_DIR" == "$tmp/de.projectmakers.stt-$(id -u)" ]] || { echo "FAIL: default runtime is not per-user"; exit 1; }
mode="$(stat -f %Lp "$STT_RUNTIME_DIR" 2>/dev/null || stat -c %a "$STT_RUNTIME_DIR")"
[[ "$mode" == 700 ]] || { echo "FAIL: runtime permissions are $mode"; exit 1; }
mkdir "$tmp/target"
ln -s "$tmp/target" "$tmp/link"
STT_RUNTIME_DIR="$tmp/link"
if stt_runtime_init 2>/dev/null; then
    echo "FAIL: accepted a symlink runtime"; exit 1
fi
echo "PASS runtime-private-directory"
