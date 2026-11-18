# Chapter 6: Typography & Simple MSDF Engine (TRG & MSDF)

Typography rendering in SAGR uses an integer-only **Multi-Channel Signed Distance Field (MSDF)** engine ([`sagr/pure/msdf.sinc`](../sagr/pure/msdf.sinc)) paired with the sovereign binary **TRG (Typed Relative Grid)** protocol.

---

## 1. Why MSDF? (Sharp Corners at Infinite Resolution)

Standard monochrome Signed Distance Fields (SDF) store a single distance value to the nearest edge. At sharp $90^\circ$ corners or serifs, standard SDF rounds off the corner.

**MSDF** solves this by storing three independent distance channels ($R, G, B$):
* Edge channels are segmented so that intersecting contours are assigned to different color channels.
* The original vector contour is reconstructed at runtime using a **Median-of-Three Filter**:

$$D_{\text{true}} = \text{median}(R, G, B) = \max(\min(R, G), \min(\max(R, G), B))$$

Because the median operation preserves the intersection of multiple distance fields, sharp corners and serifs remain crisp across arbitrary display scaling.

---

## 2. The 1-Byte Fixed-Width TRG Protocol (Replacing Unicode)

Variable-length encodings (UTF-8, UTF-16) and complex dynamic shaping engines (FreeType, HarfBuzz) introduce non-deterministic execution paths, memory allocations, and branching overhead.

SAGR replaces runtime text shaping with **TRG (Typed Relative Grid)**—a sovereign 1-byte fixed-width ingestion stream that decodes glyphs directly using branchless ALU carry arithmetic.

### 2.1 The TRG Stream Header (64 Bytes)
Every TRG text stream begins with an 8-QWORD (64-byte) header matching Cache Line 0:

| Byte Offset | Field | Description |
| :---: | :--- | :--- |
| `0x00..0x03` | `Length:32` | Total glyph count in the text run |
| `0x04` | `Script_A:8` | Primary script base coordinate (e.g. Latin/English) |
| `0x05` | `Script_B:8` | Secondary script base coordinate (e.g. Indic / regional) |
| `0x07` | `Magic:8` | `TRG_MAGIC_BYTE = 84` (`'T'`) |
| `0x08..0x3F` | `Reserved` | Zero-padded L1 cache-line alignment (56 bytes) |
| `0x40+` | **Payload** | Contiguous 1-byte fixed-width TRG glyph byte stream (`TRG_PAYLOAD_OFFSET = 64`) |

### 2.2 The 4-Line Branchless ALU Decoder (`trg_decode_1b`)
Instead of searching multi-megabyte unicode character lookup tables, each byte is resolved directly to atlas glyph coordinates in 4 ALU cycles without branching ([`sagr/pure/msdf.sinc`](../sagr/pure/msdf.sinc)):

```sinc
fn trg_decode_1b(raw_byte~, script_a, delta_ab) [
    b_hi = raw_byte >> 7;
    plane_mask = 0 - b_hi;
    masked_delta = delta_ab & plane_mask;
    lang_base = script_a + masked_delta;
    ap_low = raw_byte & TRG_MASK_APERTURE;
    ap_carry = ap_low + TRG_CARRY_ADD;
    carry_bit = ap_carry >> 7;
    is_lang = carry_bit - 1;
    lang_offset = lang_base & is_lang;
    coord = raw_byte + lang_offset;
    ret coord;
]
```

### 2.3 Single-Pass Line Layout (`msdf_layout_trg_line!`)
The client layout engine decodes an entire line of text into a stream of 4-word metric records (`[coord, x_q8, y_q8, advance_q8]`) in a single linear pass at 60+ FPS:

```sinc
fn msdf_layout_trg_line!(trg_buf, start_x_q8, start_y_q8, scale_q8, out_positions, max_glyphs) [
    magic = trg_buf@[7 * 1];
    if (magic != TRG_MAGIC_BYTE) [
        ret 0;
    ]
    raw_len = trg_buf@[0];
    length = raw_len & 4294967295;
    run_len = lm_min(length, max_glyphs);
...
```

---

## 3. Branchless Median Reconstruction in SINC

The 3-channel median reconstruction executes branchlessly using hardware minimum and maximum operations ([`sagr/pure/msdf.sinc`](../sagr/pure/msdf.sinc)):

```sinc
fn msdf_median(r, g, b) [
    min_rg = lm_min(r, g);
    max_rg = lm_max(r, g);
    min_max_b = lm_min(b, max_rg);
    med = lm_max(min_rg, min_max_b);
    ret med;
]
```

---

## 4. Integer Bilinear Texture Sampler

Sampling distance fields at arbitrary sub-pixel locations uses an integer fixed-point $Q16.16$ bilinear filter:
* `fu = (u_q16 >> 8) & 255` (8-bit horizontal sub-pixel weight)
* `fv = (v_q16 >> 8) & 255` (8-bit vertical sub-pixel weight)
* Weights are blended using 64-bit products and `>> 8` shifts, producing smooth anti-aliased font contours without floating-point units or SIMD register starvation.
