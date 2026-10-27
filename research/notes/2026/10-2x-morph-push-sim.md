# morph-push-sim: the end-of-page push on the WebKit Simulator (real XCUITest swipes, Web Inspector timeline)

Question: do morph.geom:on and morph.geom:on + morph.tween:geom-timed change the main-thread work between a push and the
morph end (680 ms) on Mobile Safari in the Simulator, and does geom-timed run with no morph style, layout, paint or rAF?
The webkit-sim counts profile sends no touch, so there the arms were equal by construction (morph-timed note).

Result: **undecided for every arm against base** (base has 1 usable VM, minVms is 3). Four CI pushes were used (the limit);
three lost most passes to the macOS VMs and to a harness hang that is now fixed. The key check is not delivered as a
verdict, and the one VM that ran geom-timed does not show a quiet window (below).

## Lean (CONFIRMED, lean/Fw/Measure/PushCycle.lean, golden packages/contracts/golden/measure/push-cycle.jsonl)
- Window of one push: from `pushLeadMs` 17 ms before the first recorder frame that sees the morph to `pushMs` 680
  (= `Fw.Parts.MorphTween.duration`) plus `pushTailMs` 100; `inWin`, `windows` (only windows inside the recording), slow frame
  = frame gap over `slowMs` 34.
- `armVerdict base arm`: `undecided:fewBase`, then `undecided:fewArm` (a VM counts with at least `minWins` 3 windows, 3 VMs
  needed), else the Offscreen spread rule on the per-VM mean counts x 1000 (style, layout, paint, rAF, slow): any counter
  above base is noGain, otherwise any below is gain. Proved: the branch theorems and `quietVerdict_sound`.
- `quietVerdict p vs` for the key check: `quiet` only if every window of every usable VM has style, layout, paint and
  page-rAF all 0 (`PushWin.quiet`), also `rafFree` alone; under 3 VMs `undecided`.
- TS twin packages/measure-webkit/src/throttle/morph-push.mjs, tested against the golden (test/morph-push.test.mjs).

## Lane (TS glue, MEASURED that it works on 2 of 3 VMs in the last run)
Push-cycle lane, profile `push`: the FinishServer XCUITest run, one cycle asked at a time; a Web Inspector timeline per
cycle; the page stamps `performance.mark('fwpc:<ms>')` every 500 ms so the timeline seconds map to page ms without a host
call (sync drift of the first and last stamp: -1 to 1 ms in run 40493131946). Page rAF is counted by wrapping
`requestAnimationFrame` and skipping the recorder's own callback. Arms: `[throttle:push-cycle-morph:all]` runs base,
morph.geom:on and morph.geom:on,morph.tween:geom-timed in turn in each of 3 jobs, rotated by the job, 6 cycles each.

## Runs (MEASURED)
| push | run | what | outcome |
|---|---|---|---|
| 1 | toolbar-throttle 40465591949 | base, one timeline over the whole pass (8 cycles) | 0 passes in 3 jobs: the VMs stalled (page unreachable, or Runtime.evaluate timeout 120 s after the touches) |
| 2 | 40470960001 | base, one timeline per cycle, host sync mark | 0 passes in 3 jobs: Runtime.evaluate timeout 120 s right after cycle 1 (VM1 got 4 pushes, then the VM froze 1615 s) |
| 3 | 40479824329 | all arms, same code | geom 1 pass in each of jobs 2 and 3 (6 pushes each); every base and timed pass and all of job 1 lost to the same hang |
| 4 | 40493131946 | all arms, page-side stamps, no host evaluate in a cycle | job 2: geom, timed and base, 6 pushes each; job 3: geom (6), timed restartFailed, base notReady; job 1: no pass (push server never ready, simctl ETIMEDOUT) until the job cap |

Pooled (results/morph-push-sim/pooled.md; a VM is one job of one run; results/morph-push-sim/run-*-passes.json hold the
rows):

| arm | VMs with >= 3 windows | windows | mean style / layout / paint / page rAF / slow per window |
|---|---|---|---|
| base | 1 (run 4 job 2) | 6 | 12.5 / 10.7 / 107.3 / 3 / 2 |
| geom | 4 (runs 3 and 4, jobs 2 and 3) | 6 each | style 9.5 to 29.8, layout 8 to 27.5, paint 104.7 to 123.7, rAF 2.7 to 4, slow 1.3 to 3.3 |
| geom-timed | 1 (run 4 job 2) | 6 | 40.5 / 37.7 / 139 / 6.3 / 7.3 |

## Verdicts at minVms 3 (pinned unit: one arm against base, per-push window, real swipes)
| arm | verdict | n and loss cause |
|---|---|---|
| morph.geom:on vs base | undecided:fewBase | geom 4 VMs, base 1: base lost in run 3 (3 of 3), run 4 (job 1 stall, job 3 notReady) |
| morph.geom:on + geom-timed vs base | undecided:fewBase | timed 1 VM, base 1 |
| key check, geom-timed quiet | undecided (1 VM) | see below |

## Key check, geom-timed (MEASURED on 1 VM, so undecided in Lean)
- The 6 windows of run 4 job 2 are not quiet: style 40.5, layout 37.7, paint 139, page rAF 6.3 per window, more than base
  (12.5, 10.7, 107.3, 3) and more than geom in the same job (29.8, 27.5, 123.7, 4). Rows are spread over the whole 780 ms
  window, not only at the start.
- INFERRED, not separated: the recording itself adds style and layout work (the recorder reads the morph property every
  frame, the 500 ms stamp timer fires), real swipes also move the toolbar and the visual viewport, and the base arm shows
  26 style rows (summed over its 6 windows) in the first 100 ms and some in every later bin. The window cannot tell a morph row from these.
  So "no morph style, layout, paint or rAF" is neither shown nor refuted on the Simulator; the Chromium reading of the
  morph-timed note (Paint, RasterTask, FireAnimationFrame fall) stands as the only evidence of fewer frames.
- Note the page rAF requests: base 3, geom 2.7 to 4, timed 6.3 per window: the geom-timed page still requests frames.
  INFERRED source: the site's other rAF users and the recorder-side wrapper edge cases; not traced.

## What the lane lost, and why (for the next try)
- Whole-pass timeline: floods the inspector on the VM (push 1).
- A host `Runtime.evaluate` right after a cycle under a running timeline hangs for 120 s on many VMs (pushes 2 and 3);
  the fix (no host call inside a cycle, stamps from the page) delivered passes in 2 of 3 jobs. INFERRED: the page is
  suspended or lost while Safari is not in front after the swipe sequence; not shown.
- macOS VMs: simctl ETIMEDOUT, push server never ready (420 s), restarts of 4 to 8 minutes. One job in four (run 4 job 1)
  never ran a pass.
- Each pass needs 3 usable base VMs: with this loss rate (about 1 usable pass in 3) 9 VMs per arm in 3 pushes would be needed.

## TS stand-ins and limits
- TS stand-ins: the lane glue (pass loop, timeline segments, stamp timer, rAF wrapper, report table) is I/O and carries no
  decision logic; the verdict and the window rules are the Lean ones through the golden. The timeline-to-page-ms mapping
  (`pageMs`, `stampSync`) is TS with unit tests, no Lean spec.
- Class L arms stay the user's visual review. Toolbar throttle and pin fight are measured as they are, not fixed. No phone run.
