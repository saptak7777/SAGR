# Chapter 4: Wang's Dyadic Flattener & Monotonic Slicing

Curve flattening via recursive De Casteljau subdivision splits Bézier curves adaptively on the call stack until segment flatness falls below a tolerance threshold.

In a CPU vector engine, stack-recursive subdivision introduces several issues:
1. It causes unpredictable call stack depths and register spills.
2. It breaks SIMD vectorization due to branch divergence.
3. It generates dynamic arrays of temporary control points.

SAGR uses **Wang’s Dyadic Power-of-Two Flattener** ([`sagr/pure/flattener.sinc`](../sagr/pure/flattener.sinc)).

---

## 1. Wang’s Error Metric

For a quadratic Bézier curve defined by control points $P_0, P_1, P_2$, the maximum deviation from a straight line occurs at midpoint $t = 0.5$:

$$\delta = \frac{1}{4} |P_0 - 2P_1 + P_2|$$

To ensure that the deviation is strictly bounded below sub-pixel tolerance $\epsilon = \frac{1}{16}\text{ px}$ ($16$ units in $Q24.8$), the required number of uniform segments $N$ is calculated analytically in a single step:

$$N = \left\lceil \sqrt{\frac{|P_0 - 2P_1 + P_2|}{8 \epsilon}} \right\rceil$$

---

## 2. Integer Dyadic Power-of-Two Rounding ($N = 2^k$)

Instead of computing square roots or dividing by arbitrary values of $N$, SAGR rounds $N$ up to the next power-of-two ($2^k$) using the x86-64 `lzcnt` instruction:

$$k = \left(64 - \text{lzcnt}(D)\right) \gg 1$$
$$N = 1 \ll k$$

### Why Power-of-Two ($2^k$) Is Crucial
When $N = 2^k$, evaluating points along the curve uses **pure bitwise shifts instead of integer division**. In `fl_eval_pt`, forward differences are evaluated directly using shift operations:

```sinc
prod1 = i * delta1;
term1 = prod1 >> k;
i_sq = i * i;
prod2 = i_sq * delta2;
k2 = k << 1;
term2 = prod2 >> k2;
sum1 = p0 + term1;
res = sum1 + term2;
```

---

## 3. Zero-Float Octagonal Norm (`bo_octagonal_norm`)

Calculating Euclidean 2D distance $\sqrt{dx^2 + dy^2}$ requires floating-point operations or slow integer square root loops. SAGR approximates vector magnitude using the **Octagonal Norm**:

$$\|V\| \approx \max(|dx|, |dy|) + \frac{1}{2} \min(|dx|, |dy|)$$

### SINC Implementation ([sagr/pure/bitops.sinc](../sagr/pure/bitops.sinc)):
```sinc
fn bo_octagonal_norm(dx, dy) [
    ax = bo_abs(dx);
    ay = bo_abs(dy);
    max_d = ax;
    min_d = ay;
    if (ay > ax) [
        max_d = ay;
        min_d = ax;
    ]
    half_min = min_d >> 1;
    res = max_d + half_min;
    ret res;
]
```
* **Accuracy**: Maximum error is $< 3.9\%$, which is mathematically sub-pixel negligible for curve subdivision limits.
* **Speed**: Computes in 3 CPU cycles using basic ALU operations.

---

## 4. Monotonic Slicing

Before flattening, curves are split at their first-derivative roots ($x'(t) = 0$ and $y'(t) = 0$).

This guarantees that every cord emitted to the tape is **strictly monotonic in $Y$** ($y_0 \le y_1$ or $y_0 \ge y_1$). Monotonicity ensures that a cord intersects each scanline at most once, making downstream Loom area accumulation branchless.
