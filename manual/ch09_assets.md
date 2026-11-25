# Chapter 9: Sovereign Asset Architecture (.stile & .stape)

The **Sovereign Asset Architecture** extends SAGR's hardware-first philosophy to external media: **visual assets contain zero foreign container formats, zero runtime decoders, and zero floating-point math.**

At runtime, image files and vector paths are memory-mapped (`mmap!`) directly into virtual address space and executed as native physical silicon structures.

---

## 1. The Sovereign Invariant (Zero Runtime Decoders)

Traditional UI and game engines ingest 1990s desktop formats (PNG, JPEG, SVG, TTF). Inside the render loop, this forces thousands of lines of parser code, heap allocations, and massive decompression latency into the application binary.

SAGR incinerates runtime format parsing:
* **Zero Runtime Decoders**: Zero PNG, JPEG, SVG, or TTF parsers in the binary.
* **Pre-Baked Silicon Alignment**: Assets are compiled ahead of time (AOT) into memory-mapped arrays matching x86-64-v4 register lanes and cache lines.
* **Sibling Protocol (Law 12)**: Asset compilation strictly mirrors SINC compiler compilation:
  - `.sinc` (ASCII code) $\to$ `sinc.elf` $\to$ `.safe` (native machine code)
  - `.tape` (ASCII vectors) $\to$ `bin/sagr-bake` $\to$ `.stape` (32-byte Cord Quads)
  - `.ppm` / `.tile` (ASCII / Netpbm rasters) $\to$ `bin/sagr-bake` $\to$ `.stile` (1,024-byte micro-tiles)

---

## 2. Unified 64-Byte Cache-Line Header Contract

Every `.stile` and `.stape` binary begins with an 8-QWORD (64-byte) header matching hardware Cache Line 0:

```
Byte Offset   0x00               0x08                                0x3F 0x40
              ┌──────────────────┬───────────────────────────────────────┬───────────────────────────┐
Cache Line 0  │  Word 0 (Magic)  │       Words 1..7 (Zero-Pad)           │  Byte 64+ Payload Start   │
              │  32-bit + Dims   │       56 Bytes (hdr_buf@[1..7] = 0)   │  (Cache Line 1 Alignment) │
              └──────────────────┴───────────────────────────────────────┴───────────────────────────┘
```

| QWORD | Offset | `.stile` (Sovereign Micro-Tile Container) | `.stape` (Sovereign Vector Cord Container) |
| :---: | :---: | :--- | :--- |
| **Word 0** | `0x00` | `[ Magic='STIL' (1398032716):32 \| Tiles_X:16 \| Tiles_Y:16 ]` | `[ Magic='STAP' (1398030672):32 \| Cord_Count:32 ]` |
| **Words 1..7** | `0x08..0x3F` | **56 Bytes Zero-Padded L1 Alignment** (`hdr_buf@[1..7] = 0`) | **56 Bytes Zero-Padded L1 Alignment** (`hdr_buf@[1..7] = 0`) |
| **Byte 64+** | `0x40` | **Contiguous 1,024-byte (128-word) Micro-Tiles** | **Contiguous 32-byte (4-word [w0..w3]) Cord Quads** |

### The 56-Byte Zero-Pad L1 Alignment Guarantee
In `sassets/pure/stile.sinc`, `bake_emit_header!(out_buf, magic, w0_lo)` writes 64 header bytes directly at `out_buf`:
```sinc
out_buf@[0] = w0;
loop (h:7 = 1 .. 8) [
    out_buf@[h] = 0;
]
```
Zeroing Words 1..7 guarantees that payload data at Byte 64 (`ptr + 64`) begins on an exact 64-byte L1 cache-line boundary, eliminating split-line cache fetch penalties during rasterization.

---

## 3. Format 1: Sovereign Micro-Tiles (`.stile`)

A `.stile` binary is an uncompressed sequence of contiguous $16 \times 16$ pixel micro-tiles in premultiplied RGBA8888.

### 3.1 $O(1)$ Direct Memory Addressing
Because each micro-tile is permanently 1,024 bytes ($16 \times 16 \times 4\text{ bytes} = 128\text{ 64-bit words}$), tile $k$'s memory pointer is resolved via a single 1-cycle bit-shift ([`sassets/pure/stile.sinc`](../sassets/pure/stile.sinc)):

```sinc
fn stile_get_tile_ptr(stile_ptr, tile_idx) [
    tile_bytes = tile_idx << 10;
    byte_off = 64 + tile_bytes;
    tile_ptr = stile_ptr + byte_off;
    ret tile_ptr;
]
```

### 3.2 The 4-State Alpha Lattice
1. **Empty Air (`#00000000`)**: Skipped completely at 0 CPU cycles.
2. **Solid Color**: Broadcast fill via `hd_broadcast_solid!`.
3. **Opaque Texture ($\forall A = 255$)**: Streamed directly into the target framebuffer via `stile_flush_opaque!` (`slsp_beam_flush_tile!`) with **zero blend multiplications**.
4. **Translucent ($\exists A \in [1..254]$)**: Composited into tile scratch memory via `stile_composite_tile!` (`hd_composite_source_over!`) using premultiplied Source-Over blending.

### 3.3 Zero-Division Premultiplication Identity
To prevent expensive hardware `idiv` instructions during asset compilation, `bin/sagr-bake` utilizes the exact 16-bit shift-add identity ([`sassets/pure/bake_lexer.sinc`](../sassets/pure/bake_lexer.sinc)):

```sinc
fn bake_premult_ch(c_val, a_val) [
    prod = c_val * a_val;
    x = prod + 128;
    x_hi = x >> 8;
    x_sum = x + x_hi;
    c_premult = x_sum >> 8;
    ret c_premult;
]
```
Across all $65{,}536$ possible $(C, A) \in [0..255]^2$ channel pairs, this identity matches $\lfloor (C \times A + 127) / 255 \rfloor$ 100% bit-for-bit with **zero division instructions**.

---

## 4. Format 2: Sovereign Vector Tapes (`.stape`)

A `.stape` binary is a flat array of 32-byte Cord Quads (`[w0, w1, w2, w3]`) with pre-flattened monotonic quadratic Béziers and tension carry flags.

### 4.1 32-Byte Cord Quad Packing
Each cord quad matches the exact layout ingested by the Jacquard Loom:
* **Word 0**: `[op:8, effect:8, tx_lo:8, tx_hi:8, rgba:32]`
  - Bit 56: OP code (`1 = PURE_CORD`)
  - Bits 48..55: Effect flags (`1 = BAKE_EFFECT_PURE`, `2 = BAKE_EFFECT_SHUTTER`)
  - Bits 40..47: Left tile index `tx_lo` ($0..119$)
  - Bits 32..39: Right tile index `tx_hi` ($0..119$)
  - Bits 0..31: Packed 32-bit RGBA color
* **Word 1**: `(x0_q8 << 32) | y0_q8` ($Q24.8$ fixed-point coordinates)
* **Word 2**: `(x1_q8 << 32) | y1_q8` ($Q24.8$ fixed-point coordinates)
* **Word 3**: 64-bit $Y$-row punch-card bitmask (`fl_make_row_mask(ty_lo, ty_hi)`)

### 4.2 Wang Dyadic Curve Flattening
Quadratic Bézier curves (`quad: x0 y0 cx cy x1 y1 #RGBA`) are split ahead of time to dyadic depth $N = 2^k$ ($k \in [0..7]$) via Wang's theorem. All emitted cord segments are strictly monotonic in $Y$, eliminating runtime curve evaluation from the client engine.

### 4.3 Bit-49 Shutter Occlusion Reaping
When a vector cord carries `effect: shutter`, its 49th bit is set:
```sinc
sh_shut = style_w0 >> 49;
is_shutter = sh_shut & 1;
```
Client code culls occluded cords backwards via `stape_reap!` ([`sassets/pure/stape.sinc`](../sassets/pure/stape.sinc)) against the Heddle shutter mask:
```sinc
fn stape_reap!(stape_ptr, shutter_mask) [
    cords_ptr = stape_get_cords_ptr(stape_ptr);
    cord_count = stape_get_cord_count(stape_ptr);
    reaped = hd_reap_shutter!(cords_ptr, cord_count, shutter_mask);
    ret reaped;
]
```

---

## 5. The Ahead-of-Time Compiler (`bin/sagr-bake`)

The sovereign asset compiler core lives in OS-neutral SINC inside `sassets/`, paired with the Linux CLI driver (`steel/sys/driver_sassets_linux.sinc`) via `./bin/staff sassets/build.staff`:

```
sassets/
├── build.staff            # Manifest for bin/sagr-bake (links driver_sassets_linux.sinc)
├── data/
│   └── asset_defs.sinc    # BAKE_STILE_MAGIC, BAKE_KIND_*, effect constants (BAKE_STAPE_MAGIC in pegboard_defs.sinc)
├── pure/
│   ├── bake_lexer.sinc    # Pure hex, int, and style parsers; premult math
│   ├── stile.sinc         # Micro-tile helpers & shared 64-byte header emitter
│   └── stape.sinc         # Vector tape runtime helpers (shutter reap & Loom weave)
└── sys/
    ├── bake_ppm.sinc      # Netpbm P6 RAM -> .stile core (bake_ppm_core!)
    ├── bake_tape.sinc     # ASCII .tape -> .stape core with Wang Quads (bake_tape_core!)
    ├── bake_tile.sinc     # ASCII .tile -> .stile RGBA core (bake_tile_core!)
    └── entry.sinc         # In-memory bake_core! SPINE dispatcher
```

### 5.1 CLI Usage Guide

```bash
# Compile ASCII raster tile grid to .stile
./bin/sagr-bake hero.tile assets/hero.stile

# Compile Netpbm P6 texture to .stile
./bin/sagr-bake texture.ppm assets/texture.stile

# Compile ASCII vector tape to .stape
./bin/sagr-bake ui_elements.tape assets/ui_elements.stape
```

### 5.2 Human-Readable Source Formats

#### ASCII Raster Tile (`.tile`)
```tile
# 16x16 Character Sprite
size: 16 16
pal: . #00000000
pal: # #FF0000FF
pal: + #FFFFFFFF
row: ................
row: ....########....
row: ..##++++++++##..
...
```

#### ASCII Vector Tape (`.tape`)
```tape
# Vector UI Layout
rect: 0 0 200 32 #202020FF shutter
line: 4 16 150 16 #FFA0A080 pure
quad: 20 50 50 10 80 50 #00FF00FF pure
```
