#!/usr/bin/env bash
# ==============================================================================
# tests/run_battle_test.sh
# SAGR Sovereign 2D Renderer Battle-Testing & Adversarial Stress Suite
# ==============================================================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

mkdir -p scratch bin

echo "=================================================================="
echo "          SAGR: SOVEREIGN 2D RENDERER BATTLE-TESTING SUITE        "
echo "=================================================================="

# 1. Merge sources into Battle-Test Bundle
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/loom.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/msdf.sinc \
    sagr/sys/slsp.sinc \
    tests/test_battle.sinc > scratch/battle_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Battle-Test Suite via sinc.elf... "
./bin/sinc.elf scratch/battle_test_bundle.sinc scratch/battle_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging Standalone ELF via packager_bin... "
./bin/packager_bin scratch/battle_test.safe ./scratch/battle_test_bin
chmod +x ./scratch/battle_test_bin
echo "OK"

# 4. Assembly & Float Audit
printf "[AUDIT] Checking x86-64 disassembly for illegal float ops... "
DISASM_OUT=$(objdump -D -b binary -m i386:x86-64 --start-address=0x78 ./scratch/battle_test_bin)
DISASM_LINES=$(wc -l <<< "$DISASM_OUT")
if [ "$DISASM_LINES" -lt 100 ] || [[ "$DISASM_OUT" != *"ret"* ]]; then
    echo "FAIL (Disassembly audit failed to decode executable instructions)"
    exit 1
fi
if grep -qE "\b(addss|subss|mulss|divss|vsqrtps|cvtsi2ss|cvtss2si|ucomiss)\b" <<< "$DISASM_OUT"; then
    echo "FAIL (Found floating-point instructions!)"
    exit 1
else
    echo "PASS (0 float instructions detected across $DISASM_LINES lines)"
fi

printf "[AUDIT] Checking x86-64 disassembly for panic traps (ud2)... "
if grep -qE "\bud2\b" <<< "$DISASM_OUT"; then
    echo "FAIL (Found ud2 trap instructions!)"
    exit 1
else
    echo "PASS (0 ud2 traps detected)"
fi

# 5. Execute Test Binary
echo ""
echo "--- Running Adversarial Subsystem Assertions ---"

BATTLE_TEST_NAMES=(
    "Test 1: Degenerate geometry - Zero-length cord (100,100 -> 100,100)"
    "Test 2: Degenerate geometry - Pure horizontal line across full tile (delta_y=0)"
    "Test 3: Anti-symmetric cancellation - Opposite diagonals cancel to 0 net flux"
    "Test 4: Boundary vertical line at x=0 (Tile left edge exact 100% saturation)"
    "Test 5: Boundary vertical line at x=4096 (Tile right edge carry slot handoff)"
    "Test 6: Sub-pixel micro-segment (1 subpixel dx=1, dy=1 numerical stability)"
    "Test 7: Canvas boundary clipper & giant diagonal clamp [0..491520, 0..276480]"
    "Test 8: Nyquist Moiré frequency grid (8 alternating 1px vertical bars, 0 bleed)"
    "Test 9: Closed right triangle discrete Green's theorem area conservation"
    "Test 10: Multi-tile horizontal tension propagation across 4 micro-tiles"
    "Test 11: Commutativity - Order-independent unsorted cord plucking (3 permutations)"
    "Test 12: Sub-pixel AA linearity - Monotonic 16-step ramp across pixel column"
    "Test 13: High-order winding number resolution (even-odd vs non-zero at w=3,4)"
    "Test 14: Bowtie self-intersecting polygon non-zero & even-odd winding"
    "Test 15: Degenerate Bézier - Coincident control points (P0=P1=P2 flat leaf)"
    "Test 16: Collinear Bézier - Zero curvature Wang norm k=0 straight chord"
    "Test 17: Maximum curvature Wang flattener (k=7, 128 segments) & C0 continuity"
    "Test 18: Peak/valley horizontal tangent De Casteljau root splitting"
    "Test 19: TRG 1-byte decoding & boundary stress ([0..111], [128..239], syntax)"
    "Test 20: MSDF 27-state exhaustive 3-channel median filter verification"
    "Test 21: msdf_layout_trg_line! bounds truncation & invalid magic rejection"
    "Test 22: Framebuffer 4-corner beam flush & 1024-byte canary guard audit"
    "Test 23: Dirty tile mask 8160-tile indexing & corner bit (119, 67) boundary"
    "Test 24: Backward opaque shutter reaper (100 overlapping windows cost 1)"
    "Test 25: PRNG Fuzzing Gate - 1,000 fuzzed coordinates through clipper & loom"
    "Test 26: PRNG Stress Torture - 500 overlapping closed triangles in micro-tile"
)

set +e
./scratch/battle_test_bin
BATTLE_EXIT=$?
set -e

if [ $BATTLE_EXIT -eq 0 ]; then
    for i in "${!BATTLE_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${BATTLE_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 26/26 BATTLE TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((BATTLE_EXIT - 101))
    echo "[FAIL] Battle-test suite failed at code $BATTLE_EXIT"
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#BATTLE_TEST_NAMES[@]} ]; then
        echo "Failed test: ${BATTLE_TEST_NAMES[$FAIL_IDX]}"
    fi
    exit 1
fi

# 6. Performance & Throughput Benchmark
echo ""
echo "--- Performance & Latency Telemetry ---"
START_NS=$(date +%s%N)
RUNS=100
for ((r=0; r<RUNS; r++)); do
    ./scratch/battle_test_bin
done
END_NS=$(date +%s%N)
TOTAL_NS=$((END_NS - START_NS))
AVG_US=$((TOTAL_NS / RUNS / 1000))
AVG_MS_DEC=$((AVG_US / 1000)).$(( (AVG_US % 1000) / 10 ))

echo "  Completed $RUNS consecutive stress cycles in $((TOTAL_NS / 1000000)) ms"
echo "  Average execution latency: ${AVG_MS_DEC} ms (${AVG_US} µs) per full battle cycle"
echo "  Throughput: $(( 1000000 / (AVG_US > 0 ? AVG_US : 1) )) battle cycles / second"
echo ""
echo "=================================================================="
echo "          BATTLE-TESTING STATUS: SOVEREIGN & BIT-PERFECT          "
echo "=================================================================="

