# toolbar-sim-lane handoff
Branch worktree-wf_bf9846c7-37b-1, worktree .claude/worktrees/wf_bf9846c7-37b-1, CI branch ci/toolbar-sim-lane at 02d957418 (push 3 of 3, the last; no top-up possible).
CI runs (toolbar-throttle.yml): 40236328441 push 1 (jobs 1-5 success, rest cancelled by me), 40250249829 push 2 (jobs 1-3 success, rest cancelled by me), 40257287239 push 3 queued, 10 jobs, new cost window.
Verified: package tests 883 pass; Lean MorphEndCount builds, golden 119 lines --check ok; check.sh green at the push-1 tree (rerun at the end); main merged, plan lint has no error for this task.
Open: wait for run 40257287239 (`pnpm -s fw ci wait 40257287239 --timeout 570`, foreground); `gh run download <id> -p 'toolbar-throttle-*'`; reduce with toolbar-cli.mjs report over run-1 jobs 1-5, run-2 jobs 1-3 and run-3 jobs (non-cost metrics pool all; cost only from run 3); note research/notes/2026/10-2x-toolbar-sim-lane.md; ledger entry; check.sh, dry land, review ready.
Scratch copies of runs 1 and 2 artifacts: scratchpad/tsl/run1, scratchpad/tsl/b1 (gitignored).

## What runs 1 and 2 showed (drove the push-2 and push-3 fixes)
- Simulator frames are 30-65 ms apart during touches, so Lean's fixed 50 ms "lifted" rule called a per-frame cadence throttled: stepsLifted now takes the median frame gap (lifted iff 2 * median step gap < frame gap + 100 ms). unthrottle: step gap 43-59 ms at frame 32-42 ms; default 83-122 ms.
- Timeline windows overran: spans of 73-157 s, g1 = 12, and a frame denominator that included the start latency. (superseded by the stamps below). Cost columns of run 1 are not usable.
- Run 2: protocol round trips under touch took 7-30 s (Timeline start 8-28 s, stop 13-51 s), the poll often first saw g > 4 (window missed), and Timeline has no RenderingFrame records (frames 0). So push 3 cuts the window by page stamps: tbg<n> at touchstart n, tbf per frame; window opens at gesture 2; Lean windowCost counts between the stamps of gestures 4 and 5.
- Failures in run 1: job 3 default and touch-first (done without a record / touchesFailed), job 4 unthrottle Timeline.stop timed out 120 s, job 5 threaded touchesFailed.

## State
- Lean: lean/Fw/Measure/MorphEndCount.lean Tb block (stepsLifted frame gaps, frameGapCs, tbPass.frameCs, winPhase, windowCost, armVerdict, flagVerdict); golden kinds tb-steps, tb-gestures, tb-onsets, tb-pass, tb-verdict, tb-hz, tb-win, tb-cost in packages/contracts/golden/device/morph-end-count.jsonl (regenerate: `lake build Fw.Measure.MorphEndCount` first, then `lake env lean --run scripts/MorphEndCountGolden.lean`).
- TS twin: packages/measure-webkit/src/throttle/toolbar.mjs; glue toolbar-page.mjs, toolbar-probe.mjs (windowWatcher), toolbar-plan.mjs, toolbar-cli.mjs, toolbar-report.mjs; test/throttle-toolbar.test.mjs replays the golden.
- Workflow: `[throttle:toolbar]` mode in toolbar-throttle.yml; out files `out/<vm>-throttle.json`.

## Conventions and limits
- One Timeline window per pass, opened at gesture 2 (cap 150 s), closed once gesture 5 began; Lean windowCost counts Layout/RecalcStyle per frame stamp only between the stamps of gestures 4 and 5.
- Look-change arms (touch-first, open-once, overscroll-lock) never enter a preset; part.json untouched (promotion is a follow-up).
- Same look is judged on the morph state trace, not pixels.
- Lost VMs are named failures with run id and job number.
