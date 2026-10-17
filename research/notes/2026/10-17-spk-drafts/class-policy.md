---
id: 2026-10-17-class-policy-draft
kind: note
title: "Determinism-class policy per lane (Chromium decided by the lead; WebKit still a draft)"
status: review
created: 2026-10-17
topics: [determinism, measurement, policy, chromium, webkit, spk-i, spk-j]
---

# Determinism-class policy (frozen on signature)

**Status.** Section 2 (Chromium) and the use rule are **DECIDED** by the lead (6b4237e, "Lead decision" in
`spk-i.md`) and in PLAN revision 7 (§1.2 V-i rules). Section 3 (WebKit) is still a **DRAFT**. Values marked
**PROPOSAL** are a reading of the evidence, not a fact.
Evidence commits: `ddc91b2` (Lean `Fw.Measure`, READMEs of both lanes), `e01f9e5` (Chromium lane), `1d6c88c` (WebKit lane).

## 1. What the classes mean (CONFIRMED, Lean)

- Source of truth: `lean/Fw/Measure/Classes.lean` (`classify`, `classify_sound` l.384, `classify_strictest` l.412,
  `classify_mono` l.437 @b63572c) and `lean/Fw/Measure/WebKit.lean` (`classifyCells`, `classifyCells_snoc`).
- **Chromium (frame sense):** deterministic = no frame differs in any pair of runs; stable(k, t) = at most k frames
  differ and run totals differ by at most t, with `k <= kMax` and `t <= tMax`; quarantined otherwise
  (`packages/measure-chromium/src/classify.mjs:1-4` @ddc91b2).
- **WebKit (cell sense):** a cell is a total, a zone sum, a step or a census state. Deterministic = identical in every
  run; stable = every cell's spread within `max(absTol, relTol * max|v|)`; quarantined = some cell beyond
  (`packages/measure-webkit/README.md`, "Determinism" @ddc91b2).
- **How a class may be used (CONFIRMED, `Fw.Measure.Tolerance`, `margin_exact` l.193, `quarantined_unsound` l.234 @b63572c):**
  deterministic is compared frame by frame; stable(k, t) only by totals, with margin `2t` (0 when k = 0); a
  quarantined type never enters a screen. Frame-by-frame use of a stable type is unsound (`stable_frames_unsound`).
- **Adding runs can only demote** (`classify_mono`, `classifyCells_snoc` for `relTol <= 1`): a class is a statement
  about the runs seen. That unseen runs stay in the class is a premise outside Lean (lean-measure handoff, "Gaps").

## 2. Chromium lane (DECIDED; container, `swipe-v1`, 503 frames, 3 runs per workflow run)

| Parameter | Value | Status |
|---|---|---|
| `kMax` | **4** frames | DECIDED; default in `classify.mjs:12` |
| `tMax` | **24** (count units over the run) | DECIDED; see the note below |
| pixel-area types (name ends in `AreaPx`) | bound max(tMax, ⌊smallest absolute run total ÷ 1000⌋) | DECIDED (6b4237e); proved in `Fw/Measure/Classes`, `classifyU_*` (5879861) |
| runs per class | **3** per workflow run; the **signed** class is the worst over **≥ 3 CI workflow runs** with the image pinned | DECIDED (6b4237e); task `class-freeze` |

**Result on CI (MEASURED, 3 workflow runs of 3 runs each; 13b6c98, re-classed in 5879861):**

| Workflow run | det / stable / quarantined (counts rule) | with the pixel-area bound |
|---|---|---|
| 39029423874 | 33 / 20 / 9 | 33 / 22 / 7 |
| 39031884554 | 31 / 21 / 10 | 31 / 23 / 8 |
| 39033771018 | 27 / 25 / 10 | 27 / 27 / 8 |

`census.activeTileAreaPx` and `census.drawingAreaPx` leave quarantine in all 3 runs (largest gap 382 ppm of the
smallest total); no count type changes class. The classes drift between runs of the same code (6 types det → stable,
`trace.Paint` stable → quarantined; cause runner noise or an unpinned image, INFERRED), which is why one run's
classes are never signed (`spk-i.md`).

**Local run (rev 6, superseded by the CI rows; kept for the type names).** 3 local container runs gave 28
deterministic, 14 stable, 8 quarantined of 50 types (`lean-measure.md` @ddc91b2):

- **Deterministic (28):** hasDamage, RecalcStyleCount, JSEventListeners, UpdateLayoutTree, ScheduleStyleRecalculation,
  Layerize, Commit, ScrollLayer, FireAnimationFrame, RequestAnimationFrame, FunctionCall, EvaluateScript,
  EventDispatch, IntersectionObserverCompute, ResizeObserverNotify, CullRectUpdate, PaintImage, ParseHTML,
  ResourceSendRequest, Layer.created, ImageDecodeTask, DecodeImage, Animation.* and cc.Activate/Commit/Draw
  (the README hand table; the exact 28 are the output of `src/classify.mjs`, which I did not run).
- **Stable (14):** LayoutCount, Layout and its three sums, InvalidateLayout, PrePaint, Paint, UpdateLayer,
  cc.SynchronizeTrees, RasterTask, DisplayItemListRaster, plus `metric.Frames` and `metric.Resources`. One to four
  frames of 503 differ, by one shift; totals within 1 except Paint (3).
- **Quarantined (8):** trace.HitTest (98-119 frames differ by 1), `UpdateLayoutTree.elementCount` (38 frames differ),
  GC-bound `metric.Nodes`, `LayoutObjects`, `Documents`, `Layer.deleted`, MinorGC, MajorGC.
- Where the Lean result differs from the hand table (CONFIRMED, README): `elementCount` is quarantined, `Frames` and
  `Resources` are stable.

**Note on `tMax` (INFERRED):** every type admitted as stable has totals within 1 (Paint 3). `tMax = 24` only mattered for
`elementCount` (up to 24 of 48,300), which fails on `k` (38 > 4) anyway. **PROPOSAL:** keep 4/24 as the frozen
policy; the lead may tighten `tMax` to 4, which should change no count class. That claim is checkable with
`node src/classify.mjs <3 runs> --tMax 4` (not run here). For pixel-area types `tMax` is only a floor (above).

**Use (DECIDED, 6b4237e, from `Tolerance`):** deterministic types feed the screen frame by frame; stable types only
through totals with margin `2t`; quarantined types are logged and never gated on. "Deterministic only" was rejected:
it would drop trace.Layout, trace.Paint, trace.RasterTask and LayoutCount, the main scroll-cost signals.

Known sources of residual noise (README, MEASURED): asynchronous image decode and iframe parsing against frame
boundaries (a 100 ms real-time barrier after each frame removed the PaintImage/RasterTask clusters), hover-recompute
hit tests after a programmatic `scrollTo`, GC timing. Software raster only. Touch input wedged BeginFrame until
`--disable-features=WaitForLateScrollEvents` (25bd9f4; 21 local runs; the CI check is task `touch-ci-verify`);
`trace.HitTest` stays quarantined.

## 3. WebKit lane (DRAFT; iOS Simulator, 4 passes in 2 independent boots, clock pinned)

Tolerances `TOL` (`packages/measure-webkit/src/reduce.mjs:130-138` @1d6c88c; Lean `measure.classify` mode `cells`):

| Level | `absTol` | `relTol` |
|---|---|---|
| census (counts) | 1 | 0.05 |
| memory (backing bytes) | 0 | 0.02 |
| paint (`paintCount`) | 2 | 0.10 |
| total | 2 | 0.05 |
| zone (500 px) | 2 | 0.10 |
| step | 1 | 0 |
| exact | 0 | 0 |

- Minimum runs: 2 passes per session, 2 independent sessions; the worse class wins (`merge`). 93 of 104 table rows
  had the same class in both sessions (MEASURED). **PROPOSAL:** keep 4 passes as the minimum for a signed class.
- **MEASURED classes, scripted scroll (107 steps):**

| Count | total | per zone | per step |
|---|---|---|---|
| Composite | det | det | det |
| EventDispatch | det | det | det |
| FireAnimationFrame | stable | stable | stable |
| RecalculateStyles, ScheduleStyleRecalculation, FunctionCall | stable | stable | quarantined |
| TimerFire | det | stable | quarantined |
| Layout, InvalidateLayout, ObserverCallback, Paint (count and clip area) | stable | quarantined | quarantined |
| RenderingFrame | absent over the proxy on iOS 27.0 (0 records); `Composite` stands in | | |

- **Layer census:** gate layer counts at scroll y >= 3000 (deterministic there); y = 0 and 1500 are ranges
  (stable/quarantined). Reasons `animation` and `(gone)` and cumulative `paintCount` are quarantined.
- **Seek fixture:** all 32 rows deterministic (see `spk-j.md`).
- **Use (PROPOSAL):** only `Composite`, `EventDispatch` and the seek fixture are exact. Everything else is used as a
  total with the tolerance above. Per-zone and per-step counts are reported, never gated (the scroll is wall-clock driven
  and the original runs rAF continuously: about 105 per 3 s idle). `classifyCells_stable` shows frame-sense (k, t) always
  holds for cell-stable types, so the Chromium `Tolerance` margin rule applies to WebKit totals too.
- **Limit:** classes are for the pinned-clock page (a frozen countdown), Simulator on a Mac host, not phone counts.

## 4. Open items before signing

- The two lanes use different meanings of "stable" (frame-shift vs cell spread). The `Tolerance` theorem bridges them
  for totals; the lead should confirm that is acceptable for one gate.
- Chromium: the premise that unseen runs stay in class is now handled by signing the worst class over ≥ 3 CI runs
  (`class-freeze`), not by a fourth local run.
- WebKit: the harness still calls its TS `reduce.mjs` (`compositeCuts`, `reduceWindows` are Lean-first debt); the
  WebKit classes need CI runs too (task `sim-speed` first: Simulator runs take 10-38 min and fail at warm-up).

## What this changed in the plan (applied in PLAN revision 7)

- PLAN §1.2 V-i: "all used types deterministic" became the V-i rules: deterministic types frame by frame, stable
  types as totals with margin 2t, quarantined never; the signed class is the worst over ≥ 3 CI runs.
- PLAN §4.2: the CI rows and the pixel-area re-class above replace the local 28/14/8 numbers.
- PLAN §10.2 M1: "every used type signed deterministic or stable"; the M0 "byte-identical vectors" clause was
  re-scoped to per-type classes in revision 6.
