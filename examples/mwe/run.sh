#!/usr/bin/env bash
# ==========================================
# examples/mwe/run.sh
# Compile and run SAGR Minimal Working Example
# ==========================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"

mkdir -p scratch bin

echo "[BUILD] Bundling and compiling SAGR MWE..."
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/loom.sinc \
    sagr/sys/slsp.sinc \
    examples/mwe/mwe.sinc > scratch/mwe_bundle.sinc

./bin/sinc.elf scratch/mwe_bundle.sinc scratch/mwe.safe
./bin/packager_bin scratch/mwe.safe scratch/mwe_bin
chmod +x scratch/mwe_bin

echo "[EXEC] Running SAGR MWE..."
./scratch/mwe_bin

if [ -f scratch/mwe.ppm ]; then
    echo "[SUCCESS] Generated scratch/mwe.ppm ($(wc -c < scratch/mwe.ppm) bytes)!"
    head -n 3 scratch/mwe.ppm
else
    echo "[ERROR] scratch/mwe.ppm was not generated!"
    exit 1
fi
