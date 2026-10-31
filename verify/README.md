# SAGR Golden Oracle Baseline Verification

This directory contains the canonical verification baselines for the **12-Scene Golden Oracle** of the Simple Analytical Grid Renderer (SAGR).

---

## Purpose

The Golden Oracle protects SAGR against silent algorithmic drift, compiler regressions, and memory corruption.

* **100% Determinism**: Every scene evaluates a core geometric, raster, compositing, or typographic subsystem.
* **FNV-1a 64-Bit Hashing**: Rendered tiles and state arrays are hashed using 64-bit FNV-1a.
* **Independent Baseline**: Any future code changes that alter even a single sub-pixel coverage value will cause a hash mismatch against [golden_baseline.txt](golden_baseline.txt).

---

## The 12 Canonical Scenes

| Scene | Subsystem Tested | Baseline Hash | Description |
| :---: | :--- | :---: | :--- |
| **0** | **Hairlines** | `1817640690661663005` | Sub-pixel horizontal and vertical cords (0.5px line at y=8px). |
| **1** | **Bézier Curve** | `-3344515123818599131` | Monotonic quadratic curve flattened via Wang's dyadic formula. |
| **2** | **Star Winding** | `6152551145473625421` | Closed 5-pointed star validating Non-Zero area accumulation. |
| **3** | **Affine Transform**| `-2543379141462635431` | Fixed-point 2x2 affine transformation (scale 2x, translate 500). |
| **4** | **Extrema Split** | `7266194098263789792` | Quadratic curve split at first-derivative roots into monotonic cords. |
| **5** | **Viewport Clipper**| `9179411575584190984` | Exact canvas boundary clipping rejecting out-of-bounds coords. |
| **6** | **Backdrop Tension**| `384559739574062237` | Multi-tile horizontal backdrop tension propagation across tiles. |
| **7** | **Solid Interior** | `-4284900774398857947` | Full-tile constant-color fill bypass (hd_broadcast_solid). |
| **8** | **Shutter Reaper** | `-4863058030181509469` | Backward NOP mutation of 49 occluded overlapping windows. |
| **9** | **Compositor** | `6693579788332997797` | 64-lane SIMD source-over alpha blending (50% red over white). |
| **10** | **MSDF Typography** | `-3921325195339606363` | 3-channel median reconstruction on 16x16 glyph distance field. |
| **11** | **Blinking Cursor** | `-8216200288567235291` | Minimal 2-tile dirty bitmask footprint update (< 0.05W thermal). |

---

## Running Verification

To run standalone baseline verification:
```bash
./verify/verify.sh
```

Or execute the complete test suite:
```bash
./tests/run_tests.sh
```
