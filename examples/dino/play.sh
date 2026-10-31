#!/usr/bin/env bash
# ==========================================
# examples/dino/play.sh
# Launcher for SAGR Dino Run
# ==========================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"

mkdir -p scratch bin

# 1. Compile bundle
echo "[BUILD] Bundling and compiling SAGR Dino via sinc.elf..."
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/loom.sinc \
    sagr/sys/slsp.sinc \
    examples/dino/dino.sinc > scratch/dino_bundle.sinc

./bin/sinc.elf scratch/dino_bundle.sinc scratch/dino.safe
./bin/packager_bin scratch/dino.safe scratch/dino_bin
chmod +x scratch/dino_bin
echo "[BUILD] Dino compiled successfully!"

# 2. Cleanup hook to restore terminal
cleanup() {
    if [ -t 0 ]; then
        stty sane 2>/dev/null || true
    fi
    printf "\033[?1049l\033[?25h\033[0m\n"
}
trap cleanup EXIT INT TERM

# 3. Put terminal into raw non-blocking mode if on a terminal
if [ -t 0 ]; then
    stty raw -echo min 0 time 0 2>/dev/null || true
fi

# 4. Run game
./scratch/dino_bin
