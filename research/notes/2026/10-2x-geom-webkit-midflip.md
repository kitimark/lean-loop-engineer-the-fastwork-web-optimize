# geom-timed mid-flip on WebKit: which tracks run accelerated, what ticks, where per-frame style comes from

Question (task geom-webkit-midflip): while a `morph.geom:on,morph.tween:geom-timed` flip is half-way through its 680 ms tween on WebKit, which of the
55 track animations run accelerated, is any effect pending or ticking continuously, what is `ThreadedTimeBasedAnimationsEnabled` in WKTR and in iOS
Safari, and how many `RecalculateStyles` (and elements) run per frame during the flip versus idle? Investigation only: no site edit, no phone run.

Runs (MEASURED, WKTR iOS 26.5 simulator build on GitHub Actions, 3 jobs each, `accel-cli.mjs run --modes mid,mid-thr-off`; never phone time):
- run 40626070244 (push 1, commit d361cb6ca): probe v1. Most arms had no mid-flip sample (see Limits).
- run 40629283336 (push 2, commit 0fae80336): flush samples after track creation and the class rule. Every number below is from this run unless it names run 1.
Artifacts `wktr-j1..j3`, each `accel-mid-1.json` (pref ON) and `accel-mid-thr-off-1.json` (pref OFF); reducers `packages/measure-wktr/src/midflip.mjs`
(`midSummary`, `frameSummary`), tests `packages/measure-wktr/test/midflip.test.mjs`.

## The rule that decides a verdict (CONFIRMED in source and Lean)
WebKit@862f17d. `WebAnimation::timeToNextTick` (WebAnimation.cpp:1917-1929): pending gives 0, not running gives infinity.
`AnimationEffect::timeToNextTick` (AnimationEffect.cpp:385-415): in the active phase it is end minus local time, or 0 when the effect
`ticksContinuouslyWhileActive`. `KeyframeEffect::ticksContinuouslyWhileActive` (KeyframeEffect.cpp:2724-2746): false without blending keyframes or without a
renderer; if the effect is completely accelerated and running accelerated it is false, except with the threaded pref when the accelerated representation is
missing or a property is disallowed; every other effect ticks. `isRunningAccelerated` (KeyframeEffect.cpp:1680-1689).
Lean `Fw.Parts.MorphTrackAccel`: `ticksContinuously`, `ticksMain = pending || (running && active && ticksContinuously)`, `tickOf` (pending, quiet, accelerated,
main), `binOf`, `normName`, `readsAccel`, plus `classOf` and `readsAccelCls` for the layer-list fold below; one theorem per OR-branch
(`readsAccelCls_no_tracks`, `readsAccelCls_empty`, `classOf_translate`, tick theorems in the same section). Golden
`packages/contracts/golden/parts/morph-track-accel.jsonl` (256 tick, 12 bin, 3 name, 8 cls lines), replayed by the TS mirror in the test. The oracle is the
engine itself: `Internals.timeToNextAnimationTick` below `animationsInterval` (15 ms) means the animation ticks.

## Threaded pref (CONFIRMED source, MEASURED in WKTR)
- `ThreadedTimeBasedAnimationsEnabled`: status preview, default false (UnifiedWebPreferences.yaml:8557-8570@862f17d). iOS Safari therefore runs it OFF
  (INFERRED: default from source, no shipped-build read). WKTR turns the experimental features on, so it is ON there: the `mid` mode reads th=true in
  3 of 3 jobs. The `mid-thr-off` mode sends the header `ThreadedTimeBasedAnimationsEnabled=false` (th=false in 3 of 3 jobs) and is the phone-like arm.
- With the pref ON, the layer reports the effect-stack entries per property (isThreaded true, `acceleratedEffectPropertyIDAsString`); with it OFF, the CA
  animations fold translate, scale, rotate and transform into one `transform` entry (GraphicsLayer.cpp:103-124, GraphicsLayerCA.cpp:5299-5344@862f17d).
  Probe v1 read the 13 translate and 1 scale track as not accelerated for that reason (a probe bug, found in run 1, fixed by the Lean class rule).

## Per-track verdict mid-flip (MEASURED, 30/50/80 % of the tween, run 40629283336)
55 tracks = 47 on rendered elements + 8 transform tracks on hidden image elements (no renderer, so never accelerated, never ticking).

| pref | job / flip | running | pending | accelerated | ticking on main | Lean agrees |
|---|---|---|---|---|---|---|
| ON | j1, j2: first flip, 30/50/80 % (all 6 samples) | 55 | 0 | 47 | 0 | 55 of 55 |
| ON | j1, j2: second flip (all-again) | 55 | 0 | 47 | 0 | 55 of 55 |
| OFF | j1: first flip at 80 %; second flip in j1, j2, j3 | 55 | 0 | 47 | 0 | 55 of 55 |
| OFF | j2: first flip at 50 % and 80 % | 55 | 0 | 26 | 21 (transform 13, translate 5, opacity 1, filter 1, scale 1) | 55 of 55 |
| both | right after creation, before the first frame (flush sample) | 55 | 0 | 0 | 47 (all rendered) | 55 of 55 |

- Per OR-branch of the Lean rule: pending (none of the flip tracks after creation); not running (none); not rendered (the 8 hidden: quiet); complete and
  accelerated and threaded OFF or representation present (quiet, 47); not yet accelerated, i.e. before the first commit (ticks, 47); not completely
  accelerated (ticks, the 21 in OFF j2 first flip). The engine and the Lean predicate agree on every active-phase sample of the flip arms (all, all-again).
- So no flip track is pending after creation and, once the first commit has run, no track ticks continuously. The window in which they do tick is between
  creation and the first commit (up to the first frame), and in one of three OFF jobs (j2) 21 tracks were still on the main thread at 50 and 80 %.
  Cause of that j2 case: UNDETERMINED. It had a 1713 ms hole in its frames (see below) and the same job's second flip was 47/0, so a late first commit is the
  likely reading (INFERRED).
- Pending appears only where the probe holds tracks paused (arms no-translate, no-transform): paused tracks are pending until the first frame and the Lean
  predicate matches the engine there (sample f-style). Three Lean-vs-oracle disagreements remain in those held arms (the paused tracks counted in the class
  tally); the flip arms have none. Samples before the tween starts (phase <= 0) are outside the Lean predicate.

## Per-frame style: idle versus flip (MEASURED, `Internals.styleRecalcCount`, run 40629283336)
| arm | frames (3 jobs, both prefs) | recalcs per frame | elements updated per frame (`lastStyleUpdateSize`) |
|---|---|---|---|
| idle (no flip, page at rest) | 119 | 1.91 to 2.11 (job values), 1 timeline invalidation per frame | 0 in every frame |
| flip arms (none, all, all-again) | 95 | 2 to 3.5, max 6 in one frame | 0 in 90 frames; 1, 1, 4, 4, 41 (mid) in the other 5 |
Run 1 (40626070244) agrees: idle 0 elements in 125 frames; flip arms one frame of 18 (mid) and frames of 4 and 166 (mid-thr-off).
- The 2 recalcs and the 1 invalidation per frame exist with no flip: 4 CSS animations `sweep-module_sweepDoc` (background-position, main-thread only,
  `timeToNextAnimationTick` 0, no accelerated entry) tick every frame in idle and in every track arm. That is the continuous per-frame source on WebKit
  (CONFIRMED by the listing at 500 ms of the idle arm: 4 sweepDoc at ttnt 0, one `cue-module_scrollFloat` accelerated and quiet).
- The tracks add no continuous ticking once committed: the oracle reads 0 ticking tracks in `all-again`. Recalcs per frame there are 2 to 3 against 2 in idle
  (the sparse WKTR frames carry the poll and creation work), so a small excess is not excluded.
- Extra work appears once, in the frames at and after creation: the `morph-module_up/down` CSS animations (3 of them, transform) are running and pending with
  ttnt 0 and no accelerated entry in the first-flip listing (j1, j2, pref ON; j2 pref OFF) and `nav-module_earn-unmask/-sheen` are finished but pending. In
  the second flip and in the `none` arm they are quiet and accelerated (ttnt 4 s to 15 s). The one-off style update of up to 166 elements (run 1) sits in that
  frame. This is pending work of a new compositor representation, not a per-frame effect.

## Does it explain the phone's 348 of 396 long frames? (INFERRED, no phone data here)
Reference: `research/notes/2026/10-2x-phone-flip-p95.md` (geom-timed: 396 long frames, 348 of them `RecalculateStyles`, 45 ms of style per long frame against
10 ms in the base). On the phone the pref is OFF (source), where my OFF samples show committed tracks accelerated and quiet. Therefore:
- Not explained by ticking tracks after the first commit: the engine reports 0 continuously ticking flip tracks once they are accelerated (MEASURED, WKTR).
- Not explained by the sweepDoc animations alone: they tick in the base arm too (10 ms style per long frame there, 423 long frames).
- Left as INFERRED candidates: (a) style cost per recalc grows with the flip's layer and animation count (55 tracks over 91 listed animations) while the same
  2 recalcs per frame continue; (b) the creation frame (up to 166 elements, pending morph/nav animations) repeated per push, 10 pushes per visit; (c) in
  the OFF case a late first commit (the j2 21-track case) keeps part of the tracks on the main thread longer. CI cannot rank them (next section).

## Limits
- WKTR is not iOS Safari: its frame clock is slow (first frame after creation 220 to 650 ms late, 3 to 30 frames per 700 ms, one hole of 1.7 s), so
  per-frame cost at 60 Hz is not visible and no recalc duration is read. Sampling is by animation phase through rAF plus a 4 ms poll, which is why mid-flip
  samples exist at all. The hidden-element and `before` samples are outside the rule.
- The iOS pref default is read from source, not from a shipped build. The archive is WebKit 324039@main, the source pin 862f17d.
- Run 1 gave 3 to 8 active-phase samples per job (18 in one OFF job; late first frame), so its table is not used for verdicts.

## Proposed next step (INFERRED effect; CI cannot show per-frame 60 Hz cost)
A phone run is the next step (the lead arranges it): arms flip and flip + a measurement-only probe `sweep:probe-paused` (`animation-play-state: paused` on the 4
`sweepDoc` spans during a push; a probe, never promoted, because it changes the look). If style per long frame in the flip arm falls toward the base value, the
fix task is `geom-sweep-compositor`: express the sweep as a transform or opacity track (same look, checked by the visual-sameness harness) so the 2 recalcs
per frame disappear for the base and the flip. Expected effect INFERRED: the base and flip style counts (1237 and ~800 per visit) fall by the sweep share;
this share is not known from CI. If the style per long frame stays at 45 ms with the sweeps paused, candidates (a) and (b) remain and the fix is a
pre-created paused track set (created at idle, started by `currentTime`), whose pending first frame the WKTR flush samples already show.

## Negative and general lesson
Predicting "tracks run on the main thread" from the pref alone was wrong for committed tracks: with the pref OFF the tracks are accelerated and quiet; the
only window in which they tick is before the first commit. A probe that reads layers must fold property classes the way the engine does (Lean `classOf`).
