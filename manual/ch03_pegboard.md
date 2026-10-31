# Chapter 3: Pegboard Vector Tape Protocol

The **Pegboard Tape** is SAGR’s fundamental geometric intermediate representation. All high-level vector shapes—rectangles, polygons, quadratic Béziers, and text glyphs—are flattened and packed into a single, contiguous array of **32-byte 4-Word Cord Quads**.

---

## 1. The 32-Byte Cord Quad Specification

Every geometric primitive on the tape occupies exactly 4 64-bit words:

```
  Bit 63       56 55      48 47             32 31                             0
Word 0: [ Opcode:8 | Effect:8 |  Tx_Span:16   |          RGBA8:32             ]
Word 1: [           X0:32 (Q24.8)             |          Y0:32 (Q24.8)        ]
Word 2: [           X1:32 (Q24.8)             |          Y1:32 (Q24.8)        ]
Word 3: [                     Tile Y-Row Mask:64 (Punch-Card)                 ]
```

### Word Layout Details ([sagr/data/pegboard_defs.sinc](../sagr/data/pegboard_defs.sinc)):

1. **Word 0: Command & Appearance**
   * **Opcode (Bits 56..63)**: 
     - `1 = PB_SEG_LINE` (Linear segment)
     - `2 = PB_SEG_QUAD` (Monotonic quadratic Bézier segment)
   * **Effect (Bits 48..55)**:
     - `1 = EFFECT_PURE` (Standard alpha-blended vector geometry)
     - `2 = EFFECT_SHUTTER` (Opaque occlusion window for backward dead-code culling)
   * **Tx_Span (Bits 32..47)**:
     - Upper byte: `Tx_Min` (leftmost micro-tile column touched)
     - Lower byte: `Tx_Max` (rightmost micro-tile column touched)
   * **RGBA (Bits 0..31)**: 32-bit packed TrueColor byte values (`0xAABBGGRR`).

2. **Word 1 & Word 2: Spatial Coordinates (Q24.8)**
   * Packed 32-bit integers representing start $(X_0, Y_0)$ and end $(X_1, Y_1)$ in global fixed-point pixel space.

3. **Word 3: The Y-Row Punch-Card Bitmask (64 Bits)**
   * Bit $i$ indicates whether this cord intersects micro-tile row $i$.
   * **Instant Tile Rejection**: When testing if a cord touches micro-tile row $T_y$, SAGR evaluates:
     ```sinc
     has_row = (w3 >> ty) & 1;
     if (has_row == 0) [ /* Skip cord in 1 cycle */ ]
     ```

---

## 2. Ingestion & Clipping (`pb_clip_line!`)

Before a vector path is accepted onto the tape, [`sagr/pure/pegboard.sinc`](../sagr/pure/pegboard.sinc) clamps coordinates to screen bounds:

```sinc
// Clamping to screen boundaries in Q24.8
x0 = pb_clamp_x(in_x0);
y0 = pb_clamp_y(in_y0);
x1 = pb_clamp_x(in_x1);
y1 = pb_clamp_y(in_y1);
```

### Invariant Guarantee
Because the Pegboard clips all coordinates upfront, **the downstream Jacquard Loom never performs a single viewport bounds check.** This eliminates branches from the hot rasterization loop.
