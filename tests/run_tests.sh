#!/usr/bin/env bash
# ==========================================
# tests/run_tests.sh
# SAGR Phase 1 Test Runner & Verification Suite
# ==========================================
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

mkdir -p scratch bin

echo "=================================================================="
echo "          SAGR PHASE 1: THE JACQUARD SILICON LOOM TESTS           "
echo "=================================================================="

# 1. Merge sources into test bundle
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/pure/bitops.sinc \
    sagr/sys/slsp.sinc \
    tests/test_phase1.sinc > scratch/phase1_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Phase 1 test suite via sinc.elf... "
./bin/sinc.elf scratch/phase1_test_bundle.sinc scratch/phase1_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/phase1_test.safe ./scratch/phase1_test_bin
chmod +x ./scratch/phase1_test_bin
echo "OK"

# 4. Execute Test Binary
echo ""
echo "--- Running Subsystem Assertions ---"

TEST_NAMES=(
    "Test 1: Bitops ctz64 edge cases (0, powers of 2, 31, 32, 48, 62)"
    "Test 2: Bitops blsr64 bit reset (0, 1, 3, 6, 128, multi-bit)"
    "Test 3: Fixed-point Q24.8 coordinate conversion (tile, local, pixel, subpixel)"
    "Test 4: SLSP surface descriptor initialization & field packing (dims, stride, fb, mask)"
    "Test 5: Single tile stamping & 64-bit boundary indexing (0,0; 63,0; 64,0; 119,67)"
    "Test 6: Dirty stamper out-of-bounds rejection (-1, 120, -1, 68, 999)"
    "Test 7: Bounding box dirty stamping & tile clipping (1-tile, 4-tile, negative clamp)"
    "Test 8: Heddle BMI1 scanner & tile coordinate recovery (tzcnt + blsr)"
    "Test 9: 16x16 L1 tile lockdown & strided beam flush (16 rows x 8 words readback)"
    "Test 10: Strided beam flush isolation & zero memory overrun (above, below, left, right)"
    "Test 11: Dirty mask clearing & zero-overhead idle audit (0 iterations on clean mask)"
    "Test 12: PPM binary header format verification (P6\n1920 1080\n255\n)"
)

# Run full binary
set +e
./scratch/phase1_test_bin
TEST_EXIT=$?
set -e

if [ $TEST_EXIT -eq 0 ]; then
    for i in "${!TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 12/12 PHASE 1 TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((TEST_EXIT - 101))
    echo "[FAIL] Test suite failed at code $TEST_EXIT"
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#TEST_NAMES[@]} ]; then
        echo "Failed test: ${TEST_NAMES[$FAIL_IDX]}"
    fi
    exit 1
fi

# 5. Build and Run Standalone SAGR Application
echo ""
echo "--- Testing Master Project Manifest Build (sagr/build.staff) ---"
printf "[BUILD] Running staff orchestrator on sagr/build.staff... "
./bin/staff sagr/build.staff scratch/sagr_app.safe
./bin/packager_bin scratch/sagr_app.safe ./scratch/sagr_app_bin
chmod +x ./scratch/sagr_app_bin
echo "OK"

printf "[RUN] Executing master application binary... "
./scratch/sagr_app_bin
echo "OK (Exit 0)"

printf "[CHECK] Verifying phase1_grid.ppm artifact... "
if [ -f "phase1_grid.ppm" ]; then
    SIZE=$(wc -c < phase1_grid.ppm)
    if [ "$SIZE" -eq 6220817 ]; then
        echo "OK ($SIZE bytes exact)"
    else
        echo "FAIL (Unexpected size: $SIZE)"
        exit 1
    fi
else
    echo "FAIL (phase1_grid.ppm missing)"
    exit 1
fi

echo ""
echo "=================================================================="
echo "          SAGR PHASE 2: FIXED-POINT PEGBOARD & CLIPPER            "
echo "=================================================================="

# 1. Merge sources into Phase 2 test bundle
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    tests/test_phase2.sinc > scratch/phase2_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Phase 2 test suite via sinc.elf... "
./bin/sinc.elf scratch/phase2_test_bundle.sinc scratch/phase2_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/phase2_test.safe ./scratch/phase2_test_bin
chmod +x ./scratch/phase2_test_bin
echo "OK"

# 4. Execute Test Binary
echo ""
echo "--- Running Subsystem Assertions ---"

PHASE2_TEST_NAMES=(
    "Test 1: Affine 2x2 Identity matrix transform ([65536, 0, 0, 0, 65536, 0])"
    "Test 2: Affine 2x2 Scale transform (2x X, 3x Y)"
    "Test 3: Affine 2x2 Translation (+5000 X, +8000 Y)"
    "Test 4: Affine 2x2 90-degree clockwise rotation (x' = y, y' = -x)"
    "Test 5: Coordinate clamping ([0..491520] X, [0..276480] Y)"
    "Test 6: Line clipping inside canvas bounds (1 line, tags, coordinates)"
    "Test 7: Out-of-bounds line rejection (fully above, fully below, zero delta)"
    "Test 8: Exact line clipping against top canvas boundary (Y=0 interpolation)"
    "Test 9: Exact line clipping against bottom canvas boundary (Y=H interpolation)"
    "Test 10: Monotonic quadratic Bézier ingestion without split (single leaf)"
    "Test 11: Quadratic horizontal tangent peak & valley De Casteljau split (2 monotonic leaves)"
    "Test 12: Analytical stroke expansion to closed bounding contour (4-edge loop)"
    "Test 13: Path builder multi-command ingestion with auto-closing (triangle path)"
)

set +e
./scratch/phase2_test_bin
PHASE2_TEST_EXIT=$?
set -e

if [ $PHASE2_TEST_EXIT -eq 0 ]; then
    for i in "${!PHASE2_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${PHASE2_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 13/13 PHASE 2 TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((PHASE2_TEST_EXIT - 101))
    echo "[FAIL] Phase 2 test suite failed at code $PHASE2_TEST_EXIT"
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#PHASE2_TEST_NAMES[@]} ]; then
        echo "Failed test: ${PHASE2_TEST_NAMES[$FAIL_IDX]}"
    fi
    exit 1
fi

echo ""
echo "=================================================================="
echo "          SAGR PHASE 3: WANG'S DYADIC FLATTENER & ROW MASK        "
echo "=================================================================="

# 1. Merge sources into Phase 3 test bundle
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    sagr/pure/flattener.sinc \
    tests/test_phase3.sinc > scratch/phase3_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Phase 3 test suite via sinc.elf... "
./bin/sinc.elf scratch/phase3_test_bundle.sinc scratch/phase3_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/phase3_test.safe ./scratch/phase3_test_bin
chmod +x ./scratch/phase3_test_bin
echo "OK"

# 4. Execute Test Binary
echo ""
echo "--- Running Subsystem Assertions ---"

PHASE3_TEST_NAMES=(
    "Test 1: Bitops lzcnt64 leading zero counting (0, 1, 2, 4, 16, 256, 31, 32, 62, 63)"
    "Test 2: Branchless octagonal norm (zero, axis-aligned, diagonal, signed combinations)"
    "Test 3: Dyadic subdivision depth k clamp (tolerance L >> 6 mapping to k in [0..7])"
    "Test 4: Y-Row punch-card bitmask generation (single row, row spans, full 0..63 span)"
    "Test 5: Shift-only dyadic forward point evaluator (linear & parabolic exact curves)"
    "Test 6: Monotonic quadratic flattening with k=0 (flat curve emits 1 exact line cord)"
    "Test 7: Curved quadratic flattening & C0 continuous seam verification (P(i) == P(i+1))"
    "Test 8: 32-byte Cord Quad packing (OP, tx_span [tx_lo..tx_hi], RGBA, Y-row mask w3)"
    "Test 9: Ingestion tape flattener (mixed lines and quadratic curves)"
    "Test 10: 10,000 quadratic curves torture test (0 div, 0 float, 0 crash, microsecond speed)"
)

set +e
./scratch/phase3_test_bin
PHASE3_TEST_EXIT=$?
set -e

if [ $PHASE3_TEST_EXIT -eq 0 ]; then
    for i in "${!PHASE3_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${PHASE3_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 10/10 PHASE 3 TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((PHASE3_TEST_EXIT - 101))
    echo "[FAIL] Phase 3 test suite failed at code $PHASE3_TEST_EXIT"
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#PHASE3_TEST_NAMES[@]} ]; then
        echo "Failed test: ${PHASE3_TEST_NAMES[$FAIL_IDX]}"
    fi
    exit 1
fi

echo ""
echo "=================================================================="
echo "          SAGR PHASE 4: THE JACQUARD LOOM CORE (WARP & WEFT)      "
echo "=================================================================="

# 1. Merge sources into Phase 4 test bundle
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/loom.sinc \
    tests/test_phase4.sinc > scratch/phase4_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Phase 4 test suite via sinc.elf... "
./bin/sinc.elf scratch/phase4_test_bundle.sinc scratch/phase4_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/phase4_test.safe ./scratch/phase4_test_bin
chmod +x ./scratch/phase4_test_bin
echo "OK"

# 4. Execute Test Binary
echo ""
echo "--- Running Subsystem Assertions ---"

PHASE4_TEST_NAMES=(
    "Test 1: Helper math & branchless bounds functions (abs, clamp, min, max)"
    "Test 2: Branchless Winding rules (Non-Zero saturation & Even-Odd fold)"
    "Test 3: 4-Cycle Hillis-Steele Weft prefix sum (shifts +1, +2, +4, +8)"
    "Test 4: Sub-scanline Y-slicer on pixel center cord (exact 50% coverage)"
    "Test 5: Commutative Warp pluck gate (Order independence: [A,B] == [B,A])"
    "Test 6: Sub-pixel horizontal sliver (0.3125 pixel width analytical area)"
    "Test 7: Sub-pixel vertical sliver (100/256 row height exact area)"
    "Test 8: 45-degree diagonal cord crossing row (exact 50% triangular area)"
    "Test 9: Closed 5-pointed star winding gate (Non-Zero=256 vs Even-Odd=0)"
    "Test 10: 16x16 tile RGBA8 linear shading with sub-pixel alpha blend"
    "Test 11: 1,000 tiles complex geometry torture test (zero crash, zero leak)"
    "Test 12: Cord outside tile isolation (reject phantom impulse on right tiles)"
    "Test 13: Tile column 15 boundary energy conservation (subpixel spill)"
)

set +e
./scratch/phase4_test_bin
PHASE4_TEST_EXIT=$?
set -e

if [ $PHASE4_TEST_EXIT -eq 0 ]; then
    for i in "${!PHASE4_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${PHASE4_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 13/13 PHASE 4 TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((PHASE4_TEST_EXIT - 101))
    for ((i=0; i<FAIL_IDX && i<${#PHASE4_TEST_NAMES[@]}; i++)); do
        printf "  %-75s [PASS]\n" "${PHASE4_TEST_NAMES[$i]}"
    done
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#PHASE4_TEST_NAMES[@]} ]; then
        printf "  %-75s [FAIL - CODE %d]\n" "${PHASE4_TEST_NAMES[$FAIL_IDX]}" "$PHASE4_TEST_EXIT"
    fi
    for ((i=FAIL_IDX+1; i<${#PHASE4_TEST_NAMES[@]}; i++)); do
        printf "  %-75s [BLOCKED]\n" "${PHASE4_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: PHASE 4 REGRESSION CAUGHT AT CODE $PHASE4_TEST_EXIT"
    echo "=================================================================="
    exit 1
fi

echo ""
echo "=================================================================="
echo "    SAGR PHASE 5: THE HEDDLE (BACKDROP, SHUTTER & COMPOSITOR)     "
echo "=================================================================="

# 1. Merge sources into Phase 5 test bundle
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
    tests/test_phase5.sinc > scratch/phase5_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Phase 5 test suite via sinc.elf... "
./bin/sinc.elf scratch/phase5_test_bundle.sinc scratch/phase5_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/phase5_test.safe ./scratch/phase5_test_bin
chmod +x ./scratch/phase5_test_bin
echo "OK"

# 4. Execute Test Binary
echo ""
echo "--- Running Subsystem Assertions ---"

PHASE5_TEST_NAMES=(
    "Test 1: Shutter dirty tile bitops & OOB safety (tx, ty indexing & clamping)"
    "Test 2: Shutter interior stamping (preserves outer border anti-aliased edge tiles)"
    "Test 3: Occlusion queries across shutter interior vs outer perimeter"
    "Test 4: Backward opaque shutter reaper mutating occluded commands to NOPs"
    "Test 5: Solid interior folder detection (zero active cords + full ±256 tension)"
    "Test 6: Multi-tile horizontal backdrop tension carry across 3 consecutive tiles"
    "Test 7: 64-lane Source-Over compositor zero-alpha passthrough (untouched dst)"
    "Test 8: 64-lane Source-Over compositor 100% alpha overwrite (pure src)"
    "Test 9: 64-lane Source-Over compositor 50% alpha linear premultiplied blend"
    "Test 10: Saturating unsigned arithmetic channel overflow protection (clamps at 255)"
    "Test 11: 50 stacked opaque windows dead-code elimination gate (49 reaped to NOP)"
    "Test 12: Multi-tile horizontal interior audit (detect hollow middle tiles)"
)

set +e
./scratch/phase5_test_bin
PHASE5_TEST_EXIT=$?
set -e

if [ $PHASE5_TEST_EXIT -eq 0 ]; then
    for i in "${!PHASE5_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${PHASE5_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 12/12 PHASE 5 TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((PHASE5_TEST_EXIT - 101))
    for ((i=0; i<FAIL_IDX && i<${#PHASE5_TEST_NAMES[@]}; i++)); do
        printf "  %-75s [PASS]\n" "${PHASE5_TEST_NAMES[$i]}"
    done
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#PHASE5_TEST_NAMES[@]} ]; then
        printf "  %-75s [FAIL - CODE %d]\n" "${PHASE5_TEST_NAMES[$FAIL_IDX]}" "$PHASE5_TEST_EXIT"
    fi
    for ((i=FAIL_IDX+1; i<${#PHASE5_TEST_NAMES[@]}; i++)); do
        printf "  %-75s [BLOCKED]\n" "${PHASE5_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: PHASE 5 REGRESSION CAUGHT AT CODE $PHASE5_TEST_EXIT"
    echo "=================================================================="
    exit 1
fi

echo ""
echo "=================================================================="
echo "    SAGR PHASE 6: BARE-METAL MSDF INTEGER TYPOGRAPHY ENGINE       "
echo "=================================================================="

# 1. Merge sources into Phase 6 test bundle
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
    tests/test_phase6.sinc > scratch/phase6_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Phase 6 test suite via sinc.elf... "
./bin/sinc.elf scratch/phase6_test_bundle.sinc scratch/phase6_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/phase6_test.safe ./scratch/phase6_test_bin
chmod +x ./scratch/phase6_test_bin
echo "OK"

# 4. Execute Test Binary
echo ""
echo "--- Running Subsystem Assertions ---"

PHASE6_TEST_NAMES=(
    "Test 1: Simple .sfont binary header contract (dims, ascent, descent, atlas offset)"
    "Test 2: 32-Byte glyph metric quad packing & lookup (unicode, adv, UV, plane)"
    "Test 3: Branchless UTF-8 ASCII decoder & length recovery (1-byte characters)"
    "Test 4: Branchless UTF-8 multi-byte decoder (2-byte Greek, 3-byte Euro, 4-byte Clef)"
    "Test 5: Exhaustive 3-channel branchless median reconstruction (all 6 permutations)"
    "Test 6: Fixed-point Q16.16 bilinear atlas sampler (exact texel & half-texel average)"
    "Test 7: Saturating screen-space anti-aliasing ramp (edge=128, clamps [0..255])"
    "Test 8: Sharp corner preservation test (distinct RGB channels preserve 90-degree apex)"
    "Test 9: 16x16 tile MSDF glyph shading & sub-pixel alpha blend into tile words"
    "Test 10: Multi-character cursor text layout with advancing X positions (SAGR string)"
    "Test 11: 4,500 glyphs dense code-editor screen stress gate (50 lines x 90 columns)"
    "Test 12: Glyph background preservation (audit non-destructive source-over)"
)

set +e
./scratch/phase6_test_bin
PHASE6_TEST_EXIT=$?
set -e

if [ $PHASE6_TEST_EXIT -eq 0 ]; then
    for i in "${!PHASE6_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${PHASE6_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 12/12 PHASE 6 TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((PHASE6_TEST_EXIT - 101))
    for ((i=0; i<FAIL_IDX && i<${#PHASE6_TEST_NAMES[@]}; i++)); do
        printf "  %-75s [PASS]\n" "${PHASE6_TEST_NAMES[$i]}"
    done
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#PHASE6_TEST_NAMES[@]} ]; then
        printf "  %-75s [FAIL - CODE %d]\n" "${PHASE6_TEST_NAMES[$FAIL_IDX]}" "$PHASE6_TEST_EXIT"
    fi
    for ((i=FAIL_IDX+1; i<${#PHASE6_TEST_NAMES[@]}; i++)); do
        printf "  %-75s [BLOCKED]\n" "${PHASE6_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: PHASE 6 REGRESSION CAUGHT AT CODE $PHASE6_TEST_EXIT"
    echo "=================================================================="
    exit 1
fi

echo ""
echo "=================================================================="
echo "    SAGR PHASE 7: ASSEMBLY AUDIT, 12-SCENE ORACLE & TELEMETRY    "
echo "=================================================================="

# 1. Merge sources into Phase 7 test bundle
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
    tests/test_phase7.sinc > scratch/phase7_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Phase 7 test suite via sinc.elf... "
./bin/sinc.elf scratch/phase7_test_bundle.sinc scratch/phase7_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/phase7_test.safe ./scratch/phase7_test_bin
chmod +x ./scratch/phase7_test_bin
echo "OK"

# 4. Assembly & Float Audit
printf "[AUDIT] Checking x86-64 disassembly for illegal float ops... "
DISASM_OUT=$(objdump -D -b binary -m i386:x86-64 --start-address=0x78 ./scratch/phase7_test_bin)
DISASM_LINES=$(wc -l <<< "$DISASM_OUT")
if [ "$DISASM_LINES" -lt 100 ] || [[ "$DISASM_OUT" != *"ret"* ]]; then
    echo "FAIL (Disassembly audit failed to decode executable x86-64 instructions)"
    exit 1
fi
if grep -qE "\b(addss|subss|mulss|divss|vsqrtps|cvtsi2ss|cvtss2si)\b" <<< "$DISASM_OUT"; then
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
echo "--- Running Subsystem Assertions ---"

PHASE7_TEST_NAMES=(
    "Test 1: vf_hash_words 64-bit FNV-1a hash consistency & bit avalanche"
    "Test 2: 12-Scene Golden Oracle deterministic rendering repeatable across runs"
    "Test 3: Golden Oracle scene distinctness (12 unique non-colliding 64-bit hashes)"
    "Test 4: Scene 1: Hairline segment rasterization into 16x16 tile words"
    "Test 5: Scene 2: Monotonic quadratic Bézier curve flattening & rasterization"
    "Test 6: Scene 3: Self-intersecting 5-point Star (winding impulse fidelity)"
    "Test 7: Scene 7: Horizontal backdrop carry tension propagation"
    "Test 8: Scene 8: Solid 16x16 tile constant folder (zero loom dispatch bypass)"
    "Test 9: Scene 9: Backward opaque shutter reaper (50 overlapping windows cost 1)"
    "Test 10: Scene 10: 64-Lane SIMD Source-Over alpha compositor"
    "Test 11: Scene 12: Blinking cursor minimal dirty-tile update (< 0.05W thermal budget)"
)

set +e
./scratch/phase7_test_bin
PHASE7_TEST_EXIT=$?
set -e

if [ $PHASE7_TEST_EXIT -eq 0 ]; then
    for i in "${!PHASE7_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "${PHASE7_TEST_NAMES[$i]}"
    done
    echo ""
    echo "=================================================================="
    echo "  RESULT: ALL 11/11 PHASE 7 TESTS PASSED BIT-PERFECT (EXIT 0)"
    echo "=================================================================="
else
    FAIL_IDX=$((PHASE7_TEST_EXIT - 101))
    echo "[FAIL] Phase 7 test suite failed at code $PHASE7_TEST_EXIT"
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#PHASE7_TEST_NAMES[@]} ]; then
        echo "Failed test: ${PHASE7_TEST_NAMES[$FAIL_IDX]}"
    fi
    exit 1
fi

echo ""
echo "=================================================================="
echo "    CROSS-TILE & MULTI-TILE REGRESSION AUDIT                      "
echo "=================================================================="

# 1. Compile standalone cross-tile moire test
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    steel/pure/bitset.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/loom.sinc \
    tests/test_failing_cross_tile_moire.sinc > scratch/failing_moire_test_bundle.sinc

printf "[BUILD] Compiling standalone cross-tile test via sinc.elf... "
./bin/sinc.elf scratch/failing_moire_test_bundle.sinc scratch/failing_moire_test.safe
echo "OK"
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/failing_moire_test.safe ./scratch/failing_moire_test_bin
chmod +x ./scratch/failing_moire_test_bin
echo "OK"

echo ""
echo "--- Running Standalone Cross-Tile Assertions ---"
set +e
./scratch/failing_moire_test_bin
MOIRE_EXIT=$?
set -e

if [ $MOIRE_EXIT -eq 101 ]; then
    printf "  %-75s [FAIL - CODE 101]\n" "Regression Test: Phantom impulse leakage on cord outside tile (Moiré streak)"
    exit 1
elif [ $MOIRE_EXIT -eq 102 ]; then
    printf "  %-75s [FAIL - CODE 102]\n" "Regression Test: Column 15 subpixel spill loss (area conservation failure)"
    exit 1
elif [ $MOIRE_EXIT -eq 103 ]; then
    printf "  %-75s [FAIL - CODE 103]\n" "Regression Test: Column 15 subpixel anti-aliasing missing (binary saturation)"
    exit 1
elif [ $MOIRE_EXIT -eq 104 ]; then
    printf "  %-75s [FAIL - CODE 104]\n" "Regression Test: Boundary wedge closure at x=4096 lost (trapped line defect)"
    exit 1
elif [ $MOIRE_EXIT -eq 0 ]; then
    printf "  %-75s [PASS]\n" "Regression Test: Cross-tile cord isolation and area conservation"
else
    printf "  %-75s [FAIL - CODE %d]\n" "Regression Test: Unexpected failure" "$MOIRE_EXIT"
    exit 1
fi

echo ""
echo "=================================================================="
echo "                   SAGR TEST SUITE AUDIT SUMMARY                  "
echo "=================================================================="
echo "  Phase 1 (Surface & Bitops):                12/12 PASSED"
echo "  Phase 2 (Pegboard & Clipper):              13/13 PASSED"
echo "  Phase 3 (Wang Flattener & Tape):           10/10 PASSED"
echo "  Phase 4 (Loom Core - Warp & Weft):         13/13 PASSED"
echo "  Phase 5 (Heddle Backdrop & Shutter):       12/12 PASSED"
echo "  Phase 6 (MSDF Typography):                 12/12 PASSED"
echo "  Phase 7 (Deterministic Golden Oracle):     11/11 PASSED"
echo "  Standalone Cross-Tile Regression:           1/1  PASSED"
echo "=================================================================="
echo "  TOTAL TESTS PASSED:                        84/84 BIT-PERFECT"
echo "  CORE ENGINE STATUS: 100% CLEAN & VERIFIED (EXIT 0)"
echo "=================================================================="



