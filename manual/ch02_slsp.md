# Chapter 2: SINC Linear Surface Protocol (SLSP)

The **SINC Linear Surface Protocol (SLSP)** defines the low-level memory layout, surface metadata, and beam-flush operations between SAGR and display hardware.

---

## 1. The 32-Byte Surface Descriptor

Every rendering target in SAGR is represented by a compact, 32-byte linear descriptor packed into 4 64-bit words:

```
Offset   Field                 Word Encoding
────────────────────────────────────────────────────────────────────────────
0x00     SLSP_WORD_DIMS        [ Height:32 | Width:32 ]
0x08     SLSP_WORD_STRIDE_FMT  [ Format:32 | StrideBytes:32 ]
0x10     SLSP_WORD_FB_PTR      Pointer to raw linear framebuffer memory
0x18     SLSP_WORD_MASK_PTR    Pointer to 128-word (1,024-byte) dirty bitmask
────────────────────────────────────────────────────────────────────────────
```

### In SINC Code ([sagr/data/surface.sinc](../sagr/data/surface.sinc)):
```sinc
const SLSP_WORD_DIMS       = 0;
const SLSP_WORD_STRIDE_FMT = 1;
const SLSP_WORD_FB_PTR     = 2;
const SLSP_WORD_MASK_PTR   = 3;
const SLSP_DESC_WORDS      = 4;
```

---

## 2. Surface Creation & Initialization

Surfaces are allocated from a linear arena via [`slsp_create!`](../sagr/sys/slsp.sinc):

```sinc
// Allocate 1080p (1920x1080) Surface with RGBA8 format
surface = slsp_create!(arena, 1920, 1080, 0);

fb_ptr   = surface.SLSP_WORD_FB_PTR;
mask_ptr = surface.SLSP_WORD_MASK_PTR;
```

* **Zero Allocation During Frames**: The framebuffer and dirty mask pointers remain fixed for the lifetime of the surface.

---

## 3. The 128-Word Dirty Tile Bitmask

SAGR eliminates full-frame re-rendering by tracking modified regions at micro-tile granularity.

* **Resolution**: 1080p requires $120 \times 68 = 8{,}160\text{ tiles}$.
* **Bitmask Size**: Exactly **128 64-bit words** ($128 \times 64 = 8{,}192\text{ bits} = 1{,}024\text{ bytes}$).
* **Hardware Acceleration**: SAGR scans modified tiles using x86-64 BMI1 hardware instructions:
  - `tzcnt` (`ctz64`): Finds the next active dirty tile index in 1 cycle.
  - `blsr` (`blsr64`): Clears the lowest set bit in 1 cycle.

### Scanning Dirty Tiles ([sagr/pure/bitops.sinc](../sagr/pure/bitops.sinc)):
```sinc
loop (w_idx:128 = 0 .. 128) [
    w_val = mask_ptr@[w_idx];
    if (w_val != 0) [
        loop (step:64 = 0 .. 64) [
            if (w_val != 0) [
                b_idx = ctz64(w_val);
                tile_idx = (w_idx << 6) + b_idx;
                ty = tile_idx / 120;
                tx = tile_idx - (ty * 120);

                // Weave, shade, and flush only this modified tile:
                lm_weave_tile!(tape, total_cords, tx, ty, 0, warp_scratch, cov_scratch);
                lm_shade_tile_rgba!(cov_scratch, fg, bg, tile_words);
                slsp_beam_flush_tile!(fb_ptr, tx, ty, stride, tile_words~);

                w_val = blsr64(w_val); // Clear processed bit
            ]
        ]
    ]
]
```

---

## 4. The Beam Flush (`slsp_beam_flush_tile!`)

Once a $16 \times 16$ tile is rasterized in L1 scratch memory, [`slsp_beam_flush_tile!`](../sagr/sys/slsp.sinc) transfers the $128$ 64-bit words ($1{,}024$ bytes) directly into the destination linear framebuffer:


```sinc
fn slsp_beam_flush_tile!(fb_base, tx, ty, stride, tile_words~) [
    y_pixel_off = ty * 16;
    y_byte_off = y_pixel_off * stride;
    x_byte_off = tx * 64; // 16 pixels * 4 bytes/pixel
    dest_base = fb_base + y_byte_off + x_byte_off;

    loop (row:16 = 0 .. 16) [
        row_byte_off = row * stride;
        row_dest = dest_base + row_byte_off;
        tile_row_off = row * 8; // 8 words per 16-pixel row

        loop (col:8 = 0 .. 8) [
            word_idx = tile_row_off + col;
            val = tile_words@[word_idx];
            row_dest@[col] = val; // 64-bit word write
        ]
    ]
    ret 0;
]
```

* **Linearity Contract (`~`)**: The `tile_words~` parameter enforces the SINC linearity contract, guaranteeing zero memory aliasing and allowing the compiler to emit streaming stores without stack reloads.
