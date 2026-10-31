# Chapter 6: Typography & Simple MSDF Engine (.sfont)

Typography rendering in SAGR uses an integer-only **Multi-Channel Signed Distance Field (MSDF)** engine ([`sagr/pure/msdf.sinc`](../sagr/pure/msdf.sinc)) paired with the binary **`.sfont`** format.

---

## 1. Why MSDF? (Sharp Corners at Infinite Resolution)

Standard monochrome Signed Distance Fields (SDF) store a single distance value to the nearest edge. At sharp $90^\circ$ corners or serifs, standard SDF rounds off the corner.

**MSDF** solves this by storing three independent distance channels ($R, G, B$):
* Edge channels are segmented so that intersecting contours are assigned to different color channels.
* The original vector contour is reconstructed at runtime using a **Median-of-Three Filter**:

$$D_{\text{true}} = \text{median}(R, G, B) = \max(\min(R, G), \min(\max(R, G), B))$$

Because the median operation preserves the intersection of multiple distance fields, sharp corners and serifs remain crisp across arbitrary display scaling.

---

## 2. The `.sfont` Binary Format

A `.sfont` file is an uncompressed binary asset containing a 64-byte (8-word) header, an array of 32-byte glyph metric quads, and a raw RGB MSDF atlas:

| Word | Byte Offset | Field | Description |
| :---: | :---: | :--- | :--- |
| **0** | `0x00` | `SFONT_MAGIC` | `1414418259` (`'SFNT'`) |
| **1** | `0x08` | Packed Dimensions | `[ AtlasWidth:16 \| AtlasHeight:16 ]` |
| **2** | `0x10` | Packed Font Metrics | `[ Ascent_Q8:16 \| Descent_Q8:16 ]` |
| **3** | `0x18` | Glyph Count | Total packed glyph records |
| **4** | `0x20` | Atlas Data Offset | Word/byte offset to raw atlas texels |
| **5..7**| `0x28..0x38` | Reserved | Zero-padded header words |

### The 32-Byte Glyph Metric Quad
Each glyph occupies 4 64-bit words:
* **Word 0**: `[ UnicodeCodepoint:32 | Advance_Q8:32 ]`
* **Word 1**: `[ AtlasU0:16 | AtlasV0:16 | AtlasU1:16 | AtlasV1:16 ]` (Integer texel coordinates)
* **Word 2**: `[ PlaneLeft:16 | PlaneBottom:16 | PlaneRight:16 | PlaneTop:16 ]` (Q8.8 metric box)
* **Word 3**: Reserved (0)

Loading a `.sfont` requires no parsing or decompression: map the file into memory and access glyph records directly by index.

---

## 3. Branchless Median Reconstruction in SINC

The 3-channel median reconstruction executes branchlessly ([`sagr/pure/msdf.sinc`](../sagr/pure/msdf.sinc)):

```sinc
fn msdf_median(r, g, b) [
    min_rg = r;
    if (g < r) [
        min_rg = g;
    ]
    max_rg = r;
    if (g > r) [
        max_rg = g;
    ]
    min_max_b = max_rg;
    if (b < max_rg) [
        min_max_b = b;
    ]
    med = min_rg;
    if (min_max_b > min_rg) [
        med = min_max_b;
    ]
    ret med;
]
```

---

## 4. Integer Bilinear Texture Sampler

Sampling distance fields at arbitrary sub-pixel locations uses an integer fixed-point $Q16.16$ bilinear filter:
* `fu = (u_q16 >> 8) & 255` (8-bit horizontal sub-pixel weight)
* `fv = (v_q16 >> 8) & 255` (8-bit vertical sub-pixel weight)
* Weights are blended using 64-bit products and `>> 8` shifts, producing smooth anti-aliasing without floating-point units.
