# Chapter 7: Memory Contracts & Scratch Buffers

SAGR operates under a strict **Zero Dynamic Allocation Policy**:
* The core rendering pipeline never calls `malloc`, `free`, `realloc`, or dynamic heap allocators.
* All scratch buffers, tile working areas, and output surfaces are allocated upfront by the caller from a contiguous memory arena.

---

## 1. Scratch Buffer Bounds & Constants

To rasterize and composite micro-tiles, SAGR uses the following scratch buffers:

| Buffer Name | Word Count | Byte Size | Description |
| :--- | :---: | :---: | :--- |
| **`warp_scratch`** | `272` words | $2{,}176\text{ bytes}$ | Holds the 16 Warp Thread columns ($16 \times 16 = 256$) plus the 16 terminal exit-tension slots ($256..271$). |
| **`cov_scratch`** | `256` words | $2{,}048\text{ bytes}$ | Holds the resolved $16 \times 16$ sub-pixel alpha coverage values $\in [0..256]$. |
| **`tile_words`** | `128` words | $1{,}024\text{ bytes}$ | Final packed $16 \times 16$ TrueColor RGBA8 tile ($128$ 64-bit words). |
| **`dirty_mask`** | `128` words | $1{,}024\text{ bytes}$ | Full-screen dirty tile bitset ($8{,}192\text{ bits}$ covers up to 1080p). |

### SINC Constants Definition:
```sinc
const LOOM_WARP_SCRATCH_WORDS = 272;
const LOOM_COV_SCRATCH_WORDS  = 256;
const TILE_WORDS              = 128;
const SLSP_DIRTY_WORDS        = 128;
```

---

## 2. Arena Sizing Guidelines

When allocating a linear memory arena for an application or compositing pipeline, use the following sizing rule:

$$\text{Total Arena Bytes} = \text{Framebuffer Bytes} + \text{Tape Scratch} + \text{Loom Scratch} + \text{Asset Buffer}$$

### Example: Sizing for 1080p ($1920 \times 1080$)
```sinc
// 1. Framebuffer: 1920 * 1088 * 4 bytes = 8,355,840 bytes (~8.3 MB)
fb_words = 1044480;

// 2. Tape Buffer: Sized for up to 8,192 cords (32 bytes per cord)
tape_words = 8192 * 4; // 32,768 words = 262 KB

// 3. Tile & Loom Scratch:
scratch_words = 272 + 256 + 128 + 128; // 784 words = 6.2 KB

// Total minimum arena requirement: ~16 MB
```

---

## 3. L1 Cache Budget Analysis

```
  ┌─────────────────────────────────────────────────────────────┐
  │                 CPU L1 DATA CACHE (32 KB - 48 KB)           │
  │                                                             │
  │  ┌─────────────────────────┐  ┌──────────────────────────┐  │
  │  │ warp_scratch (2,176 B)  │  │ cov_scratch (2,048 B)    │  │
  │  └─────────────────────────┘  └──────────────────────────┘  │
  │  ┌─────────────────────────┐  ┌──────────────────────────┐  │
  │  │ tile_words (1,024 B)    │  │ dirty_mask (1,024 B)     │  │
  │  └─────────────────────────┘  └──────────────────────────┘  │
  │                                                             │
  │  TOTAL TILE WORKING STATE: 6,272 Bytes (~6.1 KB)            │
  │  REMAINING L1 CACHE HEADROOM: > 26 KB (> 80% Free)          │
  └─────────────────────────────────────────────────────────────┘
```

Because SAGR's working footprint ($6.1\text{ KB}$) is a small fraction of the L1 Data Cache, tile rasterization creates **zero cache line evictions to L2/L3 cache**.
