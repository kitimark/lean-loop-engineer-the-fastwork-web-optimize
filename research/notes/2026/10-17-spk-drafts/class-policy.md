---
id: 2026-10-17-class-policy-draft
kind: note
title: "Determinism-class policy per lane (DRAFT for the lead to sign)"
status: draft
created: 2026-10-17
topics: [determinism, measurement, policy, chromium, webkit, spk-i, spk-j]
---

# Determinism-class policy (frozen on signature)

**Status: DRAFT.** Nothing here is signed. The lead signs by moving this file to `research/decisions/` and changing
`status` to `signed`. Values marked **PROPOSAL** are my reading of the evidence, not a fact.
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

## 2. Chromium lane (container, `swipe-v1`, 503 frames, 3 runs)

| Parameter | Value | Status |
|---|---|---|
| `kMax` | **4** frames | policy used for the 28/14/8 result; default in `classify.mjs:12` |
| `tMax` | **24** (count units over the run) | same; see the note below |
| minimum runs to assign a class | **3** | PROPOSAL (Lean accepts 2; the evidence was built on 3) |

**Result (MEASURED, 3 runs, same machine/image/snapshot; `lean-measure.md` @ddc91b2):** 28 deterministic, 14 stable,
8 quarantined, of 50 count types.

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
policy because it reproduces 28/14/8; the lead may tighten `tMax` to 4, which should change no class. That claim is
checkable with `node src/classify.mjs <3 runs> --tMax 4` (not run here; I do no measurements).

**Use (PROPOSAL, from `Tolerance`):** deterministic types feed the screen frame by frame; stable types only through
totals with margin `2t`; quarantined types are logged and never gated on. **Open for V-i:** the PLAN row requires
"Chromium: all used types deterministic" (PLAN V-i). Measured: 14 stable types exist that K1-K9 may need (layout and paint
families). See `spk-i.md` for the re-scope.

Known sources of residual noise (README, MEASURED): asynchronous image decode and iframe parsing against frame
boundaries (a 100 ms real-time barrier after each frame removed the PaintImage/RasterTask clusters), hover-recompute
hit tests after a programmatic `scrollTo`, GC timing. Software raster only; touch input not used.

## 3. WebKit lane (iOS Simulator, 4 passes in 2 independent boots, clock pinned)

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
- A fourth Chromium run, ideally on another day, to test the premise that unseen runs stay in class (owner: measure-engineer).
- The WebKit harness still calls its TS `reduce.mjs`, not fwcore (lean-measure handoff).
- `meas-chromium-2` has uncommitted work in its worktree (clock shim, run loop, Dockerfile, apt manifest). If it changes
  the classes, redo section 2.

## What this changes in the plan

- PLAN §4.2 / V-i (line 146): replace "all used types deterministic" by "every used type is deterministic, or stable
  under the policy above and used only by totals with margin 2t; quarantined types are never used".
- PLAN §10.2 M0: the "two byte-identical vectors" clause is met only for the 28 deterministic types; this policy is the
  recorded re-scope (see `spk-i.md`).
