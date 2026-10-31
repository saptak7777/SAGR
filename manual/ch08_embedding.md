# Chapter 8: API Reference & Embedding Guide

SAGR is straightforward to embed in operating system kernels, UEFI bootloaders, game engines, and desktop application compositors.

---

## 1. Core API Catalog

### Surface & Framebuffer (`sagr/sys/slsp.sinc`)

* `slsp_create!(arena, width, height, format)`
  Allocates a 32-byte surface descriptor, linear framebuffer, and 128-word dirty tile bitmask.
* `slsp_clear_dirty!(mask_ptr)`
  Zeroes all 128 words of the dirty bitmask.
* `slsp_stamp_tile!(mask_ptr, tx, ty)`
  Sets the dirty bit for micro-tile $(T_x, T_y)$.
* `slsp_stamp_box!(mask_ptr, x0_q24, y0_q24, x1_q24, y1_q24)`
  Calculates all micro-tiles touched by a bounding box and sets their dirty bits.
* `slsp_beam_flush_tile!(fb_base, tx, ty, stride, tile_words~)`
  Streams a 128-word ($16 \times 16$) TrueColor RGBA tile into the destination framebuffer.

---

### Jacquard Loom Rasterizer (`sagr/pure/loom.sinc`)

* `lm_pluck_cord!(warp_scratch, tx, ty, x0, y0, x1, y1)`
  Slices an edge cord into sub-pixel trapezoid area fluxes and accumulates into warp columns.
* `lm_weft_row!(warp_scratch, row)`
  Executes the 4-cycle Hillis-Steele horizontal prefix sum across row columns ($0..15$).
* `lm_resolve_nonzero(w)`
  Resolves signed cumulative area using the Non-Zero winding rule ($\min(|w|, 256)$).
* `lm_resolve_evenodd(w)`
  Resolves signed cumulative area using the Even-Odd winding rule ($w \& 511$ folded).
* `lm_weave_tile!(tape, tape_len, tx, ty, rule, warp_scratch, out_coverage)`
  Weaves all active cords for micro-tile $(T_x, T_y)$ into 256 sub-pixel coverage values.
* `lm_weave_tile_backdrop!(tape, tape_len, tx, ty, rule, in_bd, out_bd, warp_scratch, out_coverage)`
  Weaves micro-tile with horizontal backdrop tension propagation for multi-tile spanning shapes.
* `lm_weave_tile_row!(tape, tape_len, ty, nx, winding_rule, warp_scratch, tile_coverage, backdrop_buf)`
  Weaves an entire horizontal row of tiles with backdrop tension propagation.
* `lm_shade_tile_rgba!(cov_scratch, fg_rgba, bg_rgba, tile_words)`
  Blends foreground and background colors using the 256-level sub-pixel coverage array.
* `lm_shade_pixel(bg_r, bg_g, bg_b, bg_a, diff_r, diff_g, diff_b, diff_a, alpha)`
  Computes 8-bit channel linear blend for an individual pixel.

---

### Heddle Compositor & Shutter Reaper (`sagr/pure/heddle.sinc`)

* `hd_stamp_shutter_interior!(mask_ptr, tx0, ty0, tx1, ty1)`
  Marks the interior micro-tiles of an opaque window in the shutter bitmask.
* `hd_is_occluded(mask_ptr, tx0, ty0, tx1, ty1)`
  Queries whether a rectangular region is 100% covered by opaque foreground windows.
* `hd_reap_shutter!(tape, tape_len, mask_ptr)`
  Scans the cord tape backwards and mutates occluded draw calls into zero-cost NOPs.
* `hd_is_solid_interior(active_cords, backdrop_buf)`
  Checks if a tile has zero active cords and full 256 backdrop tension.
* `hd_broadcast_solid!(tile_words, solid_rgba)`
  Fills a $16 \times 16$ tile with a solid color in $128$ word writes, bypassing Loom rasterization.
* `hd_blend_pixel(src_px, dst_px)`
  Blends two packed 32-bit RGBA pixels using integer math with saturated alpha.
* `hd_composite_source_over!(dst_tile_words, src_tile_words)`
  Composites a 128-word source tile over a destination tile using 64-bit word operations.

---

### Pure Math & Bit Manipulation (`sagr/pure/bitops.sinc`)

* `bo_abs(v)`
  Computes integer absolute value.
* `bo_octagonal_norm(dx, dy)`
  Approximates Euclidean 2D distance ($\max + \frac{1}{2}\min$) in 3 ALU cycles.
* `bo_stamp_tile!(mask_ptr, tx, ty)`
  Sets the dirty bit for micro-tile $(T_x, T_y)$ in the 128-word bitmask.
* `bo_test_tile(mask_ptr, tx, ty)`
  Tests whether micro-tile $(T_x, T_y)$ is marked dirty in the 128-word bitmask.

---

## 2. Embedding in Bare-Metal UEFI & OS Kernels

Because SAGR has **zero OS syscalls** in its rendering pipeline, it can run directly in a bootloader or kernel:

> **Note**: In these examples, `sagr_render_*` (`sagr_render_splash`, `sagr_render_ui`, `sagr_render_frame`) represents your compiled SINC entry function that accepts `(fb_ptr, width, height, stride)`.

```c
// UEFI C Driver / Bootloader Stub
EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = ...;
uint32_t *framebuffer = (uint32_t*)gop->Mode->FrameBufferBase;
uint32_t width  = gop->Mode->Info->HorizontalResolution;
uint32_t height = gop->Mode->Info->VerticalResolution;
uint32_t stride = gop->Mode->Info->PixelsPerScanLine * 4;

// Pass pointer straight to SAGR:
sagr_render_splash(framebuffer, width, height, stride);
```

---

## 3. Embedding on Windows x64

SAGR runs natively on Windows PE x64. The only requirement is allocating memory via Win32:

```c
// Windows DIB Section
BITMAPINFO bmi = {0};
bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
bmi.bmiHeader.biWidth = 1920;
bmi.bmiHeader.biHeight = -1080; // Top-down
bmi.bmiHeader.biPlanes = 1;
bmi.bmiHeader.biBitCount = 32;
bmi.bmiHeader.biCompression = BI_RGB;

void *fb_bits;
HBITMAP hbm = CreateDIBSection(hdc, &bmi, DIB_RGB_COLORS, &fb_bits, NULL, 0);

// SAGR weaves directly into fb_bits
sagr_render_ui(fb_bits, 1920, 1080, 1920 * 4);

// Blit to screen
BitBlt(hdc, 0, 0, 1920, 1080, mem_dc, 0, 0, SRCCOPY);
```

---

## 4. Embedding on Linux (Wayland & X11)

On modern Linux desktops, pass an anonymous shared-memory buffer (`memfd_create` + `mmap`):

```c
// Wayland wl_shm buffer creation
int fd = memfd_create("sagr_buffer", MFD_CLOEXEC);
ftruncate(fd, 1920 * 1080 * 4);
uint32_t *shm_ptr = mmap(NULL, 1920 * 1080 * 4, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);

// Hand shm_ptr to SAGR
sagr_render_frame(shm_ptr, 1920, 1080, 1920 * 4);

// Present to Wayland compositor
wl_surface_attach(surface, wl_buffer, 0, 0);
wl_surface_damage_buffer(surface, 0, 0, 1920, 1080);
wl_surface_commit(surface);
```
