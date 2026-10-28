# geom-timed with ThreadedTimeBasedAnimationsEnabled off: which tracks tick on the WebKit main thread

Question (task geom-pref-off-ticking, graph r557): two notes disagree on the pref-OFF flip on the same 55 tracks. `10-2x-geom-webkit-midflip.md` (run 40629283336, main) reads
47 accelerated / 0 ticking from the second flip on. `10-2x-geom-prewarm.md` (parked branch worktree-wf_066a7844-684-1, run 40648228102) reads 25 accelerated / 30 ticking
in every flip. Which tracks tick in steady state, why, and does that explain the phone's RecalculateStyles long frames (phone-flip-p95: geom-timed 348 of 396)?
Investigation only: no site edit, no phone run. WKTR is not iOS Safari; it is the iOS 26.5 simulator build on GitHub Actions, never phone time; iOS Safari's pref default is OFF
(UnifiedWebPreferences.yaml:8557-8570@862f17d, CONFIRMED), WKTR's own default is ON, so the OFF lane (`mid-thr-off`, header `ThreadedTimeBasedAnimationsEnabled=false`) is the iOS proxy.

## Answer
- The contradiction is a readout difference, not an engine difference (MEASURED). The prewarm note's "25 accelerated / 30 ticking" is the raw property-name flag `a`
  (no class fold). The class-folded read is 47 and the engine oracle ticks 0.
- With the pref OFF the steady-state ticking set is EMPTY (MEASURED, 2 runs, 6 jobs, 16 flips with a sample after the first commit): every flip after the commit reads 47 accelerated / 0 ticking at p30, p50 and p80; the
  8 hidden image tracks have no renderer and are quiet (Lean branch `unrendered`).
- A transient set S1 of 21 tracks ticks until about p30 to p50 in some flips (MEASURED). It is not steady state, and the 2 pref-ON flips that could show it do not (INFERRED, n = 2).
- So no named track set explains the phone's 348 of 396 long frames with RecalculateStyles (INFERRED from an empty set and from recalcs per frame that do not follow the ticking set). No same-look track fix is justified.

## Probe and site diff, main against the parked branch (CONFIRMED by git diff main...worktree-wf_066a7844-684-1)
| file | difference | can change the readout? |
| --- | --- | --- |
| `accel-cli.mjs`, `midflip.mjs` | identical | no |
| `mid-page.mjs` | +22 lines: a trace and the held tracks carried into the flip | held-set arms only; not the `a` flag |
| `morph.tween/geom-timed.driver.ts` (+111), `driver.ts`, `geom-timed.bus.ts`, `morph.geom/index.tsx` | build and hold the tracks and the flip tree before the push | yes: 2 of 6 first flips held; the held `.is-flip` tree moves layout (that is why geom-prewarm was parked) |
| report reader | prewarm note counts `a` (raw `getAnimations` flag as probed); midflip note folds property classes (`readsAccelCls`) | yes: this is the whole 25 against 47 |
The raw flag misses the CSS individual transform properties: `translate`, `scale` and `rotate` are reported by the layer as `transform` (GraphicsLayer.cpp:103-124@862f17d), so a raw name match
(`readsAccel norm "translate" ["transform"] = false`, Lean `raw_misses_folded`) counts a layered `translate` track as not accelerated.

## Re-tally of run 40648228102, pref OFF j1 and j3 (MEASURED)
| count | tracks | what |
| --- | --- | --- |
| raw `a` = 1 | 25 | 18 transform, 1 backdrop-filter, 4 opacity, 2 filter |
| raw `a` = 0 (the "30 ticking") | 30 | 20 translate, 2 scale, 8 hidden image tracks (unrendered) |
| class-folded accelerated | 47 | the 25 plus the 22 translate/scale tracks |
| engine oracle ticking | 0 | `timeToNextAnimationTick` above the 15 ms interval |
The prewarm note's "30 ticking" is 22 folded-accelerated tracks plus 8 unrendered ones, none ticking. Midflip's 47 / 0 was right.

## Main code, pref OFF and ON, per track key (MEASURED)
Runs: 40653612323 (push 1, d79a4bab5; arms all, all-again, all-3, all-4) and 40657027777 (push 2, fbc187650; 8 flips per job, layer flag per sample). 3 jobs each, flips 1 to 8.
Per-flip grid of accelerated/ticking at p30, p50, p80 and at the creation flush: `results/geom-pref-off-ticking/grid-r1-r2.txt`; ticking rendered tracks per sample:
`results/geom-pref-off-ticking/ticking-rendered-off.txt`. Reducers `keySummary` and `reasonOf` in `packages/measure-wktr/src/midflip.mjs` (a TS stand-in of the Lean branch, not golden-replayed).
| pref | sample | accelerated / ticking (of 47 rendered) | where |
| --- | --- | --- | --- |
| OFF | creation flush | 0 / 47 (all `unaccelerated`) in every flip but r1j1 flip 1 (0 / 0 at ph -46, all pending) | every job; flush before the effect starts reads `not-active` |
| OFF | p30, p50, p80, flips 2-8 | 47 / 0 | every sampled cell (r1j1, r1j2, r2j2, plus p80 of r2j1, r2j3); oracle exception r2j1 flip 4 p80 at ph 993, see below |
| OFF | p30 of 5 flips, p50 of 2 flips | 26 / 21 | S1, see below; p80 is 47 / 0 in all of them |
| ON | creation flush | 0 / 47 | all jobs |
| ON | p30, p50, p80, flips 2-8 (r2j1) | 47 / 0 | every sampled cell |
| ON | first flip p50 (ph 407) | 0 / 47 | commit not yet done; p80 47 / 0 |
One pref-OFF cell, r2j1 flip 4 p80 at ph 993, reads 47 / 47 by the engine oracle (Lean predicate 0): the oracle ticks at the very end of the tween (the known end-of-tween artefact), not a track set.
Counts of 94 in the ON grid are two samples in one bin.

## The transient set S1 (MEASURED set, mechanism INFERRED)
21 tracks: 13 rendered `img[data-mg=image]` transform, `logo/translate`, `earn/opacity`, `earn/filter`, `earn/translate`, `earnClip/translate`, `earnLabel/translate`,
`footerGrad/scale`, `footerEnd/translate`. Lean branch `unaccelerated` (running, active, rendered, no accelerated entry); the engine oracle agrees on all 21 (Lean and oracle agree on every S1 sample).
- It appears at p30 in 5 of 16 pref-OFF flips with a p30 sample (r1j1 flip 1, r1j2 flip 1, r2j2 flips 1, 3, 7) and at p50 in 2 (r1j1 and r2j2, flip 1). It is gone at p80 every time.
- Correlation (MEASURED, small n): the creation flush ran while the effects were still pending (flush phase below 0) in 6 flips with a p30 sample, and S1 followed in 5 of them (r1j1 flip 1 at -46, r1j2 flip 1 at -13, r2j2 flips 1, 3, 7 at -19, -16, -9; the exception is r1j2 flip 2 at -7).
  In the 10 flips with a p30 sample and a flush at phase 0 or later, S1 appeared in none. With the pref ON, flips with a negative flush (r2j1 flips 6 and 7 at -16, -12) read 47 / 0 at p30: S1 is pref-OFF only (INFERRED, n = 2 pref-ON flips).
- Layers (MEASURED, r2j2): the 21 elements HAVE a composited layer at the sample (layer probe `l` = 1 for all 21, in every S1 sample). The layer-missing explanation is refuted at sample time.
  At rest (`layBefore`, flips 2 to 8) the elements of image, logo, earn, footerEnd and footerGrad (and lang, 2 of 5 column) have no layer, so a layer is created during the flip.
- Source reason (WebKit@862f17d, INFERRED for causality, lines CONFIRMED):
  - `KeyframeEffect::ticksContinuouslyWhileActive` (KeyframeEffect.cpp:2724-2746) stays true until the effect is completely accelerated and `isRunningAccelerated()`; with the pref OFF that is `m_runningAccelerated == Yes` (1680-1689).
  - It is set only inside `applyPendingAcceleratedActions` after `renderer->isComposited()` (2402-2411), which runs when `DocumentTimeline::applyPendingAcceleratedAnimations` drains the set filled by `acceleratedStateDidChange` (WebAnimation.cpp:1647-1650; DocumentTimeline.cpp:209-216, 422-424, 432-455).
  - The Play action is only recorded when `updateAcceleratedActions` finds a composited renderer (KeyframeEffect.cpp:2060-2071) and `canBeAccelerated` holds (1965-2030). A track whose first update ran before the layer existed waits for a later update; until then it ticks.
  - Which later update, and why the flush before activation delays it by 300 to 500 ms on the CI clock, is not shown. That step is INFERRED.
  - The pref ON uses `m_acceleratedRepresentation` and does not wait for the renderer (same file, `canHaveAcceleratedRepresentation`), which fits S1 being absent there.

## Phone question
Steady state is empty, so no geom-timed track keeps ticking on the main thread after the first commit with the iOS pref default (INFERRED to hold on iOS: WKTR is not iOS Safari).
Recalcs per frame in the flip arms (r2, `frameSummary`, 3 to 5 frames per flip because of the slow WKTR clock): pref OFF j1 and j3 2.0 to 2.3, j2 3.4 to 4.0; pref ON j1 3.0 to 4.0, j2 and j3 2.0 to 2.3.
The value follows the job, not the pref and not S1: pref ON j1 has no ticking track and reads 3 to 4. The 2 recalcs per frame of the idle arm (4 `sweepDoc` background-position CSS animations, midflip note) are the remaining candidate; sweepDoc platform animations are out of scope here.
Verdict: the pref-OFF ticking tracks do not explain the 348 of 396 long frames (INFERRED, n = 3 jobs, CI clock).

## One proposed next step
No geom track fix. Run `geom-sweep-paused` (investigation, WKTR plus one phone session booked by the user): the accel lane with an arm that pauses the 4 `sweepDoc` animations during a flip, 3 jobs, pref OFF; if recalcs per frame fall from 2 to 0 and the phone's style per long frame falls toward the base value, then the same-look task `geom-sweep-compositor` (move the sweep to a compositor property) is justified. If not, the style cost is in the style invalidation of the flip itself and needs element counts per recalc, not track counts.
S1 itself would need a flush that waits for activation (probe-side), not a site change; it is below the 15 ms interval for 2 or 3 samples at p30 only.

## Lean and checks
`lean/Fw/Parts/MorphTrackAccel.lean`: `Reason`, `reasonOf` with one theorem per branch (`reasonOf_pending`, `_notRunning`, `_notActive`, `_unrendered`, `_accelerated`, `_disallowed`, `_incomplete`, `_unaccelerated`),
`ticksMain_eq_reason`, `raw_misses_folded`. Golden `packages/contracts/golden/parts/morph-track-accel.jsonl` (regenerated from Lean; tick lines carry `reason`, `raw` lines pin the fold). TS stand-ins: `reasonOf`, `keySummary` (not golden-replayed).

## Limits
Investigation only; WKTR is not iOS Safari; no phone run; 2 of 3 pushes used (run ids 40653612323, 40657027777; the Lean lane of push 1 is 40653612431). The 8 hidden tracks are `unrendered` by construction.
The CI frame clock is slow (first frame 220 to 650 ms late), so the flush lands mid-tween in most jobs and p30/p50 samples exist mainly in r1j1, r1j2 and r2j2 (and r2j1 for the ON lane); S1 counts rest on 16 flips with a p30 sample.
The `.github/workflows/wktr.yml` `ACCEL_MODES` env existed on the ci branch only and is reverted in the last commit.

## Lesson (general)
A probe must fold property classes before it says "not accelerated" and must take "ticking" from the engine oracle or the Lean predicate, never from a raw flag: the same report read 25 / 30 or 47 / 0 depending on the reader.
