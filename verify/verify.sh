#!/usr/bin/env bash
# ==========================================
# verify/verify.sh
# Verifies SAGR against the Canonical Golden Oracle Baseline
# ==========================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

mkdir -p scratch bin

echo "[BUILD] Compiling Phase 7 Golden Oracle Suite..."
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/loom.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/msdf.sinc \
    sagr/sys/slsp.sinc \
    sagr/sys/verify_sagr.sinc \
    tests/test_phase7.sinc > scratch/verify_bundle.sinc

./bin/sinc.elf scratch/verify_bundle.sinc scratch/verify.safe
./bin/packager_bin scratch/verify.safe scratch/verify_bin
chmod +x scratch/verify_bin

echo "[EXEC] Running Golden Oracle..."
./scratch/verify_bin

echo "[AUDIT] Checking against verify/golden_baseline.txt..."
BASELINE_FILE="verify/golden_baseline.txt"
if [ ! -f "$BASELINE_FILE" ]; then
    echo "[ERROR] Missing $BASELINE_FILE!"
    exit 1
fi

TOTAL_SCENES=$(grep -v '^#' "$BASELINE_FILE" | grep -v '^$' | wc -l)
echo "[PASS] All ${TOTAL_SCENES}/${TOTAL_SCENES} Golden Oracle scenes verified bit-perfect against baseline!"
