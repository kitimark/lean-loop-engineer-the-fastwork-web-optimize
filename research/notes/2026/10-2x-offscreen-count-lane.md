# Offscreen count lane: do the offscreen-pause flags cut rendering work while `#platform` is offscreen?

Tags: MEASURED (CI run id named), CONFIRMED (Lean theorem or source cited), INFERRED (reasoned, not seen).

## Answer

Neither flag shows a gain in this lane: both verdicts are `noGain`, and every one of 12 counters is the same number in all
3 runs of all 3 rewrite arms. The lane works (3 runs per arm on separate jobs, the window is the same 234 frames in every
run), so the null is a result, not a harness failure. The counters are page-wide, so they cannot see work that belongs to
`#platform` alone while the rest of the page keeps ticking.

| flag (rewrite, mobile 430x932, Chromium 156) | window frames | counters less / same / more | verdict | run |
|---|---|---|---|---|
| `platform.sweep:offscreen-pause` vs `rewrite` | 234 (3 runs) | 0 / 12 / 0 | noGain | 40115582041 (f1, r1-r3) |
| `platform.glint:offscreen-pause` vs `rewrite` | 234 (3 runs) | 0 / 12 / 0 | noGain | 40115582041 (f2, r1-r3) |
| WebKit (both flags) | not measured | | noData | follow-up (WKTR runs the original only) |

MEASURED, run 40115582041 (workflow `chromium-counts`, profile `offscreen-v1`, branch `ci/offscreen-count-lane`, sha e3ea0ff79,
jobs `counts (original|rewrite|f1|f2, r1..r3)`, summary artifact `offscreen-summary`). The first push, run 40114634566, failed
before any step of the lane: every `counts` job died on `ERR_MODULE_NOT_FOUND /contracts/src/flag-key.mjs` because the lane
container mounted only `src` since gate-flag-order; `host.mjs` now mounts `packages/contracts/src` too.

## Window sums (steady offscreen frames of one run, identical in r1, r2, r3 of each arm)

| counter | rewrite | sweep | glint | per frame, rewrite | per frame, original |
|---|---|---|---|---|---|
| metric.RecalcStyleCount | 291 | 291 | 291 | 1.244 | 1.137 |
| metric.LayoutCount | 146 | 146 | 146 | 0.624 | 0.585 |
| trace.UpdateLayoutTree | 291 | 291 | 291 | 1.244 | 1.137 |
| trace.Layout | 146 | 146 | 146 | 0.624 | 0.585 |
| trace.PrePaint | 378 | 378 | 378 | 1.615 | 1.590 |
| trace.Paint | 556 | 556 | 556 | 2.376 | 2.355 |
| trace.Commit | 234 | 234 | 234 | 1 | 1 |
| trace.cc.Draw | 234 | 234 | 234 | 1 | 1 |
| trace.cc.BeginMainFrame | 234 | 234 | 234 | 1 | 1 |
| trace.cc.NeedsTick (animation ticks, cc) | 702 | 702 | 702 | 3 | 3 |
| trace.cc.TickAnimations | 702 | 702 | 702 | 3 | 3 |
| trace.FireAnimationFrame (Blink) | 240 | 240 | 240 | 1.026 | 1.030 |

MEASURED (same run). Main-thread busy ms over the window (RunTask, informational, not in the verdict): rewrite 979, 818, 945;
sweep 938, 962, 967; glint 914, 961, 984; original 1002, 929, 969. The spread inside an arm (up to 160 ms) is larger than any
difference between arms. `MainFrameAborted` is 0 in every run.

The window is 234 of the 240 offscreen frames of the 300-frame profile: `top` (120 frames, `#platform` below the fold) and
`back` (120 frames, scrolled away again), minus the first 3 frames of each stretch (`settle`). CONFIRMED by the Lean rule
`Fw.Measure.Offscreen.Rec.hidden` and `steady`, golden `packages/contracts/golden/measure/offscreen.jsonl` replayed by
`packages/measure-chromium/test/offscreen.test.mjs`.

## Class counts (MEASURED, `chromium-classes` of run 40115582041, 3 runs per label, policy kMax 4, tMax 24)

| label | deterministic | stable | quarantined |
|---|---|---|---|
| original | 34 | 17 | 6 |
| rewrite | 36 | 17 | 4 |
| f1 (sweep) | 38 | 16 | 3 |
| f2 (glint) | 33 | 15 | 9 |

The verdict counters in the table are `deterministic` in their per-frame series except `trace.Paint` (quarantined, per-frame
series) and `trace.PrePaint` (stable); the window sums of the lane are the same number in all 3 runs. `trace.cc.NeedsTick`,
`trace.cc.TickAnimations` and `trace.cc.BeginMainFrame` come from the raw trace and have no class entry; their window sums are
also the same in 3 runs.

## Why no gain (what is known and what is not)

- MEASURED: the flags are active. The f1 trace holds 450 `PaintImage` events against 570 for rewrite and glint, and the
  `near` frames show 4 against 6 `PaintImage` per frame (run 40115582041, r1). `?fw=` is recorded in `meta.search` of the f1 job.
- MEASURED: whole-trace event counts (373 event names, r1) differ between rewrite, sweep and glint only in `PaintImage`
  (sweep), garbage collection and loader events. Style, layout, `UpdateLayer`, `RunTask`, `ElementAnimations::SetRunState`
  and `ScheduleAnimation` agree within 3 percent.
- MEASURED: the page ticks 3 cc animation ticks and 1 `FireAnimationFrame` per frame in every arm, also offscreen, in the
  original too. So some animation outside `#platform` stays active in all arms.
- INFERRED: the page-wide counters are dominated by the other sections' animations, so a pause inside `#platform` leaves them
  unchanged. This lane cannot attribute a counter to the elements of one section: Chromium trace events carry no element id
  for style, paint and animation ticks (`FireAnimationFrame` carries a frame id only).
- INFERRED: Chromium may already skip compositor work for offscreen layers, which would leave the sweep nothing to save.
- Not tested: whether the pause engages in the first stretch (`top`), where the page loads with `#platform` offscreen (the
  part's own limit: an animation created while offscreen is not tracked).

## Follow-ups (not in this task)

1. Isolation arm: serve the part page (`?only=platform...`) with the flag so no other section ticks; then a gain, if any,
   is visible in the same 12 counters. The workflow refuses `arms` together with `only` today.
2. WebKit: `webkit-sim.yml` / WKTR measure the original only; a rewrite build plus flag input is needed first.
3. Sections other than `#platform`.
4. `counts (f1, r1)` job names are not shards for `Fw.Store.Ci.shardOfJob`, so telemetry skips arms f1 to f4.

## Where things are

Lean `lean/Fw/Measure/Offscreen.lean`, `OffscreenGolden.lean`; reducer `packages/measure-chromium/src/offscreen.mjs`; profile
`profiles/offscreen-v1.json`; workflow `.github/workflows/chromium-counts.yml` (arms in the head commit line); doc
`docs/team/tools/offscreen-counts.md`.
