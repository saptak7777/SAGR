# SAGR Simple Dino Run 🦖

An interactive, zero-dependency Chrome Dino runner built entirely in **SINC** and rasterized in real-time by the **SAGR Jacquard Loom** engine.

```text
╔═══════════════════════════════════════════════════════════════════════════════════╗
║  SAGR DINO  |  SCORE: 00480  HI: 01250  |  TILES: 10/10  |  CPU: 0.6% @ 60FPS     ║
╚═══════════════════════════════════════════════════════════════════════════════════╝
```

---

## 🎮 How to Play

Run the interactive launcher directly from your terminal:

```bash
./examples/dino/play.sh
```

### Controls
* **`[SPACE]` or `[W]`**: Jump over cacti / Restart after crashing
* **`[Q]`**: Quit to shell

---

## ⚡ Architectural Highlights

1. **Pure Fixed-Point Physics ($12.4$ Integer Math)**:
   * Gravity, jumping velocity, and obstacle scrolling run entirely in $12.4$ fixed-point coordinates with **zero floating-point operations**.
2. **Subpixel Anti-Aliased Vector Geometry**:
   * The Dino, cacti, ground line, and drifting clouds are vector polygons decomposed into geometric cords and woven by SAGR's 16-fencepost area coverage accumulator.
3. **Real-Time CPU Core Telemetry**:
   * Displays live CPU core utilization (typically **`< 0.8%` of a single CPU core**) because the Jacquard Loom finishes micro-tile rasterization in microseconds.
4. **Zero-Dependency Terminal TrueColor**:
   * Uses 24-bit ANSI TrueColor and Unicode half-blocks (`▀`) to display 2 vertical pixels per character cell without requiring X11, Wayland, or GPU driver stacks.
