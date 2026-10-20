# panel-final-size (C1): refuted on the visual

Candidate C1 from `10-20-webkit-lag-source.md` (line 137): lay the morph panel, backdrop and columns out once at the
final panel size, centred in the nav and clipped by the nav's `overflow: hidden`. It does remove every panel subtree
layout, but it changes the picture on 36 of the 42 frames of a push. The task's stop rule applies: no flag, no
goldens, no CI. This note records the finding.

## Result

| Claim | Status | Lean (`Fw.Parts.MorphPanelOpt.FinalSize`) |
|---|---|---|
| End frame `m = 1`: the scenes are equal for every layout | proved | `end_E` |
| Hidden frames `m ≤ 0.08`: neither arm shows a box (panel opacity 0) | proved | `hidden_E` |
| Layout sizes differ by `(1 - m)·(panelW - pillW)` and `(1 - m)·(panelH - pillH)` | proved | `size_gap` |
| The footer is drawn `(1 - m)·ΔH/2` lower in the arm, below the nav clip | proved | `footer_shift` |
| Every `m` in `(0.08, 1 - 1/(2ΔH))` breaks VisSame (not even Q at ½ px) | proved | `not_Q`, `desk_not_Q`, `phone_not_Q` |
| Work bound: the arm lays out the panel subtree on no frame | proved | `relayouts_final` |
| The original lays it out on every frame where `m` changes (41 per push) | proved, `#guard` | `relayouts_orig_pos` |

ΔH = `panelH - pillH`: 820 − 64 = 756 at 1440 × 900, and 820 − 52 = 768 at 390 × 844. ΔW = 414 on desktop and 8 on phone.

## Which frames differ, and by how much

Frames are 60 Hz tween samples `k · 50/3 ms` of the 680 ms ease-out cubic (`Fw.Parts.MorphTween.tween`). The verdicts come
from `FinalSize.verdict` and are pinned by `#guard`. They are identical at 1440 × 900 and 390 × 844.

| Push | E | differs | Q only |
|---|---|---|---|
| 0 → 1 | k = 0, 1, 41 | k = 2 … 37 (600 ms) | k = 38, 39, 40 |
| 1 → 0 | k = 0 and k ≥ 24 (hidden) | k = 1 … 23 (383 ms) | none |

The layout height gap at 1440 × 900 for the 0 → 1 push, in panel px before the panel's `scale()`. The footer shift is half
of it. Columns shift by `(1/2 − offset)` times it, so up to 0.83 × the gap for the −33 % columns.

| k | m | panel opacity | height gap | footer shift |
|---|---|---|---|---|
| 2 | 0.139 | 0.08 | 650 px | 325 px |
| 5 | 0.324 | 0.34 | 511 px | 255 px |
| 10 | 0.569 | 0.68 | 325 px | 163 px |
| 17 | 0.801 | 1.00 | 150 px | 75 px |
| 25 | 0.941 | 1.00 | 44 px | 22 px |
| 31 | 0.986 | 1.00 | 10 px | 5 px |
| 37 | 0.999 | 1.00 | 0.6 px | 0.3 px |
| 38 | 0.9997 | 1.00 | 0.2 px | 0.1 px (Q) |

Why the boxes depend on the panel size (CSS, `apps/site/src/parts/`):
- The panel is `inset: 0` in the nav, so in the original it reflows with the nav every frame.
- The veil's `radial-gradient(123% 74% …)` is sized from its own box.
- The backdrop is `inset: 0 -3%`, its columns are `flex: 1 1 0`, and each one moves by `translateY(var(--col-offset))`, a percentage of its own height.
- The footer is anchored by `bottom: 0`.
- The title is `width: min(941px, 100%)` with `text-wrap: balance`. This is not in the model, which already fails without it.

With C1, the arm shows a crop of the end-state layout. The original shows the layout at the current nav size.

## Engine sources: why only the clip parent would repaint

- WebKit@862f17d. A size change repaints the whole layer:
  - `PlatformCALayerRemote.mm:596-607`: `setBounds` calls `updateBackingStore`.
  - `PlatformCALayerRemote.mm:333-355`: `ensureBackingStore` runs with the new size.
  - `RemoteLayerBackingStore.mm:145-152`: changed parameters lead to `clearBackingStore`.
  - `RemoteLayerBackingStore.mm:139-143`: `clearBackingStore` calls `setNeedsDisplay`, a full repaint. CONFIRMED.
- WebKit@862f17d. A move does not repaint:
  - `PlatformCALayerRemote.mm:615-622`: `setPosition` only records `PositionChanged`.
  - `GraphicsLayerCA.cpp:603-610` (`setPosition`) and `641-648` (`setSize`) only record `GeometryChanged`.
  - `RenderElement.cpp:1482-1565`: `repaintAfterLayoutIfNeeded` compares rects in repaint-container coordinates, and equal rects repaint nothing (1565).
  - A size change with fill layers repaints the full box (1494-1523, 1544).
  - CONFIRMED.
- WebKit@862f17d, layout: when the containing block lays out its children, it marks the out-of-flow panel and lays it out (`RenderBlock.cpp:901-915, 925-929, 944`). So the panel box itself still gets a layout call every frame, because its offset moves. That its subtree is skipped at a fixed size is INFERRED.
- Chromium@f842f52, `raster_invalidator.cc:64-143` (`ChunkPropertiesChanged`): raster is invalidated only when a chunk's clip or effect state changes relative to its layer state.
  - An equal tight clip gives `kNone` (105-116).
  - Any other clip change relative to the layer state invalidates (136-142).
  - A nav clip above the panel's layer state is applied by cc without raster. INFERRED for these layers.

The paint saving is CONFIRMED for WebKit layer resizes and INFERRED for Chromium; area not measured (webkit-lag-probe). The candidate fails only because the picture changes.

## Follow-ups (not done here)

- C1b: morph the nav with `transform: scale` and `clip-path` at the final size. It needs its own VisSame model with counter-scaled content; `not_Q` predicts the same failure unless the panel content keeps its per-frame size.
- A narrower C1: fix only the boxes whose ink does not depend on the panel size, for example the columns' width when the panel width does not change (phone ΔW = 8). Each box needs its own `size_gap`-style bound below the ½ px tolerance.
- WebKit paint area is waiting on webkit-lag-probe; it is an accepted limit of this task.
