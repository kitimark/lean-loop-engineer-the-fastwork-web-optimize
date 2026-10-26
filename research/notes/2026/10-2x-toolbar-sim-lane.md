---
id: 2026-10-2x-toolbar-sim-lane
kind: note
title: "Toolbar lane on the Simulator (real touch swipes): unthrottle lifts the 10 Hz toolbar steps to per frame (undecided, cost not measured; enters a preset: no), the other flags keep them throttled"
status: review
created: 2026-10-26
topics: [toolbar, unthrottle, simulator, webkit, touch, ci, morph]
---

# Toolbar lane on the Simulator (real touch swipes)

## Answer
- MEASURED (Simulator on GitHub macOS, Mac GPU, not the iPhone): with real touch drags past the page end, the `visualViewport.height` steps of the default arrive about 95 ms apart (the 100 ms visible-rect throttle, `WKWebViewIOS.mm:143` and `:3256-3268`@862f17d). `engine.scroll:unthrottle` brings them to about 50 ms (about 1.5 frame gaps; frames are about 34 ms apart), past the midpoint between per-frame and the 100 ms throttle that Lean stepsLifted uses. Idle requestAnimationFrame cadence is 32 to 38 Hz on the VM (MEASURED); frame gaps under touch are 32 to 38 ms (26 to 31 Hz).
- Verdict by the Lean rule (`Fw.Measure.MorphEndCount.flagVerdict`): engine.scroll:unthrottle undecided (cost not measured; enters a preset: no): its cadence is lifted and no state column is worse, but no default pass beside it holds a cost window, and a win needs at least 3 cost windows on each side. touch-first, open-once, overscroll-lock and threaded no-win. Look-change arms (touch-first, open-once, overscroll-lock) never enter a preset whatever the verdict.
- The touch script opens the morph once per cycle in every arm (4 opens in 12 gestures), so closes, re-opens and fade onsets per gesture are 0.33, 0.25 and 0.33 for every arm: this lane cannot show a flag that removes re-opens. Reversals per gesture overlap between every flag and the default.
- Layout and RecalculateStyles per frame are not judged here: they move to task toolbar-cost-sample (section "Not measured here"). The model says 3x the updates at the idle rAF cadence seen here (6x at 60 Hz, 12x at 120 Hz, Lean `unthrottle_costs_twelve_fold_120hz`); that fold is derived from the cadence, not measured.
- Round 1 called unthrottle a win from missing data: its jobs held 0 default passes with a whole cost window, `TouchLock.cmp_empty_faith` makes `cmp [] cand` overlap, so Layout and RecalcStyle counted as not higher. The cost-evidence rule (`costKnown`, theorem `unthrottle_no_cost_undecided`) closes that.

## Pinned unit and what was delivered
Per arm at least 3 passes beside a same-job default: usable passes pooled over three pushes (the non-cost metrics come from the same reducers; push 3 adds per-frame and per-touchstart console.timeStamp stamps and a different Timeline window, so each flag arm is compared only with default passes of its own job).

| arm | usable passes | default passes beside them |
|---|---|---|
| touch-first | 7 | 7 |
| open-once | 6 | 6 |
| unthrottle | 5 | 4 |
| overscroll-lock | 6 | 5 |
| threaded | 6 | 5 |
| default | 14 | |

Cost windows are not part of this unit (see "Not measured here").

## Tables (pooled, tool output of `toolbar-cli.mjs report`)

| arm | passes (usable) | passes with a toolbar move | vh steps | steps per pass | median step gap ms | median frame gap ms | step cadence | vh range px |
|---|---|---|---|---|---|---|---|---|
| default | 15 (14) | 14 | 561 | 40.1 | 95.0 | 35.0 | throttled | 775.0 to 815.0 |
| touch-first | 8 (7) | 7 | 319 | 45.6 | 87.0 | 33.0 | throttled | 775.0 to 815.0 |
| open-once | 6 (6) | 6 | 263 | 43.8 | 96.0 | 38.0 | throttled | 775.0 to 815.0 |
| unthrottle | 6 (5) | 5 | 299 | 59.8 | 50.0 | 34.0 | per frame | 775.0 to 815.0 |
| overscroll-lock | 6 (6) | 6 | 274 | 45.7 | 98.0 | 32.0 | throttled | 775.0 to 815.0 |
| threaded | 7 (6) | 6 | 252 | 42.0 | 97.0 | 35.0 | throttled | 775.0 to 815.0 |

| arm | gestures | reversals per gesture | closes per gesture | re-opens per gesture | fade onsets per gesture | gestures with an onset | lowest peak (of 1000) | passes open at the end |
|---|---|---|---|---|---|---|---|---|
| default | 168 | 1.12 | 0.33 | 0.24 | 0.33 | 55 / 168 | 1000 | 0 |
| touch-first | 84 | 1.67 | 0.33 | 0.25 | 0.33 | 28 / 84 | 1000 | 0 |
| open-once | 72 | 1.18 | 0.33 | 0.25 | 0.33 | 24 / 72 | 1000 | 0 |
| unthrottle | 60 | 1.33 | 0.33 | 0.25 | 0.33 | 20 / 60 | 1000 | 0 |
| overscroll-lock | 72 | 1.57 | 0.33 | 0.25 | 0.33 | 24 / 72 | 1000 | 0 |
| threaded | 72 | 1.17 | 0.33 | 0.25 | 0.33 | 24 / 72 | 1000 | 0 |

| flag | class | usable passes | default passes beside them | jobs | reversals | re-opens | onsets | step cadence lifted | state-trace floor holds | verdict | enters a preset |
|---|---|---|---|---|---|---|---|---|---|---|---|
| morph.mount:touch-first | look-change (L) | 7 | 7 | 7 | overlap | overlap | overlap | no | yes | no-win | no |
| morph.mount:open-once | look-change (L) | 6 | 6 | 6 | overlap | overlap | overlap | no | yes | no-win | no |
| engine.scroll:unthrottle | plain | 5 | 4 | 5 | overlap | overlap | overlap | yes | yes | undecided (cost not measured) | no |
| morph.mount:overscroll-lock | look-change (L) | 6 | 5 | 6 | overlap | overlap | overlap | no | yes | no-win | no |
| morph.panel:threaded | plain | 6 | 5 | 6 | overlap | overlap | overlap | no | yes | no-win | no |

This check does not detect touch-first's designed change of the first push; look-change arms still need the user's visual review.

## Not measured here (task toolbar-cost-sample)
Layout and RecalculateStyles per frame need at least 3 whole gesture-4 cost windows on each side (Lean `minCostWindows`); the windows that exist are below that, so no verdict reads them. Counts from `toolbar-cli.mjs report`, for the record:

| arm | passes with a whole gesture-4 window | windows without both gesture stamps (left out) | frames in the windows | Layout per frame | RecalcStyle per frame | idle requestAnimationFrame Hz (median of passes) | cost fold derived from that cadence |
|---|---|---|---|---|---|---|---|
| default | 2 | 3 | 326 | 2.040 | 2.929 | 32 | 3x |
| touch-first | 4 | 1 | 781 | 1.956 | 2.753 | 38 | 3x |
| open-once | 2 | 2 | 344 | 1.910 | 2.814 | 34 | 3x |
| unthrottle | 2 | 1 | 331 | 2.166 | 2.924 | 32 | 3x |
| overscroll-lock | 2 | 1 | 375 | 1.723 | 2.701 | 36 | 3x |
| threaded | 2 | 1 | 367 | 1.975 | 2.771 | 37 | 3x |

| flag | cost windows (default / flag) | Layout vs default | RecalcStyle vs default |
|---|---|---|---|
| morph.mount:touch-first | 2 / 4 | not read | not read |
| morph.mount:open-once | 1 / 2 | not read | not read |
| engine.scroll:unthrottle | 0 / 2 | not read | not read |
| morph.mount:overscroll-lock | 0 / 2 | not read | not read |
| morph.panel:threaded | 1 / 2 | not read | not read |

Windows per arm are counted against the default passes of the same jobs. The measurement (at least 3 same-job windows per arm, a new push budget) is task toolbar-cost-sample.

## Runs
Conclusions are cancelled, cancelled, failure; completed passes are used.
- Push 1, run 40236328441 (eb755ffb4), cancelled: sim (1) to (5) success; sim (6) to (10) cancelled by me once the cost window overran (spans 73 to 157 s). A fixed 50 ms lifted rule called per-frame steps throttled (frames are 30 to 65 ms apart); replaced by a rule relative to the frame gap.
- Push 2, run 40250249829 (86646a00d), cancelled: sim (1) to (3) success; sim (4) to (10) cancelled by me: Timeline start took 8 to 28 s and stop 13 to 51 s under touch, so polling could not cut the window, and Timeline has no RenderingFrame records.
- Push 3, run 40257287239 (02d957418), failure: sim (1) to (3) and (5) to (10) success. sim (4) failed in the touch step with no log and no artifact after 75 min: a lost VM, a named failure, not rerun (push budget used). The cost window is cut by page stamps `tbg<n>` (touchstart n) and `tbf` (frame); Lean `windowCost` counts only between the stamps of gestures 4 and 5.
- Passes that failed inside jobs (restarts, touchesFailed, Timeline.stop timeouts of 120 s) are in each job's `failed` list and are not counted.
- Report input labels r1jN, r2jN, r3jN are job N of push 1, 2, 3; each flag arm is compared with the default passes of its own jobs.

## Method and limits
- Lean first: `lean/Fw/Measure/MorphEndCount.lean` (steps, burst gaps, median, lifted against the frame gap, gestures, onsets, refresh Hz and fold, sameLook, armVerdict, costKnown, flagVerdict with the verdict `undecided`, winPhase, windowCost) with 126 golden lines in `packages/contracts/golden/device/morph-end-count.jsonl`, replayed by `packages/measure-webkit/test/throttle-toolbar.test.mjs`. TS stand-ins: page scripts, the window watcher and the CLI glue (unproved I/O).
- The state-trace floor (peak floor, gestures with an onset, settled) is judged on the morph state trace, not on pixels, so it does not detect touch-first's designed change of the first push.
- One Timeline window per pass perturbs the cadence of all arms equally; a whole-pass Timeline is not used (it stalls, `10-2x-sim-touch-reliable.md`).
- CI only; the phone pass belongs to phone-compose-counts. The cost measurement, any promotion of unthrottle in `part.json` and the `research/findings/ledger.json` row are follow-ups (cost: task toolbar-cost-sample). A look-change arm is never promoted.
