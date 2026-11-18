#!/usr/bin/env bash
# ==========================================
# examples/image_viewer/run.sh
# Pure SAGR Sovereign Image Viewer Driver
# Strictly Consumes Pre-Baked .stile Files
# ==========================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"

mkdir -p scratch bin

# Default to pre-baked sample if no argument provided
DEFAULT_STILE="scratch/sample.stile"
STILE_FILE="${1:-$DEFAULT_STILE}"

echo "=================================================================="
echo "          SAGR: SOVEREIGN RASTER IMAGE VIEWER                     "
echo "=================================================================="

# Auto-bake sample asset if user ran without arguments and default is missing
if [ -z "${1:-}" ] && [ ! -f "$STILE_FILE" ]; then
    echo "[SETUP] Baking default sample asset from examples/image_viewer/assets/sample.tile..."
    ./bin/sagr-bake examples/image_viewer/assets/sample.tile "$STILE_FILE"
fi

# 1. Enforce strict .stile input contract (No runtime baking in viewer)
if [[ "$STILE_FILE" != *.stile ]]; then
    echo "[ERROR] Invalid asset format: '$STILE_FILE'"
    echo ""
    echo "The SAGR runtime viewer strictly consumes pre-baked .stile assets."
    echo "It does NOT compile or bake foreign formats (PNG/PPM) at runtime."
    echo ""
    echo "To bake an asset ahead of time:"
    echo "  1. From PPM:   ./bin/sagr-bake input.ppm output.stile"
    echo "  2. From .tile: ./bin/sagr-bake input.tile output.stile"
    echo ""
    echo "Usage: $0 <path/to/asset.stile>"
    exit 1
fi

if [ ! -f "$STILE_FILE" ]; then
    echo "[ERROR] File not found: '$STILE_FILE'"
    echo "Please provide a valid pre-baked .stile file."
    exit 1
fi

echo "[INPUT] Target Asset: $STILE_FILE ($(wc -c < "$STILE_FILE") bytes)"

# 2. Bundle and compile viewer in pure SINC
echo ""
echo "[BUILD] Bundling and compiling SAGR Image Viewer via sinc.elf..."
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/loom.sinc \
    sagr/sys/slsp.sinc \
    sassets/pure/stile.sinc \
    examples/image_viewer/image_viewer.sinc > scratch/image_viewer_bundle.sinc

./bin/sinc.elf scratch/image_viewer_bundle.sinc scratch/image_viewer.safe
./bin/packager_bin scratch/image_viewer.safe scratch/image_viewer_bin
chmod +x scratch/image_viewer_bin
echo "[BUILD] Image Viewer compiled successfully into scratch/image_viewer_bin!"

# 3. Execute Image Viewer on the .stile asset
echo ""
echo "[EXEC] Rendering $STILE_FILE onto native SAGR framebuffer..."
./scratch/image_viewer_bin "$STILE_FILE"

if [ -f scratch/image_view.ppm ]; then
    PPM_SIZE=$(wc -c < scratch/image_view.ppm)
    echo "[SUCCESS] Generated raw framebuffer dump: scratch/image_view.ppm ($PPM_SIZE bytes)!"

    # Optional: desktop viewer convenience
    if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -v error -i scratch/image_view.ppm scratch/image_view.png
        PNG_SIZE=$(wc -c < scratch/image_view.png)
        echo "[DESKTOP] Converted to scratch/image_view.png ($PNG_SIZE bytes) for desktop inspection."
    fi
else
    echo "[ERROR] scratch/image_view.ppm was not generated!"
    exit 1
fi

echo ""
echo "=================================================================="
echo "  SAGR IMAGE VIEWER RUN COMPLETED SUCCESSFULLY (EXIT 0)           "
echo "=================================================================="
