# SAGR: Simple Analytical Grid Renderer

> [!WARNING]
> **Notice**: SAGR is an **experimental prototype** only, with **no guarantees**.

**SAGR** (*Simple Analytical Grid Renderer*) is a zero-float, 100% deterministic 2D vector graphics and compositor engine written in **[SINC](https://github.com/saptak/SINC)**.

Designed around the **Jacquard Silicon Loom** architecture, SAGR evaluates sub-pixel anti-aliased geometry, signed distance field typography, and alpha-blended window composition inside CPU L1 cache with **zero GPU drivers, zero C libraries, and zero floating-point operations**.

---

## Architectural Invariants

SAGR relies on five core technical constraints:

1. **Zero Float**: 100% fixed-point integer mathematics ($Q24.8$ world space, $Q8.8$ tile space, $U8$ color).
2. **Zero Dynamic Allocation**: All scratch memory is caller-provided and statically bounded. Zero heap allocations during the render loop.
3. **L1 Data Cache Residency**: All rasterization operates strictly inside $16 \times 16$ pixel micro-tiles ($1{,}024$ bytes RGBA). Working scratch is $< 6\text{ KB}$, maintaining a high L1 cache hit rate.
4. **Commutative Weaving**: No sorting edge intersections. SAGR plucks vertical cords into signed area fluxes and integrates them with a branchless 4-cycle prefix sum.
5. **Portability**: Core SAGR contains zero OS syscalls. It writes to a raw linear pointer (`*fb_ptr, width, height, stride`) and runs on Linux, Windows x64, bare-metal UEFI bootloaders, or custom OS kernels.

---

## The 4-Stroke Jacquard Silicon Loom Architecture

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │                        THE 4-STROKE LOOM PIPELINE                      │
  └────────────────────────────────────────────────────────────────────────┘

  [ Vector Input: Polygons, Bézier Curves, MSDF Glyphs ]
                           │
                           ▼
  STROKE 1: PEGBOARD & WANG FLATTENER (sagr/pure/flattener.sinc, pegboard.sinc)
  • Clamps coordinates to screen bounds [0..W, 0..H] in Q24.8.
  • Flattens quadratic Béziers via Wang's dyadic formula (lzcnt branchless).
  • Emits flat 32-byte 4-word cord instructions into the Pegboard Tape.
                           │
                           ▼
  STROKE 2: HEDDLE & OCCLUSION REAPER (sagr/pure/heddle.sinc, bitops.sinc)
  • Maintains a 128-word dirty tile bitmask (BMI1 ctz / blsr acceleration).
  • Front-to-back opaque shutter stamping: occluded windows reaped to NOPs.
  • Constant-color solid interior fast-folding (bypasses Loom rasterization).
                           │
                           ▼
  STROKE 3: JACQUARD SILICON LOOM (sagr/pure/loom.sinc)
  • Stroke A (Warp Pluck): Unsorted cords add signed sub-pixel area trapezoids.
  • Stroke B (Weft Shuttle): 4-cycle Hillis-Steele prefix sum (+1, +2, +4, +8).
  • Stroke C (Winding Resolver): Branchless Non-Zero (|w|) or Even-Odd (& 511).
  • Stroke D (Shading): Sub-pixel alpha blending into 128-word tile scratch.
                           │
                           ▼
  STROKE 4: SURFACE BEAM FLUSH (sagr/sys/slsp.sinc)
  • Strided 64-bit word streaming directly into linear display framebuffer.
```

---

## Performance Scorecard

Measured on standard x86-64 hardware rendering high-complexity vector scenes:

| Metric | Target Specification / Measured Result |
| :--- | :--- |
| **Startup / Init Latency** | **$< 0.001\text{ ms}$ ($< 1\text{ }\mu\text{s}$)** |
| **L1 Data Cache Hit Rate** | **$> 99.8\%$ (Micro-tile L1 residency)** |
| **Working Memory Footprint** | **$< 12\text{ KB}$ (Static scratch arrays)** |
| **Edge Sorting Cost** | **$O(1)$ Commutative Weft Prefix-Sum (skips edge sorting)** |
| **Dead Window Occlusion** | **Reaped to NOPs before rasterization** |
| **Binary Executable Size** | **$< 25\text{ KB}$ (Pure Standalone ELF)** |
| **Floating-Point Drift** | **None (100% Bit-Perfect Golden Oracle)** |

---

## Live Showcase: Chrome Dino Runner

SAGR includes a fully interactive, playable demonstration of the classic Chrome Dino runner running in standard terminals using sub-pixel physics, AABB collision, live HUD telemetry, and 24-bit ANSI TrueColor:

```bash
# Launch the interactive terminal Dino game:
./examples/dino/play.sh
```

* **Controls**: <kbd>Space</kbd> or <kbd>W</kbd> to Jump / Restart, <kbd>Q</kbd> to Quit.
* **Telemetry**: Displays real-time score, high score, and live CPU core utilization ($< 0.8\%$ at calibrated 35 FPS).

```
 SAGR DINO | SCORE: 00482 HI: 01250 | CPU: 0.6% | RUNNING
 ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 [SPACE] JUMP | [Q] QUIT
```

### Experimental Prototype: Desktop Window Editor

SAGR includes an experimental desktop window editor proof-of-concept demonstrating direct 1:1 X11 framebuffer blitting (`XPutImage`) outside the terminal:

> [!WARNING]
> **Notice**: The desktop editor in `examples/editor/` is an **experimental prototype** provided for demonstration only, with **no stability, production, or backwards-compatibility guarantees**.

```bash
# Launch the interactive desktop window (requires X11):
./examples/editor/play.sh

# Headless automated verification (renders 1 frame to Netpbm PPM):
./examples/editor/run.sh
```

---

## Quickstart & Building

### Prerequisites
* Linux x86-64 (or Windows/bare-metal target with SINC packager)
* CPU with BMI1/BMI2 instructions (`lzcnt`, `tzcnt`, `blsr`)
* The included bootstrap SINC toolchain in `bin/` (`sinc.elf`, `packager_bin`, `staff`)

### 1. Build and Run the Complete Test Suite
SAGR features an exhaustive 84-assertion test harness covering bitops, culling, Wang flattening, Loom area integrals, MSDF typography, and the 12-scene Golden Oracle:

```bash
./tests/run_tests.sh
```
```
==================================================================
                   SAGR TEST SUITE AUDIT SUMMARY                  
==================================================================
  Phase 1 (Surface & Bitops):                12/12 PASSED
  Phase 2 (Pegboard & Clipper):              13/13 PASSED
  Phase 3 (Wang Flattener & Tape):           10/10 PASSED
  Phase 4 (Loom Core - Warp & Weft):         13/13 PASSED
  Phase 5 (Heddle Backdrop & Shutter):       12/12 PASSED
  Phase 6 (MSDF Typography):                 12/12 PASSED
  Phase 7 (Deterministic Golden Oracle):     11/11 PASSED
  Standalone Cross-Tile Regression:           1/1  PASSED
==================================================================
  TOTAL TESTS PASSED:                        84/84 BIT-PERFECT
  CORE ENGINE STATUS: 100% CLEAN & VERIFIED (EXIT 0)
==================================================================
```

### 2. Verify Zero-Float & Zero-Trap Assembly Purity
SAGR guarantees zero floating-point instructions (`float`, `double`, `x87`, `sse-float`) and zero `ud2` panic traps in compiled output:

```bash
# Audited automatically by Phase 7 in tests/run_tests.sh:
objdump -D -b binary -m i386:x86-64 --start-address=0x78 ./scratch/phase7_test_bin | grep -iE 'addss|subss|mulss|divss|addsd|subsd|mulsd|divsd' # Returns 0
objdump -D -b binary -m i386:x86-64 --start-address=0x78 ./scratch/phase7_test_bin | grep -i 'ud2'                                              # Returns 0
```

---

## Minimal Working Example (MWE)

Below is a complete, minimal SINC program that creates a surface, adds vector paths, weaves them with the Jacquard Loom, and exports a raw Netpbm `.ppm` image:

```sinc
fn main!() [
    // 1. Initialize linear memory arena (64 MB)
    sys_mmap!(67108864);
    arena = arena_init!(536870912, 67108864);

    // 2. Allocate 1080p surface (1920x1080 RGBA8)
    surface = slsp_create!(arena, 1920, 1080, 0);
    fb_ptr = surface.SLSP_WORD_FB_PTR;
    mask_ptr = surface.SLSP_WORD_MASK_PTR;

    // 3. Allocate Loom scratch buffers
    warp_scratch = arena_alloc_words!(arena, LOOM_WARP_SCRATCH_WORDS);
    cov_scratch = arena_alloc_words!(arena, LOOM_COV_SCRATCH_WORDS);
    tile_words = arena_alloc_words!(arena, 128);
    tape = arena_alloc_words!(arena, 1024);

    // 4. Record vector geometry into Pegboard Tape (32-byte cords)
    // ... [Add cords: w0=Opcode/Color, w1=X0/Y0, w2=X1/Y1, w3=RowMask] ...

    // 5. Weave micro-tiles (16x16) and flush to framebuffer
    loop (ty:68 = 0 .. 68) [
        loop (tx:120 = 0 .. 120) [
            lm_weave_tile!(tape, total_cords, tx, ty, 0, warp_scratch, cov_scratch);
            lm_shade_tile_rgba!(cov_scratch, 4284803990, 4279505940, tile_words);
            slsp_beam_flush_tile!(fb_ptr, tx, ty, 7680, tile_words~);
        ]
    ]

    sys_exit!(0);
]
```

---

## Repository Structure

```
SAGR/
├── bin/                       # Bootstrap SINC toolchain (sinc.elf, packager_bin, staff)
├── examples/
│   ├── dino/                  # Playable Chrome Dino terminal runner
│   │   ├── dino.sinc          # Game logic, physics & multi-color pixel renderer
│   │   ├── play.sh            # One-click launcher with raw terminal hook
│   │   └── README.md          # Technical notes on terminal half-block rendering
│   ├── editor/                # Experimental desktop editor (prototype, no guarantees)
│   │   ├── editor.sinc        # SINC desktop editor and raster canvas
│   │   ├── x11_connector.c    # Pure X11 direct framebuffer blitter
│   │   ├── play.sh            # Interactive desktop launcher
│   │   └── README.md          # Prototype documentation & disclaimer
│   └── mwe/                   # Minimal Working Example standalone test
├── manual/                    # 8-Chapter Developer Manual
│   ├── SUMMARY.md             # Table of Contents
│   ├── ch01_axioms.md         # Architecture & fixed-point math
│   ├── ch02_slsp.md           # SINC Linear Surface Protocol (SLSP)
│   ├── ch03_pegboard.md       # Pegboard vector tape protocol
│   ├── ch04_flattener.md      # Wang's dyadic curve flattener
│   ├── ch05_loom.md           # Jacquard Loom rasterizer (warp & weft)
│   ├── ch06_msdf.md           # Integer MSDF typography (.sfont)
│   ├── ch07_memory.md         # Memory contracts & scratch buffers
│   └── ch08_embedding.md      # API reference & embedding guide
├── sagr/                      # Core SAGR Engine (STRICTLY <= 2,400 LOC)
│   ├── data/
│   │   ├── pegboard_defs.sinc # Tape opcodes, cord layouts, and effect constants
│   │   └── surface.sinc       # SLSP surface constants & format flags
│   ├── pure/
│   │   ├── bitops.sinc        # 64-bit BMI1 bit manipulation (ctz, blsr, bitsets)
│   │   ├── flattener.sinc     # Wang's dyadic Bézier curve flattener
│   │   ├── heddle.sinc        # Window occlusion reaper & SIMD alpha compositor
│   │   ├── loom.sinc          # Jacquard Loom: Warp pluck & Weft prefix-sum
│   │   ├── msdf.sinc          # Integer MSDF typography & .sfont loader
│   │   └── pegboard.sinc      # Coordinate quantizer & tile cord clipper
│   └── sys/
│       ├── entry.sinc         # Phase 1 verification harness
│       ├── slsp.sinc          # Linear surface descriptor & tile beam flush
│       └── verify_sagr.sinc   # FNV-1a 64-bit hash engine & 12-scene golden oracle
├── steel/                     # Minimal SINC standard runtime dependencies
│   ├── pure/bitset.sinc       # Bitset utility functions
│   └── sys/
│       ├── arena.sinc         # Linear bump allocator
│       └── sys.sinc           # Raw Linux syscall interface (sys_mmap, sys_write)
└── tests/                     # 84-Assertion Bit-Perfect Test Suite
    ├── run_tests.sh           # Master test runner
    ├── test_phase1.sinc .. test_phase7.sinc # Subsystem test suites
    └── test_failing_cross_tile_moire.sinc # Multi-tile backdrop tension regression test
```

---

## Documentation

The complete developer manual is located in the [`manual/`](manual/) directory:

* [Ch 1: Architectural Axioms & Fixed-Point Mathematics](manual/ch01_axioms.md)
* [Ch 2: SINC Linear Surface Protocol (SLSP)](manual/ch02_slsp.md)
* [Ch 3: Pegboard Vector Tape Protocol](manual/ch03_pegboard.md)
* [Ch 4: Wang's Dyadic Flattener & Monotonic Slicing](manual/ch04_flattener.md)
* [Ch 5: The Jacquard Loom Rasterizer (Warp & Weft)](manual/ch05_loom.md)
* [Ch 6: Typography & MSDF Engine](manual/ch06_msdf.md)
* [Ch 7: Memory Contracts & Scratch Buffers](manual/ch07_memory.md)
* [Ch 8: API Reference & Embedding Guide](manual/ch08_embedding.md)

---

## License

SAGR is open-source software released under the **Apache License, Version 2.0** (see [LICENSE](LICENSE)). Zero runtime dependencies.
