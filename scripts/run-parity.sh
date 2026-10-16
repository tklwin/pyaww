#!/bin/bash
# Gate 1 — one-command parity check: build pyaww-cli, transcribe the full
# golden set, compare with the Python reference outputs and report CER.
#
# Usage: scripts/run-parity.sh
# Exits nonzero on any unexpected difference (tests/fixtures/README or
# docs/decisions.md for the g2063 tolerance).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== building pyaww-cli =="
swift build

run_dir=$(mktemp -d "${TMPDIR:-/tmp}/pyaww-parity.XXXXXX")
trap 'rm -rf "$run_dir"' EXIT
outputs="$run_dir/swift_outputs.tsv"

clip_count=$(find Tests/Fixtures/audio -name '*.wav' | wc -l | tr -d ' ')
echo "== transcribing $clip_count golden clips =="
start=$SECONDS
.build/debug/pyaww-cli --model-dir Models Tests/Fixtures/audio/*.wav > "$outputs"
echo "   ($((SECONDS - start)) s)"

if [ -f myanmar_asr/example.mp3 ]; then
    echo "== transcribing bonus example.mp3 =="
    .build/debug/pyaww-cli --model-dir Models myanmar_asr/example.mp3 >> "$outputs"
fi

echo "== comparing with the Python reference =="
python3 scripts/parity_swift.py "$outputs"
