# sim-end-cut-2: with park-engage and sweep-pause-all landed, does the live end-of-page rate reach 100 per 100 on the Simulator?

Task `sim-end-cut-2`, re-run of `10-31-sim-end-cut.md`. Question: on the CI iOS Simulator, with animations running, does the end and back stage style-recalc rate per 100 frames reach 100 for
any of the four arms (v2p, parks, pauses, both)? No flag or preset change; gate: none (measurement task).

Answer: no, not in any arm. All 12 arm-stage cells read tier two (197 to 205 per 100) in 3 of 3 jobs (`results/sim-end-cut-2/r1/table.txt:1-8`). This time every flag took in every
job (census, section 3), so the result is a real no-effect, not an untested one. `both` has one source left in its census: the 2 sweep loops that are in view (Secure, Organized).
They must run, so the sweep pause rightly leaves them (INFERRED), and they hold the rate at 200. Pausing them (the `paused` stage) reads 100 per 100 in `both` (3 of 3 jobs).
Candidate for the next step: `platform.sweep:layer-sweep` (class L, look change, spec only here).

## 1. Run

- MEASURED: webkit-sim run 41204019629 (commit `e23ab818e0474ab69212f79b675dfeed4615afe1`), 3 separate CI jobs r1, r2, r3, one round each, runtime
  `com.apple.CoreSimulator.SimRuntime.iOS-27-0` (`results/sim-end-cut-2/r1/cut.txt:1-2`). Lean run 41204019683 at the same commit: success. Arm order rotated by 1 per job: r1 `v2p, parks, pauses, both`,
  r2 `parks, pauses, both, v2p`, r3 `pauses, both, v2p, parks` (`job{1,2,3}.json`, `rounds[0].order`). Window 360 `requestAnimationFrame` callbacks; stages end, back, paused (v2p and both).
- Arms as in `10-31-sim-end-cut.md` section 1 (Lean `Fw.Device.SimEndCut.ArmId.active`): `v2p` = `engine.scroll:unthrottle`, `hero.exit:threaded`, `platform:faded-pause`; `parks` = `engine.scroll:unthrottle-park`,
  `hero.exit:threaded-park`, `platform:faded-pause`; `pauses` = `unthrottle`, `threaded`, `hero.accent:offscreen-pause`, `hero.cue:offscreen-pause`, `platform.sweep:offscreen-pause` (no `faded-pause`, it conflicts with the sweep pause,
  `apps/site/src/registry/resolve.ts:141`); `both` = the two parks and the three pauses.
- Window quality: 36 windows, `seen` 360 in 29, 361 to 378 in 7, all end-stage windows (`rows.txt`). `both` had a reconnect in job 1 and in job 3 (`Runtime.evaluate timed out after 120000 ms`, `job1-log.txt:31`, `job3-log.txt:11`);
  the reported window is from the fresh load.

## 2. Rates (MEASURED)

Rate = recalcs per 100 frames, band 10, tier two = 200 (`table.txt`, `rows.txt`).

| stage | arm | rate per 100 (job 1, 2, 3) | tier | table.txt line |
|---|---|---|---|---|
| end | v2p | 205, 200, 200 | two | 1 |
| end | parks | 203, 201, 200 | two | 2 |
| end | pauses | 205, 200, 200 | two | 3 |
| end | both | 202, 197, 203 | two | 4 |
| back | v2p, parks, pauses | 200, 200, 200 each | two | 5-7 |
| back | both | 200, 200, 200 | two | 8 |
| paused | v2p | 200, 200, 200 | two | 9 |
| paused | both | 100, 100, 100 | one | 10 |

In `both` at the paused stage schedule per frame is 0.00 and recalcs per frame 1.00 (`table.txt:10`); at end schedule is 1.00 to 1.03.

## 3. Census before the verdict (MEASURED)

Lean `Fw.Device.SimEndCut.Flag.took` over the page census (`cut.txt:46-77`, `effect` lines; golden `packages/contracts/golden/device/sim-end-cut.jsonl`). The census is complete in every window.

| flag | arms | took-check | took (jobs 1, 2, 3) |
|---|---|---|---|
| `engine.scroll:unthrottle` | v2p, pauses | unthrottle elements > 0 and 1 scroll-driven animation | yes, yes, yes |
| `hero.exit:threaded` | v2p, pauses | 13 view-driven animations, parked 0 | yes, yes, yes |
| `engine.scroll:unthrottle-park` | parks, both | scroll-driven 0, unthrottle parked > 0 | yes, yes, yes |
| `hero.exit:threaded-park` | parks, both | view-driven 0, hero parked | yes, yes, yes (was no in sim-end-cut: park-engage fixed it) |
| `hero.accent:offscreen-pause` | pauses, both | none of the accent idle loops running | yes, yes, yes |
| `hero.cue:offscreen-pause` | pauses, both | cue float not running | yes, yes, yes |
| `platform.sweep:offscreen-pause` | pauses, both | no running sweep loop outside the viewport (in-view loops allowed) | yes, yes, yes (hidden 0; v2p and parks have 4 running, 2 hidden) |

Running animations left at end (`cut.txt:46-77`, `sources` lines): v2p 13 view, 1 scroll, cue 1, sweep 4 (accent 3 in jobs 2, 3); parks cue 1, sweep 4 (accent 3 in job 2); pauses 13 view, 1 scroll, sweep 2; `both` sweep 2 only.
The back stage census is the same. So the verdict is gated on took (Lean `gate_took`) and stands; no cell reads `untested`.

## 4. Lean verdicts (prediction recorded before the run)

Prediction (`cut.txt:3`, Lean `predTierFor`): v2p, parks, pauses two; `both` one only if no source remains in its census, otherwise two (INFERRED: the 2 in-view sweep loops remain, so two).

| edge | stage | overall verdict | predicted | gated | cut.txt line |
|---|---|---|---|---|---|
| parks against v2p | end / back | noEffect:parks | noEffect:parks | held | 7 / 11 |
| pauses against v2p | end / back | noEffect:pauses | noEffect:pauses | held | 15 / 19 |
| both against parks | end / back | noEffect:pauses | noEffect:pauses | held | 23 / 27 |
| both against pauses | end / back | noEffect:parks | noEffect:parks | held | 31 / 35 |

Tier lines `cut.txt:36-45`: v2p, parks, pauses, both two at end and back, all held; paused v2p two, paused both one (reference). All 8 edge predictions and all 8 tier predictions held.

## 5. What is left in `both` (MEASURED census, INFERRED attribution)

- `both` end and back: the only running animation is `platform sweep` x2 (`sources both end round 1..3`, `cut.txt`): two `sweepDoc` loops on `span.platform-module_word...sweep-module_sw` and `...platform-module`, both in the viewport,
  0 running out of the viewport. Everything else is parked, paused or finished.
- The same arm and load reads 100 when every document animation is paused (paused stage), so the 200 minus 100 is held by animations that play. The census lists only those 2 loops (INFERRED: they are the holder; this run has no arm
  that removes only them).
- Why they cost a recalc per frame: the sweep animates `background-position` with `background-clip:text`; WebKit gives `background-position` no accelerated animation wrapper (`Source/WebCore/css/CSSProperties.json` at 862f17d, cited in
  `apps/site/src/parts/platform.sweep/part.json` `layer-sweep` webkit field), so each frame restyles the word (INFERRED).
- Candidate: `platform.sweep:layer-sweep` (`apps/site/src/parts/platform.sweep/part.json:22`): a child layer with the same gradient, translated under a static text mask, so the animation is composited (transform). It is class L, a look change for the user's
  visual review, never into a preset. SPEC ONLY here; not measured on the Simulator.

## 6. Finding: the floor of `both` with everything paused is 100, not 0

Paused `both` keeps one recalc per frame with 0 scheduled (`table.txt:10`): the unscheduled per-frame recalc left open in `10-31-sim-floor-attrib.md` is still the floor under all flags (INFERRED: one recalc per rAF frame the harness itself causes, unmeasured here).
So 100 per 100 is the best any flag set reaches on this Simulator; the live target of 100 needs the in-view sweep loops off the main thread.

## 7. Accepted limits

- Simulator only, not the phone; 3 jobs x 1 round; the in-view sweep loops may run; attribution of the remaining source is INFERRED from the census owner list.
- `platform:faded-pause` is absent from `pauses` and `both` (conflict); sim-floor-attrib measured it as noEffect (INFERRED to carry over).
- No flag or preset change. Gate: none (measurement task).
