# SAGR Sovereign Image Viewer (`examples/image_viewer`)

A pure, sovereign raster image viewer demonstrating zero-decoder asset rendering in SAGR.

---

## Architectural Principles

1. **Strictly Pre-Baked `.stile` Input:** The runtime engine contains **zero foreign format decoders** (no PNG, JPEG, or DEFLATE decompressor in silicon). The image is pre-compiled into a `.stile` micro-tile binary stream ahead of time.
2. **L1 Cache Alignment:** Every 16×16 tile is exactly 128 64-bit words (1,024 bytes), matching hardware cache lines with $O(1)$ constant indexing.
3. **Silicon Compositing:** Translucent micro-tiles are composited directly into tile scratch memory using `stile_composite_tile!` (`hd_composite_source_over!`), then flushed to framebuffer memory using `slsp_beam_flush_tile!`.

---

## How to Run

### Step 1: Bake Your Image Ahead of Time (Offline)

Compile your source image into a sovereign `.stile` micro-tile binary via the native SINC baker:

```bash
# Convert Netpbm P6 image to sovereign .stile:
./bin/sagr-bake input.ppm assets/image.stile

# Or convert human-readable ASCII .tile to sovereign .stile:
./bin/sagr-bake assets/sample.tile assets/sample.stile
```

### Step 2: Render with the Sovereign Image Viewer (Runtime)

Pass a `.stile` asset directly to the viewer (or run with no arguments to use the built-in sample):

```bash
# Render default sample asset (auto-bakes examples/image_viewer/assets/sample.tile):
./examples/image_viewer/run.sh

# Or render a custom pre-baked .stile:
./examples/image_viewer/run.sh assets/image.stile
```

The script compiles the pure SINC viewer into `scratch/image_viewer_bin` and outputs:
- `scratch/image_view.ppm` (Uncompressed raw framebuffer dump)
- `scratch/image_view.png` (Convenience copy for desktop window managers, if ffmpeg is installed)
