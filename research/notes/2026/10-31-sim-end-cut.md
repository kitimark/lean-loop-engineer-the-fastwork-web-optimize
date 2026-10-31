# sim-end-cut: do the end-of-page sources found by sim-floor-attrib, removed with same-look flags, cut the live Simulator rate from 200 to 100?

Task `sim-end-cut`, follow-up of `10-31-sim-floor-attrib.md` section 6. Question: on the CI iOS Simulator, with animations running, does the end and back
stage style-recalc rate drop from 200 to 100 per 100 frames when the park flags remove the scroll and view timeline animations and the off-screen pauses
remove the looping document animations? No flag or preset change.

Answer: no. The recorded prediction held for parks alone and pauses alone (both stay 200) and missed for both: parks plus pauses reads 200 at the end and back
stage in 3 of 3 jobs. The census says why: two of the five flags did not take effect (`hero.exit:threaded-park` in 3 of 3 jobs, `platform.sweep:offscreen-pause`
in 3 of 3), so 13 view-timeline animations and 2 sweep loops still run in `both` (sections 3 and 4).

## 1. Run

- MEASURED: run 41173535319 (workflow webkit-sim, commit `2afff9f6ba69b7ff60f60aa66aaf00013a321701`), 3 separate CI jobs r1, r2, r3, one round each, one build, runtime
  `com.apple.CoreSimulator.SimRuntime.iOS-27-0` (`results/sim-end-cut/r1/cut.txt:1-2`). The arm order is rotated by 1 per job: r1 `v2p, parks, pauses, both`, r2
  `parks, pauses, both, v2p`, r3 `pauses, both, v2p, parks` (`results/sim-end-cut/r1/job{1,2,3}.json`, `rounds[0].order`). Window 360 `requestAnimationFrame`
  callbacks, stages end (idle at the end, animations running), back (returned to the end) and paused (all animations paused; v2p and both only in the table).
- The first push (run 41173075281, commit 35807f6bc) failed in the `site` job before any sim job: `platform:faded-pause conflicts with platform.sweep:offscreen-pause`
  (`apps/site/src/registry/resolve.ts:141`, `apps/site/src/parts/platform/part.json:46-48`). So the `pauses` and `both` arms do not contain `platform:faded-pause`; they swap it
  for the three pauses. This differs from the task text ("v2p plus the three pauses") and is an accepted limit (section 6).
- Arms (searches in `packages/measure-webkit/src/sim-end-floor.mjs` `CUT_ARMS`; flag sets in Lean `Fw.Device.SimEndCut.ArmId.flags`):
  - `v2p`: `engine.scroll:unthrottle`, `hero.exit:threaded`, `platform:faded-pause`.
  - `parks`: v2p with `engine.scroll:unthrottle-park` and `hero.exit:threaded-park` in place of `unthrottle` and `threaded`.
  - `pauses`: `unthrottle`, `threaded`, `hero.accent:offscreen-pause`, `hero.cue:offscreen-pause`, `platform.sweep:offscreen-pause` (no `faded-pause`).
  - `both`: the two parks and the three pauses.
- Edges (named flag sets, so that the Attrib one-part rule applies; Lean `edges`, proofs `parks_v2p_real`, `pauses_v2p_real`, `both_parks_real`, `both_pauses_real`):
  parks against v2p, pauses against v2p, both against parks, both against pauses. Real parts that differ: parks `engine.scroll, hero.exit`; pauses `platform,
  hero.accent, hero.cue, platform.sweep`.
- Window quality: 36 windows, `seen` is 360 in 30 and 362 to 379 in 6, all in the end stage (`rows.txt`, `seen`). Reconnects: job1 `pauses` round 1 attempt 1 and job2 `parks`
  round 1 attempt 1, each `Runtime.evaluate timed out after 120000 ms` (`job1-log.txt:14`, `job2-log.txt:5`); the reported windows are from the fresh load.

## 2. Rates (MEASURED)

Source: `results/sim-end-cut/r1/table.txt` (from `sim-end-floor-cli.mjs cut`); windows in `rows.txt`. Rate = recalcs per 100 frames, band 10, Lean tier two = 200.

| stage | arm | rate per 100 (r1, r2, r3) | scheduled per frame | table.txt line | rows.txt lines (r1, r2, r3) |
|---|---|---|---|---|---|
| end | v2p | 200, 200, 202 | 1.00, 1.01, 1.02 | 1 | 1, 25, 49 |
| end | parks | 200, 202, 205 | 1.00, 1.02, 1.05 | 2 | 2, 26, 50 |
| end | pauses | 200, 204, 202 | 1.00, 1.04, 1.00 | 3 | 3, 27, 51 |
| end | both | 200, 203, 201 | 1.00, 1.00, 1.01 | 4 | 4, 28, 52 |
| back | v2p, parks, pauses, both | 200, 200, 200 each | 1.00 each | 5-8 | 5-8, 29-32, 53-56 |
| paused | v2p | 200, 200, 200 | 1.00 | 9 | 9, 33, 57 |
| paused | both | 200, 200, 200 | 1.00 | 10 | 12, 36, 60 |

## 3. Lean verdicts against the named comparators (prediction recorded before the run)

Prediction (Lean `predTier`, committed before the first CI push): both reaches 100 at end and back; v2p, parks and pauses stay 200
(`cut.txt:3`). Verdicts from `Fw.Device.SimEndCut` (TS stand-in checked against `packages/contracts/golden/device/sim-end-cut.jsonl`); each edge differs in one named set.

| edge | stage | overall verdict (3 jobs) | predicted | held | cut.txt line |
|---|---|---|---|---|---|
| parks against v2p | end | noEffect:parks | noEffect:parks | held | 7 |
| parks against v2p | back | noEffect:parks | noEffect:parks | held | 11 |
| pauses against v2p | end | noEffect:pauses | noEffect:pauses | held | 15 |
| pauses against v2p | back | noEffect:pauses | noEffect:pauses | held | 19 |
| both against parks | end | noEffect:pauses | cut:pauses | missed | 23 |
| both against parks | back | noEffect:pauses | cut:pauses | missed | 27 |
| both against pauses | end | noEffect:parks | cut:parks | missed | 31 |
| both against pauses | back | noEffect:parks | cut:parks | missed | 35 |

Per-arm tiers: v2p, parks, pauses two (held) and both two (predicted one, missed) at end and back (`cut.txt:36-43`); the paused reference is two for v2p and both
(`cut.txt:44-45`). No stage of any arm reaches tier one.

## 4. Census: which flag took effect (MEASURED)

Lean `Fw.Device.SimEndCut` `Flag.took` over the page census (`cut.txt:46-77`, census rows `rows.txt`, line = (round - 1) * 24 + 13 + 3 * arm + stage with arm
v2p 0, parks 1, pauses 2, both 3 and stage end 0, back 1, paused 2). The census is complete in every window (running list under the cap of 24). End and back stages are the same.

| flag | arms holding it | took (rounds 1, 2, 3) | what the census shows |
|---|---|---|---|
| `engine.scroll:unthrottle-park` | parks, both | yes, yes, yes | scroll-driven animations 0 (v2p and pauses hold 1 `scroll:finished`) |
| `hero.exit:threaded-park` | parks, both | no, no, no | 13 `view:finished` animations remain in every parks and both window (`rows.txt:16`, `:22`, `:40`, `:46`, `:64`, `:70`) |
| `hero.accent:offscreen-pause` | pauses, both | pauses yes x3; both no, yes, yes | both round 1: 3 accent idle loops still running (`cut.txt:58`) |
| `hero.cue:offscreen-pause` | pauses, both | yes, yes, yes | cue float not running in pauses or both |
| `platform.sweep:offscreen-pause` | pauses, both | no, no, no | 2 sweep loops still running (v2p holds 4) (`cut.txt:54-56`, `:58-60`) |

Running animations left per arm at the end stage (`cut.txt:46-61`): v2p 13 view, 1 scroll, accent 3 (rounds 1, 2), cue 1, sweep 4; parks 13 view, accent 3 (rounds 2, 3),
cue 1, sweep 4; pauses 13 view, 1 scroll, sweep 2; both 13 view, sweep 2, accent 3 (round 1 only). The loops are the `document` timeline animations in the `running` list of the census rows.

## 5. What still schedules (INFERRED from the census and sim-floor-attrib)

- `both` keeps two sources the prediction needed gone: the 13 view-timeline animations (the hero park did not engage) and 2 sweep loops. The previous note showed that a
  scroll or view timeline animation is ticked every frame whatever its play state (`AnimationTimelinesController.cpp:149-177@862f17d`, CONFIRMED by reading) and that cancelling all 14 cuts
  the paused 200 to 100 (`research/notes/2026/10-31-sim-floor-attrib.md`, section 2). So the 13 view animations are the INFERRED main holder in `both`; the 2 sweep loops are a second one.
  This run cannot split them: no arm removes the view animations or the 2 sweeps alone.
- The hero park did not engage under the harness's jump to the page end. The park uses an IntersectionObserver on a zero-height sentinel and
  `10-30-scrolldriven-park.md` already measured that an instant jump may never fire it (INFERRED, same cause). The rate cannot show it; the census does (view-driven 13).
- The 2 remaining sweep loops: the pause watches only the elements matching `.${sw.sweep}` at mount (`apps/site/src/parts/platform/index.tsx:151`, `apps/site/src/parts/platform.sweep/pause.ts:41`). The remaining
  loops sit on one `sweep-module` word and one `platform-module` word (`rows.txt:43`, census truncated at 48 characters); that the second is outside the selector and the first not yet reported hidden is INFERRED.
- Paused stage: every document animation is paused yet v2p and both read 200 with the 13 view animations present and paused (`rows.txt:15`, `:24`), as in the previous note: view and scroll animations schedule
  while paused.

## 6. Accepted limits, follow-up candidate

- The Simulator is not the phone. The first unscheduled recalc of the paused base is out of scope (open in sim-floor-attrib).
- `hero.exit:threaded-park` is a class-L proposal measured here only; no preset change. The effective `ThreadedScrollDrivenAnimationsEnabled` value stays INFERRED.
- The `pauses` and `both` arms drop `platform:faded-pause` (conflict, section 1). sim-floor-attrib measured `platform:faded-pause` as noEffect at every stage (`10-31-sim-floor-attrib.md`, section 3), so the swap is not
  expected to move the rate; this run has no arm that isolates it (INFERRED).
- Follow-up candidate (spec only, to be built as its own task): make the two failing flags engage, then re-run these four arms with the same Lean verdicts.
  1. Hero park: check the page-end position by a scroll or `scrollend` handler (or one rAF check after a jump) so that it does not depend on an IntersectionObserver callback after an instant jump.
  2. Sweep pause: track every `sweepDoc` element, not only `.${sw.sweep}`, and log full class names in the census.
  Prediction for that run: census shows view-driven 0 and no sweep loop running in `both`, and `both` reads 100 at end and back (INFERRED from the 200 to 100 cancel in sim-floor-attrib); parks alone and pauses alone stay 200.
  Lesson recorded here: a census `took` check is part of the arm, since a flag that does not engage gives a clean-looking noEffect.
