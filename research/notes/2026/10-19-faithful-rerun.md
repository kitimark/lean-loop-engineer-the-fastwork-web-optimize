# Faithful check re-run after page-root-clip (task faithful-checks-rerun)

Status: MEASURED (Chromium counts, CI), verdict computed by Lean (`Fw.Faithful`, fwcore `faithful.verdict`); the anchor part is
PROVED in Lean (`Fw.Gate.PageRoot`). Educational study of the public fastwork.com homepage, not affiliated with Fastwork.
Method, bands and class table are those of `research/notes/2026/10-18-faithful-checks.md`; this note holds the new numbers only.

## Question

With the page root clipping horizontal overflow (task page-root-clip), does the rewrite R stay inside the PL5 bands of the
original A in the zones `y04000`, `y04500`, `tail`, for swipe-v1 and swipe-touch-v1? The 645x1398 run of the first note is
discarded as not comparable and replaced.

## Runs

| profile | CI run | commit | shards per arm | viewport |
|---|---|---|---|---|
| swipe-v1 | 39146329183 (chromium-counts, target both) | b8c051ab | 3 original + 3 rewrite, separate jobs | 430x932, scrollWidth 430 (page-root-clip) |
| swipe-touch-v1 | 39146332555 (chromium-counts, target both) | b8c051ab | 3 original + 3 rewrite, separate jobs | same |

A is the frozen original baseline (`results/baselines/chromium/<p>/`), A' the original of the same run (control), the class
table `classes.frozen.json`. Files: `results/faithful/runs/<p>/*`, verdicts `results/faithful/<p>.verdict.json`, Lean theorems
`Fw.Faithful.Measured` (`swipeV1_*`, `swipeTouchV1_*`, `decide`).

## Verdict per zone

| profile | zone | shape (frames, px) A / R | off-band cells | verdict |
|---|---|---|---|---|
| swipe-v1 | y04000 | 50, 500 / 50, 500 | 26 of 44 judged | FAIL |
| swipe-v1 | y04500 | 14, 136 / 14, 136 | 14 of 43 | FAIL |
| swipe-v1 | tail | 30, 0 / 30, 0 | 14 of 38 | FAIL |
| swipe-touch-v1 | y04000 | 50, 500 / 50, 500 | 26 of 40 | FAIL |
| swipe-touch-v1 | y04500 | 13, 129 / 13, 129 | 15 of 41 | FAIL |
| swipe-touch-v1 | tail | 30, 0 / 30, 0 | 15 of 41 | FAIL |

- Control A'/A passes all three zones on both profiles with zero failing cells (harness and verdict code reproduce A in its bands).
- Shape now matches in every zone: R has 12 (swipe-v1) and 13 (swipe-touch-v1) zones like A, and the same frames and scrolled px.
  The first note's 240 px shorter page and the touch "did not scroll" stop are gone (page-root-clip). Touch: no data last time, data now.
- What stays off band (cell lists in `verdict.zones[].offBand`; numbers A vs R medians):
  - y04000, both profiles, 26 cells: layout work R does and A does not (`metric.LayoutCount` 0 vs 24, `trace.Layout` 0 vs 24,
    `trace.Layout.totalObjects` 0 vs 1505, `RecalcStyleCount` 152 vs 175 on swipe-v1); fewer animation-frame callbacks
    (`trace.RequestAnimationFrame` 204 vs 154 on swipe-v1, 175 vs 131 on touch; exact family); compositor census (`census.layers` 3188 vs
    3662, `census.tiles` 7284 vs 5252, `census.drawingAreaPx` +32 %); `raster.invalidationRects` 571 vs 103.
  - y04500: rAF callbacks (42 vs 28; 67 vs 54), the census family, `raster.invalidationRects`, `trace.Layout.totalObjects` 50 vs 54.
  - tail: swipe-v1 rAF callbacks 51 vs 48 and the census family; touch adds `trace.Layout.totalObjects` 21540 vs 49650 and R decodes no
    image there (`trace.DecodeImage` 6 vs 0, `ImageDecodeTask` 367 vs 0).
- Unbanded differences (reported, never gating): `trace.EventDispatch`, `FunctionCall`, `ResizeObserverNotify`, plus `HitTest` on touch.
- R has 17 (swipe-v1) and 18 (swipe-touch-v1) types the frozen table does not list (unlisted, not gating) and detDrift 40 / 56 cells
  across its three shards: the rewrite is less deterministic than A in these runs (INFERRED to be the live rAF/animation work of R; not diagnosed).

## Gate anchor

`Fw.Gate.PageRoot` (lean/Fw/Gate/PageRoot.lean): the anchor `scrollWidth <= innerWidth` as a gate item (class box, key
`scrollWidth<=innerWidth`), statuses `equal` (both arms fit), `differ` (original fits, rewrite overflows), `na` (original overflows:
no valid control), `missing`. Theorems: `status_equal_iff`, `status_differ_iff`, `status_na_of_orig_overflow`, `status_missing`,
`cell_pass_iff`, `cell_fail_iff` (as the only item of a cell, with `cellVerdict`), and the why: `clip_fits` (with overflow-x clip it
holds for any content width), `noclip_overflows` (without the clip, content wider than the viewport breaks it, the 645 px case),
`noclip_fits_of_le`. `anchors.json`: role `pageRoot` (original `.start-selling`, rewrite `[data-fw="page-root"]`, dimension `w`) in part
`engine.scroll`, so the existing box comparison already sees a root whose width leaves the viewport. The `scrollWidth` observation
itself is not collected by `page.mjs` yet (it reads `innerWidth` and `clientWidth`): follow-up.

## Limits

Chromium only; one CI run per profile (3 shards per arm); stable-type margin is the PLAN 2t proxy; R judged by the median of its 3
shards; WebKit and pixels out of scope; counts are work, not milliseconds. Findings only: nothing was patched, causes of the
layout and rAF differences are not diagnosed here.
