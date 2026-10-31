# Chapter 5: The Jacquard Loom Rasterizer (Warp & Weft)

The **Jacquard Silicon Loom** ([`sagr/pure/loom.sinc`](../sagr/pure/loom.sinc)) is the rasterization core of SAGR.

Traditional software renderers sort edge intersections per scanline ($O(E \log E)$).

SAGR uses commutative area accumulation:

Because addition is commutative ($A + B = B + A$), edge cords can pluck the vertical grid lines in **any arbitrary order**. The rasterizer integrates 2D coverage using a 4-cycle branchless parallel prefix sum.

---

## 1. Stroke 1: The Warp Pluck Gate (`lm_pluck_cord!`)

A $16 \times 16$ micro-tile contains 16 horizontal pixel rows. When an edge cord intersects a tile, [`lm_pluck_cord!`](../sagr/pure/loom.sinc) slices the cord into individual row intersections.

```
       Column 0    Column 1    Column 2           Column 15
Row 0: ──┬───────────┬───────────┬───────── ... ────┬────────► Warp Thread 0
Row 1: ──┼───────────┼───────────┼───────── ... ────┼────────► Warp Thread 1
Row 2: ──┼───────╲───┼───────────┼───────── ... ────┼────────► Warp Thread 2
                 ▲
          Edge Cord Pluck (Adds Signed Area Delta: ΔA0, ΔA1)
```

For each row, the line segment between $(x_a, y_a)$ and $(x_b, y_b)$ forms a trapezoid:
* $\Delta y = y_b - y_a$ (Height of slice)
* Sub-pixel horizontal displacement contributes signed area flux into the columns.
* Area deltas are deposited directly into `warp_scratch[row * 16 + col]`.

---

## 2. Stroke 2: The Weft Shuttle (`lm_weft_row!`)

Once all cords have plucked the warp threads, the **Weft Shuttle** integrates the area fluxes horizontally across each row using a **4-Cycle Hillis-Steele Parallel Prefix Sum**:

```sinc
fn lm_weft_row!(warp_scratch, row) [
    base = row * 16;
    // Step 1: Shift +1 (col = 15 down to 1)
    loop (k1:15 = 0 .. 15) [
        col1 = 15 - k1;
        prev1 = col1 - 1;
        i_curr1 = base + col1;
        i_prev1 = base + prev1;
        c1 = warp_scratch@[i_curr1];
        p1 = warp_scratch@[i_prev1];
        warp_scratch@[i_curr1] = c1 + p1;
    ]
    // Step 2: Shift +2 (col = 15 down to 2)
    loop (k2:14 = 0 .. 14) [
        col2 = 15 - k2;
        prev2 = col2 - 2;
        i_curr2 = base + col2;
        i_prev2 = base + prev2;
        c2 = warp_scratch@[i_curr2];
        p2 = warp_scratch@[i_prev2];
        warp_scratch@[i_curr2] = c2 + p2;
    ]
    // Step 3: Shift +4 (col = 15 down to 4)
    loop (k3:12 = 0 .. 12) [
        col3 = 15 - k3;
        prev3 = col3 - 4;
        i_curr3 = base + col3;
        i_prev3 = base + prev3;
        c3 = warp_scratch@[i_curr3];
        p3 = warp_scratch@[i_prev3];
        warp_scratch@[i_curr3] = c3 + p3;
    ]
    // Step 4: Shift +8 (col = 15 down to 8)
    loop (k4:8 = 0 .. 8) [
        col4 = 15 - k4;
        prev4 = col4 - 8;
        i_curr4 = base + col4;
        i_prev4 = base + prev4;
        c4 = warp_scratch@[i_curr4];
        p4 = warp_scratch@[i_prev4];
        warp_scratch@[i_curr4] = c4 + p4;
    ]
    ret 0;
]
```

* **Speed**: Exactly $1 + 2 + 4 + 8 = 15$ additions per row. In AVX-512, this executes in **4 vector clock cycles** using horizontal shuffle and add (`vpaddd`).
* **Zero Sorting**: The weft shuttle fills polygon interiors and produces anti-aliased edge values simultaneously.

---

## 3. Stroke 3: Branchless Winding Rule Resolution

Once the raw prefix sum is computed, each pixel holds a cumulative winding value $W$. SAGR resolves coverage $\alpha \in [0..256]$ branchlessly:

### A. Non-Zero Winding Rule (`lm_resolve_nonzero`)
$$\alpha = \min(|W|, 256)$$
```sinc
fn lm_resolve_nonzero(w) [
    if (w < 0) [
        w = 0 - w;
    ]
    if (w > 256) [
        ret 256;
    ]
    ret w;
]
```

### B. Even-Odd Winding Rule (`lm_resolve_evenodd`)
Uses binary folding around $512$:
```sinc
fn lm_resolve_evenodd(w) [
    if (w < 0) [
        w = 0 - w;
    ]
    m = w & 511;
    if (m > 256) [
        fold = 512 - m;
        ret fold;
    ]
    ret m;
]
```

---

## 4. Multi-Tile Horizontal Backdrop Tension

When a polygon spans across multiple horizontal tiles ($Tx = 0, 1, 2...$):
* **Tile 0 (Enter)**: Contains the left downward edge. At column 15, the exit tension is $256$.
* **Tile 1 (Solid Interior)**: Contains no edges. It inherits `in_backdrop = 256` from Tile 0. The tile is recognized as a **Solid Interior** and filled at 100% coverage instantly.
* **Tile 2 (Exit)**: Inherits `in_backdrop = 256`. The right upward edge cancels the tension down to $0$, producing `out_backdrop = 0`.

The 272-word `warp_scratch` buffer is partitioned into two regions: words `0..255` hold the $16 \times 16$ pixel columns, while words `256..271` store the 16 right-edge carry-out values (`256 + row`) for rows $0..15$. When a cord crosses or spills past the column 15 boundary, its flux accumulates directly into this 17th carry slot to seed the backdrop tension of the next tile.

This tension carry guarantees that shapes spanning across the screen never glitch or break at 16-pixel tile boundaries.
