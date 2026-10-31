#!/usr/bin/env bash
# ==========================================
# examples/editor/run.sh
# Automated build, test, and render for SAGR Simple Text Editor (Experimental Prototype)
# ==========================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"

mkdir -p scratch bin

echo "[BUILD] Bundling and compiling SAGR Text Editor..."
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    examples/editor/editor.sinc > scratch/editor_bundle.sinc

./bin/sinc.elf scratch/editor_bundle.sinc scratch/editor.safe
./bin/packager_bin scratch/editor.safe scratch/editor_bin
chmod +x scratch/editor_bin
echo "[BUILD] Text Editor compiled successfully into scratch/editor_bin!"

echo "[EXEC] Running SAGR Text Editor (1 frame batch snapshot)..."
printf "q" | ./scratch/editor_bin > /dev/null

if [ -f scratch/editor.ppm ]; then
    PPM_BYTES=$(wc -c < scratch/editor.ppm | tr -d ' ')
    echo "[SUCCESS] Generated scratch/editor.ppm (${PPM_BYTES} bytes)!"
    head -n 3 scratch/editor.ppm
else
    echo "[ERROR] scratch/editor.ppm was not generated!"
    exit 1
fi

echo "[EXEC] Testing [SAVE] action..."
printf "s" | ./scratch/editor_bin > /dev/null 2>&1 || true

if [ -f scratch/editor_saved.txt ]; then
    echo "[SUCCESS] Generated scratch/editor_saved.txt:"
    cat scratch/editor_saved.txt
else
    echo "[ERROR] scratch/editor_saved.txt was not generated!"
    exit 1
fi

echo "[DONE] All editor tests passed cleanly!"
