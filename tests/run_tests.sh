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
printf "[BUILD] Running staff manifest build & compiling via sinc.elf... "
./bin/staff sagr/build.staff scratch/sagr_app_staff.safe
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/loom.sinc \
    sagr/pure/msdf.sinc \
    sagr/sys/slsp.sinc \
    sagr/sys/entry.sinc \
    steel/sys/driver_sagr_linux.sinc > scratch/sagr_app_bundle.sinc
./bin/sinc.elf scratch/sagr_app_bundle.sinc scratch/sagr_app.safe
./bin/packager_bin scratch/sagr_app.safe ./scratch/sagr_app_bin
chmod +x ./scratch/sagr_app_bin
echo "OK"

printf "[RUN] Executing master application binary... "
./scratch/sagr_app_bin
echo "OK (Exit 0)"

echo ""
echo "--- Stage A: Pure OS-Neutral sagr_core.safe Zero-Syscall Verification ---"
printf "[BUILD] Compiling OS-neutral sagr_core.safe (0 Syscalls / 0 Driver)... "
cat steel/sys/arena.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/loom.sinc \
    sagr/pure/msdf.sinc \
    sagr/sys/slsp.sinc \
    sagr/sys/entry.sinc > scratch/sagr_core_bundle.sinc

echo 'fn main!(tape_buf, tape_bytes, surf_ptr, arena) [ ret sagr_core!(tape_buf, tape_bytes, surf_ptr, arena); ]' >> scratch/sagr_core_bundle.sinc

./bin/sinc.elf scratch/sagr_core_bundle.sinc scratch/sagr_core.safe
echo "OK"

printf "[AUDIT] Checking sagr_core.safe for illegal syscalls (0F 05 / CD 80)... "
CORE_DISASM=$(objdump -D -b binary -m i386:x86-64 scratch/sagr_core.safe)
if grep -qE "\b(syscall|sysenter|int\s+\$0x80)\b" <<< "$CORE_DISASM"; then
    echo "FAIL (Found OS syscall instructions in sagr_core.safe!)"
    exit 1
else
    echo "PASS (0 syscall instructions detected in sagr_core.safe)"
fi

echo ""
echo "=================================================================="
echo "          SAGR PHASE 2: FIXED-POINT PEGBOARD & CLIPPER            "
echo "=================================================================="

# 1. Merge sources into Phase 2 test bundle
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
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
    "Test 1: TRG 64-byte binary header contract (magic 84, scripts, length)"
    "Test 2: O(1) TRG atlas grid UV cell derivation (u0, v0 mapping)"
    "Test 3: Branchless TRG 1-byte English script decoder (slots 0..61 -> Page 1)"
    "Test 4: Branchless TRG bilingual script decoder (Bank B Bengali & Tamil)"
    "Test 5: Exhaustive 3-channel branchless median reconstruction (all 6 permutations)"
    "Test 6: Fixed-point Q16.16 bilinear atlas sampler (exact texel & half-texel average)"
    "Test 7: Saturating screen-space anti-aliasing ramp (edge=128, clamps [0..255])"
    "Test 8: Sharp corner preservation test (distinct RGB channels preserve 90-degree apex)"
    "Test 9: 16x16 tile MSDF glyph shading & sub-pixel alpha blend into tile words"
    "Test 10: 1-Instruction branchless XOR bracket matching (bracket ^ 1)"
    "Test 11: msdf_layout_trg_line! TRG 1-byte container layout into out_positions"
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
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/pegboard.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/loom.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/msdf.sinc \
    sagr/sys/slsp.sinc \
    verify/verify_sagr.sinc \
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
echo "    SOVEREIGN ASSET ARCHITECTURE TESTS (.stile & .stape)          "
echo "=================================================================="

# 1. Merge sources into test bundle
cat steel/sys/sys.sinc \
    steel/sys/arena.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/loom.sinc \
    sagr/pure/msdf.sinc \
    sagr/sys/slsp.sinc \
    sagr/sys/entry.sinc \
    sassets/data/asset_defs.sinc \
    sassets/pure/stile.sinc \
    sassets/pure/stape.sinc \
    sassets/pure/bake_lexer.sinc \
    sassets/sys/bake_ppm.sinc \
    sassets/sys/bake_tile.sinc \
    sassets/sys/bake_tape.sinc \
    sassets/sys/entry.sinc \
    tests/test_assets.sinc > scratch/assets_test_bundle.sinc

# 2. Compile via SINC Native Compiler
printf "[BUILD] Compiling Asset test suite via sinc.elf... "
./bin/sinc.elf scratch/assets_test_bundle.sinc scratch/assets_test.safe
echo "OK"

# 3. Package into Standalone ELF Binary
printf "[BUILD] Packaging standalone ELF via packager_bin... "
./bin/packager_bin scratch/assets_test.safe ./scratch/test_assets_bin
chmod +x ./scratch/test_assets_bin
echo "OK"

# 4. Execute Test Binary
echo ""
echo "--- Running Subsystem Assertions ---"

ASSET_TEST_NAMES=(
    "Test 1: Sovereign asset 64-byte header contract & L1 alignment"
    "Test 2: Direct opaque micro-tile beam flush (0 blend arithmetic)"
    "Test 3: Translucent micro-tile Source-Over composite"
    "Test 4: Solid micro-tile vector broadcast from header"
    "Test 5: Vector cord shutter culling (EFFECT_SHUTTER = 2)"
    "Test 6: Premultiplied alpha bounded channel invariant (Out <= 255)"
    "Test 7: Zero-overhead O(1) micro-tile memory addressing"
    "Test 8: Simplified stile_get_dims 32-bit direct mask verification"
    "Test 9: Rect shutter interior stamping & occlusion reaper"
    "Test 10: .tile RGBA 4-state micro-tile layout & premultiplication"
    "Test 11: .tape Wang quadratic Bézier flattening & horizontal culling"
    "Test 12: Lexer hex nibbles, whitespace skipping, and EOF clamping"
    "Test 13: Declarative style parser (pure vs. shutter vector cords)"
    "Test 14: Sovereign In-Memory Asset Compiler Invalid Kind Rejection (ret 1)"
    "Test 15: End-to-end .stile opaque beam flush & translucent composite"
    "Test 16: End-to-end .stape shutter reap occlusion & backdrop weave"
    "Test 17: End-to-end TRG bake_core! -> sagr_core! multi-tile carry & alpha blend"
    "Test 18: TRG container validation, byte-0 ('A') palette & Hindi MSDF"
)

set +e
./scratch/test_assets_bin
ASSET_EXIT=$?
set -e

if [ $ASSET_EXIT -ne 0 ]; then
    FAIL_IDX=$((ASSET_EXIT - 101))
    if [ $FAIL_IDX -ge 0 ] && [ $FAIL_IDX -lt ${#ASSET_TEST_NAMES[@]} ]; then
        printf "  %-75s [FAIL - CODE %d]\n" "${ASSET_TEST_NAMES[$FAIL_IDX]}" "$ASSET_EXIT"
    else
        printf "  %-75s [FAIL - CODE %d]\n" "Asset Test Suite Failure" "$ASSET_EXIT"
    fi
    exit 1
else
    for name in "${ASSET_TEST_NAMES[@]}"; do
        printf "  %-75s [PASS]\n" "$name"
    done
fi

echo ""
echo "=================================================================="
echo "  RESULT: ALL 18/18 SOVEREIGN ASSET TESTS PASSED BIT-PERFECT (EXIT 0)"
echo "=================================================================="

# 5. Sovereign Asset Compiler Verification (bin/sagr-bake.elf + bin/trg_encode + bin/sagr-bake wrapper)
echo ""
echo "--- Building Pure SINC Asset Compiler via staff (bin/sagr-bake.elf) ---"
printf "[BUILD] Compiling sassets package via staff... "
./bin/staff sassets/build.staff scratch/sagr_bake.safe
echo "OK"
printf "[BUILD] Packaging standalone ELF via packager_bin (bin/sagr-bake.elf)... "
./bin/packager_bin scratch/sagr_bake.safe ./bin/sagr-bake.elf
chmod +x ./bin/sagr-bake.elf
echo "OK"

echo ""
echo "--- Stage A: Pure OS-Neutral sassets_core.safe Zero-Syscall Verification ---"
printf "[BUILD] Compiling OS-neutral sassets_core.safe (0 Syscalls / 0 Driver)... "
cat steel/sys/arena.sinc \
    sagr/data/surface.sinc \
    sagr/data/pegboard_defs.sinc \
    sagr/pure/bitops.sinc \
    sagr/pure/flattener.sinc \
    sagr/pure/heddle.sinc \
    sagr/pure/loom.sinc \
    sagr/sys/slsp.sinc \
    sassets/data/*.sinc \
    sassets/pure/*.sinc \
    sassets/sys/*.sinc > scratch/sassets_core_bundle.sinc

echo 'fn main!(src_buf, src_len, kind, out_buf, arena) [ ret bake_core!(src_buf, src_len, kind, out_buf, arena); ]' >> scratch/sassets_core_bundle.sinc

./bin/sinc.elf scratch/sassets_core_bundle.sinc scratch/sassets_core.safe
echo "OK"

printf "[AUDIT] Checking sassets_core.safe for illegal syscalls (0F 05 / CD 80)... "
SASSETS_DISASM=$(objdump -D -b binary -m i386:x86-64 scratch/sassets_core.safe)
if grep -qE "\b(syscall|sysenter|int\s+\$0x80)\b" <<< "$SASSETS_DISASM"; then
    echo "FAIL (Found OS syscall instructions in sassets_core.safe!)"
    exit 1
else
    echo "PASS (0 syscall instructions detected in sassets_core.safe)"
fi

echo ""
echo "--- Testing Pure SINC Asset Compiler (bin/sagr-bake) ---"
if [ -f "./bin/sagr-bake" ]; then
    printf "[CHECK] Verifying CLI argument validation (0 args -> exit 1)... "
    set +e
    ./bin/sagr-bake > /dev/null 2>&1
    ARG0_EXIT=$?
    set -e
    if [ "$ARG0_EXIT" -eq 1 ]; then
        echo "OK (Usage printed, exit 1)"
    else
        echo "FAIL (Unexpected exit: $ARG0_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying CLI missing input file error path (exit 1)... "
    set +e
    ./bin/sagr-bake scratch/no_such_file.tile scratch/out.stile > /dev/null 2>&1
    MISS_EXIT=$?
    set -e
    if [ "$MISS_EXIT" -eq 1 ]; then
        echo "OK (Exit 1)"
    else
        echo "FAIL (Unexpected exit: $MISS_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying CLI empty .tile error path (exit 2)... "
    echo -n "" > scratch/cli_empty.tile
    set +e
    ./bin/sagr-bake scratch/cli_empty.tile scratch/out.stile > /dev/null 2>&1
    EMPTY_TILE_EXIT=$?
    set -e
    if [ "$EMPTY_TILE_EXIT" -eq 2 ]; then
        echo "OK (Exit 2)"
    else
        echo "FAIL (Unexpected exit: $EMPTY_TILE_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying CLI .tile missing size: header error path (exit 3)... "
    echo "tile: 0 0" > scratch/cli_no_size.tile
    set +e
    ./bin/sagr-bake scratch/cli_no_size.tile scratch/out.stile > /dev/null 2>&1
    NO_SIZE_EXIT=$?
    set -e
    if [ "$NO_SIZE_EXIT" -eq 3 ]; then
        echo "OK (Exit 3)"
    else
        echo "FAIL (Unexpected exit: $NO_SIZE_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying CLI empty .tape error path (exit 2)... "
    echo -n "" > scratch/cli_empty.tape
    set +e
    ./bin/sagr-bake scratch/cli_empty.tape scratch/out.stape > /dev/null 2>&1
    EMPTY_TAPE_EXIT=$?
    set -e
    if [ "$EMPTY_TAPE_EXIT" -eq 2 ]; then
        echo "OK (Exit 2)"
    else
        echo "FAIL (Unexpected exit: $EMPTY_TAPE_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying CLI .tape zero cords error path (exit 4)... "
    echo "style: pure #FF0000FF" > scratch/cli_zero_cords.tape
    set +e
    ./bin/sagr-bake scratch/cli_zero_cords.tape scratch/out.stape > /dev/null 2>&1
    ZERO_CORDS_EXIT=$?
    set -e
    if [ "$ZERO_CORDS_EXIT" -eq 4 ]; then
        echo "OK (Exit 4)"
    else
        echo "FAIL (Unexpected exit: $ZERO_CORDS_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying CLI non-P6 .ppm magic error path (exit 3)... "
    echo "P3 1 1 255 0 0 0" > scratch/cli_bad.ppm
    set +e
    ./bin/sagr-bake scratch/cli_bad.ppm scratch/out.stile > /dev/null 2>&1
    BAD_PPM_EXIT=$?
    set -e
    if [ "$BAD_PPM_EXIT" -eq 3 ]; then
        echo "OK (Exit 3)"
    else
        echo "FAIL (Unexpected exit: $BAD_PPM_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying CLI unknown extension fail-fast error path (exit 1)... "
    echo "P6 1 1 255 0 0 0" > scratch/cli_bad.unknown
    set +e
    ./bin/sagr-bake scratch/cli_bad.unknown scratch/out.stile > /dev/null 2>&1
    BAD_EXT_EXIT=$?
    set -e
    if [ "$BAD_EXT_EXIT" -eq 1 ]; then
        echo "OK (Exit 1)"
    else
        echo "FAIL (Unexpected exit: $BAD_EXT_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying .stile compilation (PPM -> .stile)... "
    printf 'P6\n32 32\n255\n' > scratch/cli_test.ppm
    dd if=/dev/zero bs=3072 count=1 >> scratch/cli_test.ppm 2>/dev/null
    ./bin/sagr-bake scratch/cli_test.ppm scratch/cli_ppm_test.stile > /dev/null 2>&1
    SIZE_STILE=$(wc -c < scratch/cli_ppm_test.stile)
    if [ "$SIZE_STILE" -eq 4160 ]; then
        echo "OK ($SIZE_STILE bytes exact)"
    else
        echo "FAIL (Unexpected size: $SIZE_STILE)"
        exit 1
    fi

    printf "[CHECK] Verifying .tile compilation (Human-Readable .tile -> .stile RGBA)... "
    cat << 'EOF' > scratch/cli_hero.tile
# cli_hero.tile - 16x16 RGBA Sprite
size: 16 16
pal: . #00000000
pal: # #FF0000FF
pal: s #0000FF80
pal: w #FFFFFFFF
row: ......####......
row: ....########....
row: ...##w####w##...
row: ...##w####w##...
row: ....########....
row: .....######.....
row: ....ssssssss....
row: ...ssssssssss...
row: ..ssssssssssss..
row: ..ssssssssssss..
row: ...ss......ss...
row: ...ss......ss...
row: ...##......##...
row: ..####....####..
row: .######..######.
row: ................
EOF
    ./bin/sagr-bake scratch/cli_hero.tile scratch/hero_sinc_test.stile > /dev/null 2>&1
    SIZE_HERO=$(wc -c < scratch/hero_sinc_test.stile)
    if [ "$SIZE_HERO" -eq 1088 ]; then
        echo "OK ($SIZE_HERO bytes exact)"
    else
        echo "FAIL (Unexpected size: $SIZE_HERO)"
        exit 1
    fi

    printf "[CHECK] Verifying .stape compilation (TAPE -> .stape)... "
    cat << 'EOF' > scratch/cli_shutter.tape
bounds: 0 0 1920 1080
rect: 100 100 400 300 #FF0000FF pure
rect: 200 150 200 150 #00FF00FF shutter
line: 50 50 500 500 #0000FFFF pure
line: 100 200 300 400 #FFFF00FF shutter
EOF
    ./bin/sagr-bake scratch/cli_shutter.tape scratch/tape_sinc_test.stape > /dev/null 2>&1
    SIZE_STAPE=$(wc -c < scratch/tape_sinc_test.stape)
    if [ "$SIZE_STAPE" -eq 256 ]; then
        echo "OK ($SIZE_STAPE bytes exact)"
    else
        echo "FAIL (Unexpected size: $SIZE_STAPE)"
        exit 1
    fi

    printf "[CHECK] Verifying Bézier .tape compilation (.tape -> .stape with Wang Quads)... "
    cat << 'EOF' > scratch/cli_curve.tape
# cli_curve.tape - Vector with Bezier Curves
bounds: 0 0 500 500
rect: 10 10 80 80 #202020FF shutter
line: 10 10 90 90 #FFFFFFFF pure
quad: 20 50 50 10 80 50 #FFCC00FF pure
quad: 80 50 50 90 20 50 #00FFCCFF shutter
EOF
    ./bin/sagr-bake scratch/cli_curve.tape scratch/curve_sinc_test.stape > /dev/null 2>&1
    SIZE_CURVE=$(wc -c < scratch/curve_sinc_test.stape)
    if [ "$SIZE_CURVE" -eq 1184 ]; then
        echo "OK ($SIZE_CURVE bytes exact)"
    else
        echo "FAIL (Unexpected size: $SIZE_CURVE)"
        exit 1
    fi

    printf "[CHECK] Verifying direct TRG-native pipeline (bin/trg_encode -> bin/sagr-bake.elf)... "
    ./bin/trg_encode scratch/cli_curve.tape scratch/cli_curve.tape.trg
    ./bin/sagr-bake.elf scratch/cli_curve.tape.trg scratch/curve_elf_test.stape > /dev/null 2>&1
    SIZE_ELF_CURVE=$(wc -c < scratch/curve_elf_test.stape)
    cp scratch/cli_curve.tape scratch/bad_ascii.tape.trg
    set +e
    ./bin/sagr-bake.elf scratch/bad_ascii.tape.trg scratch/out.stape > /dev/null 2>&1
    BAD_TRG_EXIT=$?
    set -e
    if [ "$SIZE_ELF_CURVE" -eq 1184 ] && [ "$BAD_TRG_EXIT" -eq 3 ]; then
        echo "OK ($SIZE_ELF_CURVE bytes direct, non-TRG exit 3)"
    else
        echo "FAIL (size=$SIZE_ELF_CURVE bad_trg_exit=$BAD_TRG_EXIT)"
        exit 1
    fi

    printf "[CHECK] Verifying external text TRG encoding (SINC bin/trg_encode .txt -> .trg)... "
    printf "Hello SAGR 123\n" > scratch/cli_trg.txt
    ./bin/trg_encode scratch/cli_trg.txt scratch/cli_trg.trg
    SIZE_TRG=$(wc -c < scratch/cli_trg.trg)
    if [ "$SIZE_TRG" -eq 79 ]; then
        echo "OK ($SIZE_TRG bytes exact)"
    else
        echo "FAIL (Unexpected size: $SIZE_TRG)"
        exit 1
    fi
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
echo "  Sovereign Assets (.stile, .stape, .trg):   18/18 PASSED"
echo "=================================================================="
echo "  TOTAL TESTS PASSED:                       102/102 BIT-PERFECT"
echo "  CORE ENGINE STATUS: 100% CLEAN & VERIFIED (EXIT 0)"
echo "=================================================================="



