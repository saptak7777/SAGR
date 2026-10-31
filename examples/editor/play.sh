#!/usr/bin/env bash
# ==========================================
# examples/editor/play.sh
# Interactive Launcher for SAGR Simple Text Editor (Experimental Prototype)
#
# Connectors:
#   - Native X11 Window (Default when DISPLAY is active)
#     100% of pixels rendered by SAGR and blitted directly via XPutImage.
#   - Terminal Mode (when using --terminal or headless)
# ==========================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"

# Advisory single-instance lock to prevent accidental concurrent spawns
LOCK_FILE="/tmp/sagr_editor.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[SAGR ERROR] Another editor instance is already running ($LOCK_FILE is locked)."
    exit 1
fi

mkdir -p scratch bin

# 1. Compile SAGR SINC Core Engine
echo "[BUILD] Compiling SAGR SINC Text Editor Engine..."
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    examples/editor/editor.sinc > scratch/editor_bundle.sinc

./bin/sinc.elf scratch/editor_bundle.sinc scratch/editor.safe
./bin/packager_bin scratch/editor.safe scratch/editor_bin
chmod +x scratch/editor_bin
echo "[BUILD] SAGR Core Engine compiled successfully into scratch/editor_bin!"

# Check if terminal mode requested or if DISPLAY is missing
if [[ "${1:-}" == "--terminal" || "${1:-}" == "-t" || -z "${DISPLAY:-}" ]]; then
    echo "[LAUNCH] Running in native terminal mode..."
    cleanup() {
        if [ -t 0 ]; then
            stty sane 2>/dev/null || true
        fi
        printf "\033[?1049l\033[?25h\033[0m\n"
    }
    trap cleanup EXIT INT TERM

    if [ -t 0 ]; then
        stty raw -echo min 0 time 0 2>/dev/null || true
    fi

    ./scratch/editor_bin
    exit 0
fi

# 2. Compile Pure X11 Display Connector
echo "[BUILD] Compiling Simple X11 Display Connector..."
gcc -O2 examples/editor/x11_connector.c -lX11 -o scratch/sagr_x11
chmod +x scratch/sagr_x11

# 3. Launch Native X11 Window
echo "[LAUNCH] Opening SAGR Native X11 Desktop Window on DISPLAY=${DISPLAY}..."
# Release launcher build lock fd so x11_connector can acquire its own session lock
exec 200>&-
exec ./scratch/sagr_x11
