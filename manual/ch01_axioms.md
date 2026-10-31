# Chapter 1: Architectural Axioms & Simple Contracts

The **Simple Analytical Grid Renderer (SAGR)** is designed around a single premise: **2D vector graphics can be computed with 100% mathematical determinism, zero floating-point operations, and zero dynamic memory allocations directly in CPU L1 cache.**

---

## 1. The Zero-Float Invariant

Floating-point coordinates (`float`, `double`) introduce three issues in deterministic rendering pipelines:
1. **Non-Determinism**: Floating-point rounding varies across x86-64 microarchitectures (FMA vs non-FMA, denormals, compiler optimizations), making bit-perfect golden image verification impossible across machines.
2. **SIMD Starvation**: 32-bit floats reduce 512-bit AVX-512 register lane capacity to 16 elements, whereas 8-bit integer operations achieve 64 simultaneous lanes.
3. **Conversion Overhead**: Converting back and forth between float coordinates and integer framebuffers burns CPU pipeline stages with 4-cycle truncation instructions (`vcvttps2dq`).

### SAGR's Fixed-Point Number System

SAGR uses integer math only. All spatial calculations use explicit fixed-point integer coordinate representations:

| Domain | Format | Fractional Bits | Unit Scale | Range / Representation |
| :--- | :--- | :---: | :---: | :--- |
| **World Space** | $Q24.8$ | 8 | $256 = 1.0\text{ px}$ | Full screen coordinates ($0.0$ to $16{,}777{,}215.0\text{ px}$) |
| **Tile-Local Space** | $Q8.8$ | 8 | $256 = 1.0\text{ px}$ | Micro-tile coordinates ($0$ to $4096 = 16.0\text{ px}$) |
| **Sub-Pixel Area Flux** | $Q8.8$ | 8 | $256 = 1.0\text{ (100\%)}$ | Trapezoid coverage integrals $\in [0..256]$ |
| **Color Channels** | $U8$ | 0 | $1$ | Byte color values $[0..255]$ ($RGBA8888$) |

* **Sub-Pixel Precision**: With 8 fractional bits ($1/256^{\text{th}}$ of a pixel), rounding errors are smaller than $0.0039\text{ pixels}$—well below the threshold of human visual perception on high-DPI displays.

---

## 2. The $16 \times 16$ Micro-Tile L1 Cache Contract

SAGR does not maintain monolithic full-screen rasterization state. The viewport is partitioned into an immutable lattice of **$16 \times 16$ pixel micro-tiles**:

```
      ◄─────────────────── 1920 Pixels (120 Tiles) ───────────────────►
   ▲  ┌──────────┬──────────┬──────────┬──────────┬ ─── ┬──────────┐
   │  │ Tile 0,0 │ Tile 1,0 │ Tile 2,0 │ Tile 3,0 │     │Tile 119,0│  Row 0
   │  ├──────────┼──────────┼──────────┼──────────┼ ─── ┼──────────┤
   │  │ Tile 0,1 │ Tile 1,1 │ Tile 2,1 │ Tile 3,1 │     │Tile 119,1│  Row 1
1088  ├──────────┼──────────┼──────────┼──────────┼ ─── ┼──────────┤
 px   │ Tile 0,2 │ Tile 1,2 │ Tile 2,2 │ Tile 3,2 │     │Tile 119,2│  Row 2
(68   ├──────────┼──────────┼──────────┼──────────┼ ─── ┼──────────┤
Tiles)│   ...    │   ...    │   ...    │   ...    │     │   ...    │
   │  ├──────────┼──────────┼──────────┼──────────┼ ─── ┼──────────┤
   ▼  │Tile 0,67 │Tile 1,67 │Tile 2,67 │Tile 3,67 │     │Tile 119,67
      └──────────┴──────────┴──────────┴──────────┴ ─── ┴──────────┘
```

### Memory Footprint of a Micro-Tile
* **Pixels**: $16 \times 16 = 256\text{ pixels}$.
* **RGBA8 TrueColor**: $256 \times 4\text{ bytes} = 1{,}024\text{ bytes} = 128\text{ 64-bit words}$.
* **AVX-512 Register Fit**: Exactly 16 ZMM registers (`zmm0`–`zmm15`, 64 bytes each).
* **L1 Cache Residency**: 
  - Warp Scratch: $272 \times 8\text{ bytes} = 2{,}176\text{ bytes}$
  - Coverage Scratch: $256 \times 8\text{ bytes} = 2{,}048\text{ bytes}$
  - Output Tile Words: $128 \times 8\text{ bytes} = 1{,}024\text{ bytes}$
  - **Per-Tile Working State**: **$5{,}248\text{ bytes} \approx 5.1\text{ KB}$**
  - Shared Screen Dirty Mask: $128 \times 8\text{ bytes} = 1{,}024\text{ bytes}$
  - **Total Working Footprint**: **$6{,}272\text{ bytes} \approx 6.1\text{ KB}$**.

Because modern x86-64 CPUs feature $32\text{ KB}$ to $48\text{ KB}$ of L1 Data Cache per core, the entire rasterization loop of every tile executes inside CPU L1 cache with zero DRAM roundtrips.

---

## 3. Coordinate Space Mappings

Transforming a global coordinate $(X, Y)$ into a tile coordinate:

```sinc
// Convert Q24.8 global coordinate to Tile Index
tx = x_q8 >> 12; // (X / 256) / 16 = X >> 12
ty = y_q8 >> 12; // (Y / 256) / 16 = Y >> 12

// Convert to Tile-Local Coordinate in Q8.8 [0..4096]
local_x = x_q8 & 4095;
local_y = y_q8 & 4095;
```

---

## 4. The 100% Deterministic Guarantee

Because every arithmetic operation is integer addition, subtraction, bit-shift, and bitwise logic:
* Output pixel values are **bit-for-bit identical** across all Intel, AMD, or emulator platforms.
* Every release of SAGR is audited against the **12-Scene Golden Oracle** ([`sagr/sys/verify_sagr.sinc`](../sagr/sys/verify_sagr.sinc)), calculating 64-bit FNV-1a hashes of the rendered pixels to verify zero bit-drift.
