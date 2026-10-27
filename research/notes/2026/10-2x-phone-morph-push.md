# Phone morph push at the end of the page (round 2: Lean rule done, phone run blocked)

Question: on the real iPhone (WebKit), at the end of the page, do the morph arms change the lag during real pushes?
Arms: base, morph.geom:on, morph.geom:on + morph.tween:geom-timed, morph.stage:on; end segment only; one thermal state (Serious).

## Result (MEASURED, 2026-10-27)
- Verdict: undecided. n = 0 visits per arm. The Lean rule needs at least 3 interleaved visits per arm, so every arm is `unresolved`.
- Loss: the XCUITest push driver builds and signs for the phone (17 s), starts on the phone after the certificate trust, and
  then waits forever at the first accessibility snapshot. Three runs: Safari (pid 2845, a Safari restarted by devicectl, pid 3365)
  and a variant that asks SpringBoard (pid 37) for the screen height instead of Safari. None returned in 4 to 7 minutes
  (`xcodebuild` log: `Requesting snapshot of accessibility hierarchy for app with pid N`, the last line each time). The phone stayed
  unlocked, Nominal, charging; the thermal tool read it between the runs. No condition was induced, nothing needs clearing.
- The raw logs are in `.local/phone/2026-10-27/` (gitignored).
- The push is a fixed XCUITest swipe (forward, hold, back, hold, forward), not the user's recorded finger path. This stays true
  for any later run through this driver.

## Cause (INFERRED)
A hang on SpringBoard as well as Safari points at the phone's automation switch, not at a page. Next step for the user: Settings >
Developer > Enable UI Automation (and keep the phone unlocked). If it is already on, the next suspect is the iOS 27 beta UI
automation stack; then a WebDriverAgent-style driver is the other route (none is built here).

## What was built (CONFIRMED in code)
- `lean/Fw/Device/PhoneArms.lean` push-visit section, golden `packages/contracts/golden/device/phone-arms.jsonl`, twin
  `packages/measure-webkit/src/device-push.mjs`, test `test/device-push.test.mjs` (8 tests on the golden).
- Visit: forward push, hold, back, hold, forward again (`pattern`, 2 asks), then a back-to-back worst case of 3 extra asks with no
  rest between pushes (`burstAsks`); 10 pushes counted per visit (`pushes`).
- Visit count: `minVisits` = 3 per arm (PhoneArms `visitMin` is minutes per visit, not a count); `pushRounds` interleaves the 4 arms
  three times (12 visits), `noRepeat` forbids the same arm twice in a row, `pushOk` checks the count.
- Per-arm columns (`columns`): p95, p99, max, frames over 50 ms from the frames lane; style, layout, paint and rAF counts between
  the push and the morph end from the counts lane. The two lanes run in separate passes: the counts lane has no rAF recorder (so
  the page's own FireAnimationFrame count is not perturbed) and takes its span lengths from the frames lane (`shifted`, clock offset
  from the wk:a/wk:b marks). Morph end counts running animations too, because geom-timed writes nothing per frame.
- The verdict (`pushLabel`) is `armLabel` over those columns against base; fewer than 3 visits on either side is `unresolved`.

## Follow-ups (below the pinned unit)
- Wire the run (a push visit in `runBlock`, deps.visit) once a driver answers; the pure parts above are ready.
- Class L arms (geom-timed) stay the user's visual review; the felt-smoothness verdict is the user's.
