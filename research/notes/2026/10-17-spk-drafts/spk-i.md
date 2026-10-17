---
id: 2026-10-17-spk-i
kind: note
title: "SPK-i: BeginFrameControl in a linux-arm64 container, fonts from snapshot only, byte-identical count vectors"
status: decided
created: 2026-10-17
topics: [spike, decision-record, chromium, determinism, counts-lane, v-i, ci]
---

# SPK-i (decision record)

**Decision.** Byte-identical count vectors are **not reached** and are dropped as a goal. V-i is re-scoped to
**per-type determinism classes**: every Chromium count type is classified by Lean `measure.classify`
(`lean/Fw/Measure/Classes.lean`, `classify` l.158 @32c6336) under the policy **kMax = 4 frames, tMax = 24 count
units, 3 runs**, as deterministic, stable or quarantined. The first CI evidence (run 39029423874 @ee18c6b) gives
**33 deterministic, 20 stable, 9 quarantined** of 62 types. The other two parts of the question pass: BeginFrameControl
works in the container, and fonts come only from `snapshot/`.

**Question (PLAN Appendix B).** Does linux-arm64 headless-shell in a container accept BeginFrameControl with the three
flags, with fonts only from `snapshot/`, and give byte-identical count vectors?

| Part | Answer | Status |
|---|---|---|
| BeginFrameControl in the container | yes: 503 virtual frames per run on CI | MEASURED (run 39029423874, job `counts (r1)`: `frames=503`, host wall 87.8 s) |
| Fonts only from `snapshot/` | yes: the image has no system fonts | MEASURED (run 39029423874, job `image`: `fc-list lines: 0`; check in `packages/measure-chromium/src/image-check.sh:5`) |
| Byte-identical count vectors | no: all three `counts.json` and `zones.json` sha256 differ | MEASURED (run 39029423874, job `classify`, `sha256-all.txt`) |

## Evidence

| Claim | Evidence | Status |
|---|---|---|
| Chromium refuses BeginFrameControl on macOS, hence the container | `headless/lib/browser/protocol/target_handler.cc` l.62-65 @317846d579b2 (PLAN §4.1) | CONFIRMED |
| As-built flags: `--enable-begin-frame-control --run-all-compositor-stages-before-draw` plus `--disable-new-content-rendering-timeout --disable-checker-imaging --disable-image-animation-resync --num-raster-threads=2 --disable-gpu`; `--deterministic-mode` was dropped at 70c3370 | `packages/measure-chromium/src/run.mjs:32-36` @32c6336; PLAN §4.2 step 1 | CONFIRMED |
| CI classes 33 / 20 / 9 (62 types, 3 runs on separate `ubuntu-24.04-arm` runners, one image `sha256:aa5134f54884`) | `gh run view 39029423874` (headSha ee18c6b), job `classify`: `classify.mjs ... --kMax 4 --tMax 24` | MEASURED |
| The CI classifier is the Lean one: `classify.mjs` decides nothing, it calls fwcore `measure.classify` mode `frames` | `packages/measure-chromium/src/classify.mjs:1,12`; `src/fwcore.mjs:38` @32c6336 | CONFIRMED |
| Class meaning: deterministic = no frame differs in any run pair; stable(k, t) = k <= kMax frames differ and totals differ by t <= tMax; else quarantined. The class is the strictest that holds | `Classes.lean` l.124 (`Policy`), l.158 (`classify`), `classify_sound` l.384, `classify_strictest` l.412 @32c6336 | CONFIRMED |
| Use: deterministic types frame by frame; stable(k, t) only as totals with margin 2t; quarantined never | `lean/Fw/Measure/Tolerance.lean` `margin_exact` l.193, `quarantined_unsound` l.234, `stable_frames_unsound` l.144 @32c6336 | CONFIRMED |
| Quarantined on CI: census.activeTileAreaPx (k 1, t 16384), census.drawingAreaPx (k 1, t 752), metric.LayoutObjects, metric.Nodes, trace.HitTest (k 116), trace.Layer.deleted, trace.MajorGC, trace.MinorGC, trace.UpdateLayoutTree.elementCount | run 39029423874, job `classify` | MEASURED |
| Earlier Mac container result: 28 / 14 / 8 of 50 types (before the census and raster types were added) | `docs/team/handoffs/lean-measure.md` @ddc91b2; PLAN §4.2 table | MEASURED (local, superseded by CI) |

## Classes are not stable across CI workflow runs (new finding)

Same Chromium lane code in all three runs (`git diff ee18c6b da5d49e` touches only a docstring in
`lean/Fw/Measure/WebKit.lean`; `git diff ee18c6b 12271fd` is empty for `packages/measure-chromium`, the workflow,
`snapshot/` and `lean/Fw/Measure`; CONFIRMED). Each workflow run builds its own image.

| Run id | headSha | Image id | det / stable / quar | Status |
|---|---|---|---|---|
| 39029423874 | ee18c6b | `sha256:aa5134f54884` | 33 / 20 / 9 | MEASURED |
| 39031884554 | da5d49e | `sha256:2c8d323772c9` | 31 / 21 / 10 | MEASURED |
| 39033771018 | 12271fd | `sha256:5315b7be0edc` | 27 / 25 / 10 | MEASURED |

Types that change class (MEASURED, `classify` job of each run): metric.Documents and metric.Frames (det -> stable in
the 2nd and 3rd run); trace.CullRectUpdate, trace.ImageDecodeTask, trace.PaintImage, trace.ResizeObserverNotify
(det -> stable in the 3rd run); trace.Paint (stable k 4 -> quarantined k 5, t 4 in the 2nd and 3rd run).

- The worst class per type over the three runs is 27 / 25 / 10, which equals run 39033771018 (MEASURED, by comparison
  of the three tables). A single classification over all 9 runs can only be this strict or stricter, since adding runs
  only demotes (`classify_mono`, `Classes.lean` l.437 @32c6336, CONFIRMED; the 9-run table itself was not computed, INFERRED).
- Cause: runner-to-runner noise or image differences; the image ids differ but a rebuild changes the id even with equal
  content, and apt versions are not pinned, so the two causes are confounded (INFERRED).

## Contradictions with the plan and the class policy (listed, not edited)

1. **V-i use of stable types.** PLAN §1.2 V-i row (l.152) says "Chromium: every type used for screening is
   deterministic". `class-policy.md` §2 and the earlier draft of this record proposed "deterministic, or stable and used
   only as totals with margin 2t". The lead must pick one; with CI numbers, "deterministic only" excludes trace.Layout,
   trace.Paint, trace.RasterTask and LayoutCount from screening.
2. **Numbers are out of date.** PLAN §4.2 and `class-policy.md` §2 report 28 / 14 / 8 of 50 types (Mac, pre-70c3370).
   The as-built lane has 62 types; the CI tables above supersede it. `class-policy.md` also lists metric.Frames and
   metric.Resources as stable and metric.Documents as quarantined; run 39029423874 has all three deterministic.
3. **"Frozen" classes vs drift.** PLAN §4.2 cites only 33 / 20 / 9 (ee18c6b). Two later runs of the same code give
   different classes (table above), so a class signed from one workflow run does not hold for the next.
4. **tMax in pixels.** `class-policy.md` says tMax = 24 "only mattered for elementCount". On CI two pixel-area types
   (activeTileAreaPx t 16384, drawingAreaPx t 752, both k = 1) are quarantined by tMax alone, so one tMax in "count
   units" now governs pixel areas too (MEASURED values; the unit mismatch is INFERRED to be unintended).
5. **Flags.** The earlier draft of this record and `packages/measure-chromium/README.md:46` still list
   `--deterministic-mode`; `run.mjs:34` and PLAN §4.2 say it was dropped (CONFIRMED).

## Missing
- A 9-run (or cross-run) classification artifact; a pinned image (apt pins or a cached image digest across workflow
  runs) to separate image drift from runner noise.
- Software raster only, programmatic `scrollTo` instead of touch for the original (touch wedges BeginFrame, PLAN §4.2).

## Next step
1. Lead signs this record and `class-policy.md` after choosing contradiction 1. Owner: lead.
2. Freeze the class table as the worst class over at least 3 workflow runs (or one 9-run classify), with the image
   pinned. Owner: measure-engineer.
3. Decide whether pixel-area census types get their own tolerance or stay quarantined. Owner: lean-prover (policy in
   `Classes.lean`), lead.

## What this changes in the plan
- **§1.2 V-i row:** keep per-type classes, p = (4, 24), 3 runs; add that the signed class is the worst over at least 3
  CI workflow runs (MEASURED drift 33/20/9 -> 27/25/10) and state the chosen rule for stable types (contradiction 1).
- **§4.2 "What the first runs showed":** replace the 28 / 14 / 8 row as the current result by the three CI rows above;
  mark Paint as quarantined in 2 of 3 CI runs.
- **§10.2 M0 row:** SPK-i is recorded as "byte-identical files not reachable" (this file, status decided); the
  re-scope signature still waits on the lead.
- **Appendix B SPK-i row:** status "decided: not byte-identical; V-i per-type classes (spk-i.md)".
