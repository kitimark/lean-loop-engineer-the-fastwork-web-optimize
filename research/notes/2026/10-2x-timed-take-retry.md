# timed-take-retry: the timed take is retried per frame (probe note A5)

Task timed-take-retry (graph r536). Cause CONFIRMED earlier (10-27-end-columns-probe.md A5): `take()` was decided once at push start by
`is-on-dark`; light at that instant meant the whole push and the pull-out ran the faithful per-frame tween (valid look, laggy).

## What changed
- Lean `Fw.Parts.MorphGeomTimed` (lean/Fw/Parts/MorphGeomTimed.lean, end of file): `takeOk` (direction-free), the retry machine
  `stepTake`/`scanTake`, `takeFrame`; theorems `take_at_first_dark`, `take_entered`, `take_never` (one per branch), `scanTake_taken`
  (no fallback once taken), `firstFrom_stable` (a longer window keeps the frame), `switch_jump_zero` (CONFIRMED: shown value after the
  switch equals the faithful frame value exactly, so the "existing bound" is not needed: jump 0, because the set keeps `s.start`).
- Golden: 7 `take` scenarios in packages/contracts/golden/morph-geom-timed.jsonl (light at start then dark at 3, close from rest, close
  after open, reversal while pending, reversal after take, dark at start, never dark). The faithful reversal starts from the last tick
  value (Lean `startValue`), the timed one from the event-time value.
- TS: `geom-timed.driver.ts` no longer refuses `to < from`; `driver.ts` tick retries `startTimed()` while pending (one extra
  `allowed()` read per frame until taken), then drops its frame subscription. Replay: `geom-timed.take.golden.test.ts` (all 7 equal).
- Opt-in probe hook `TweenEnv.trace` (push and take events, wired to `window.__fwTakeTrace` for geom-timed only).
- The "m > 0.2" escape of the task text is not used: the scroll-driven geom driver only tests `m > 0` plus `allowed()`
  (morph.geom/driver.ts:25), so no 0.2 rule exists to copy; a take with a light nav would also show the dark-nav geometry.

## INFERRED point (settle(m>0) drops tracks without goal rules): false
Panel effects (driver.ts createPanelEffects.settle) drop at the end, but the panel reads `--morph` from CSS (morph.panel/morph.module.css:9-13)
and `mark`/`tick` publish the final value in the same task as the settle, so no frame shows the dropped state. The timed geometry keeps
its goal rules until `leave` (settle(m>0) only drops animations): tested in geom-timed.driver.test.ts ("settle at 1").

## Measured (local debug runs, not results)
Chromium, swipe-touch-v1 strokes (10 css px per 16 ms, y 880 to 100) sent by CDP touch to the page end, then a tail and two pull-outs
(results/timed-take-retry/pushlog.mjs; logs pushlog-before.json, pushlog-after.json). takeFrameMs = ms into the push when the timed
tracks were taken. Differs from the profile: dpr 1, start 2.5 viewports above the end, wall-clock pacing, two added pull-outs,
one run with 2 pushes per width.

| width | before (no retry) | after |
|---|---|---|
| 390 | open: fell back (null); close 20 | open 119; close 10 |
| 430 | not run | open 14; close 8 |
| 1280 | open 20; close 13 | open 16; close 13 |

Every push takes the timed path at all three widths. The 119 ms at 390 is the retry (the hit test read light at
the push and dark a few frames later). Why the test reads light at 390 in Chromium but dark in WebKit stays open.

## Measured on CI (round 2)
Branch ci/timed-take-retry at 8e667f5ab.

| item | run | result |
|---|---|---|
| breakpoint gate, both engines, morph.geom:on,morph.tween:geom-timed | 40503716001 | success (chromium j0-j2, playwright-webkit j0-j3) |
| Chromium swipe-touch-v1 x3, rewrite base | 40503734787 | filed |
| same with the flags | 40503729708 | filed |

Lean OffscreenWindows reader (results/timed-take-retry/chromium-windows.md): end frame 574 in base and flag; every window noGain.
The flag arm counts fewer LayoutCount, Paint, RasterTask in the end windows, but RecalcStyleCount is higher (43 to 51), and end 60-119 has more Paint
(120 to 151), so no window gains. This matches the earlier morph-timed result (runs 40454388920 vs 40454426552): the take retry changes which path runs
(every push now takes the timed path), not the counted cost. The count arms do not show the per-push take; the local push log above does.

## Not delivered here
Phone run (accepted limit). The per-push take log is a local CDP-touch approximation, not a CI result.
