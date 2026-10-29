# glint-hold-wktr

Question: does `platform.glint:hold-freeze` cut the residual WebKit style recalcs that the SMIL timeline of the 2 `[data-fw-dash]`
glint svgs carries (geom-recalc-bisect, 10-2x-geom-recalc-bisect.md, run 40812007953)? Task glint-hold-wktr, pinned unit: WKTR
accel lane, threaded-animations pref OFF, 3 jobs, recalcs per 100 frames for idle and flip, flag vs base vs the all-paused floor.

## Decided before the data (Lean, CONFIRMED by the golden replay)
`lean/Fw/Device/GlintHold.lean`, golden `packages/contracts/golden/device/glint-hold.jsonl` (check.sh job "device-glint-hold golden
check"), replayed by `packages/measure-wktr/test/glint-hold.test.mjs` against the TS stand-in `src/glint-hold.mjs`.
- Schedule (theorems `rampSegs`, `ticking_*`): per dash the hold ring ticks 2 animations on its 2 ramp segments of 5 and 0 on the
  3 hold segments; left holds [1,2,4], right [0,3,4]. The union of ramp segments is 4 of 5, so the dashes together are quiet only in
  segment 4. The faithful arm ticks 2 at every elapsed time.
- Prediction: a frame that follows a SMIL tick (a dash ticks in that frame or the frame before) recalcs at the base rate b, any other
  at the floor f: `pred = f + (b - f) * q / n`, q = hold frames after a tick, n = hold frames. The SMIL phase per frame is read in the
  page (`svg.getCurrentTime()` minus the begin time seen by a `beginElement` wrapper).
- Verdict (`judge`): unread, premise, no-contrast, uninformative, cuts more (h + band < pred), cuts less / no cut (pred + band < h),
  else cuts as predicted; band = max((b - f)/16, spread of the base arms). Overall: at least 2 judged jobs, all alike.

## Results (MEASURED, CI WKTR of the iOS 26.5 Simulator build, pref OFF, not phone time)
Run 40820116581 (push 1, 6 flips): idle cuts as predicted (2 of 3 jobs judged, j1 uninformative), flip unread or uninformative in all
3 jobs (18 to 36 frames; flips were missed). Push 2 (commit 6ad2a5828) added a flip retry and 16 flips: wktr run 40823517468.

Run 40823517468 (`results/glint-hold-wktr/r2`, recalcs per 100 frames; base = mean of two base arms, floor = every svg timeline paused):

| job | cell | base | floor | hold | predicted | band | hold frames after a tick | verdict |
|---|---|---|---|---|---|---|---|---|
| j1 | idle | 99 | 0 | 73 | 78 | 6 | 232/292 | cuts as predicted |
| j2 | idle | 101 | 0 | 74 | 79 | 6 | 215/272 | cuts as predicted |
| j3 | idle | 100 | 0 | 74 | 80 | 6 | 236/295 | cuts as predicted |
| j1 | flip | 193 | 85 | 156 | 172 | 6 | 39/48 | cuts more |
| j2 | flip | 170 | 81 | 150 | 153 | 5 | 39/48 | cuts as predicted |
| j3 | flip | 189 | 86 | 147 | 156 | 6 | 33/48 | cuts more |

- Overall idle: **cuts as predicted** (3 of 3 jobs). Overall flip: **mixed** (cuts more twice, as predicted once; the Lean rule does not
  merge them). Reading, INFERRED: the cut is at least the predicted one in every job; none reads cuts less or no cut.
- The cut is real but partial: idle falls from about 100 to about 74 per 100 frames (about 26 percent), not to the floor 0, because
  about 80 percent of hold frames still follow a tick (the two dashes ramp in different segments, so only segment 4 is quiet).
- Style-work proxy (`results/glint-hold-wktr/r2/zsum.txt`): the style-recalc tree size summed per 100 frames is 0 in every idle arm,
  base and hold, so a glint recalc touches no element in the tree (MEASURED). In the flip cell it is 600 to 725 per 100 frames in every
  arm including the floor and hold, so the flip tree work does not come from the glint (MEASURED; flip floor is 81 to 86 recalcs per 100,
  not 0). There is no style-ms in this lane; the cost of an empty-tree recalc is not measured here (limit).

## Mechanism (WebKit @862f17d)
- SMIL timer 1/60 s per outermost svg: `SMILTimeContainer.cpp:42,86-92,261-316`; each tick runs `SVGAttributeAnimator.cpp:105-125`
  -> `SVGLinearGradientElement.cpp:94-104` -> gradient resource invalidation (the last link INFERRED).
- `<set>` and frozen pieces stop timers: `SVGSMILElement.cpp:1074-1088` `calculateNextProgressTime`. This is why only hold segments
  stop ticking (CONFIRMED from source, consistent with the measured 26 percent cut).

## Look (CONFIRMED by proof)
Same look by `Fw.Parts.PlatformGlintHold.hold_eq_faithful` (class E, not a look candidate), pixels `glint.hold-pixels` run 40345059212
(worst channel 1 Chromium, 0 WebKit), breakpoint gate run 40345141093. No user look review is needed.

## What blocks v2-proved (CONFIRMED from `Gen.run`, trajectory run 40823517367 at 6ad2a5828)
Trajectory probe `--fw platform.glint:hold-freeze`, both engines: Chromium hero pass, Chromium morph pass (0 new units of 14416),
Linux WebKit hero pass; recorded with `Gen.record`, `Gen.entry` untouched by hand. Still open:
1. WebKit morph cell: Linux WebKit cannot decide the morph path, so the cell stays pending (needs Mac Safari or the Simulator lane).
2. `why`: no `linkTable` entry (verdict no-link); needs exactly one ledger row at status "proved". The row is "partly-proved" with
   WebKit zone counts undecided; this note's idle result can feed it but is WKTR, not iOS Safari.
Result: not a member; `Gen.run` wrote 2 flags (`engine.scroll:unthrottle`, `hero.exit:threaded`).

## Limits
WKTR is not iOS Safari; no phone run; flip cells have 48 hold frames per job; 3 jobs of one pass each; the recalc cost in ms is not measured.
