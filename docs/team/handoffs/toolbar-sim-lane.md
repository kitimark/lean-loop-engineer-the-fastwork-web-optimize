# toolbar-sim-lane handoff
Branch worktree-wf_bf9846c7-37b-1, worktree .claude/worktrees/wf_bf9846c7-37b-1, CI branch ci/toolbar-sim-lane at 86646a00d (push 2 of 3, marker commit).
CI runs (toolbar-throttle.yml): 40236328441 push 1 at eb755ffb4, jobs 1-5 success, I cancelled it (jobs 6-10 would repeat the cost windows with the flawed code); 40250249829 push 2 queued, 10 jobs.
Verified: package tests 864 pass; Lean MorphEndCount builds, golden 117 lines --check ok; check.sh green at the push-1 tree (rerun at the end).
Open: wait for run 40250249829 (`pnpm -s fw ci wait --branch ci/toolbar-sim-lane --workflow toolbar-throttle`, foreground, <= 590 s per call); download `gh run download <id> -p 'toolbar-throttle-*'`; reduce with toolbar-cli.mjs report over run-1 jobs 1-5 plus run-2 jobs; top up (push 3) with `[ci:toolbar-throttle] [throttle:toolbar] [toolbar-top:N] [toolbar-plan:a+b,...]` in the head commit; note research/notes/2026/10-2x-toolbar-sim-lane.md; ledger entry; merge main, plan lint, dry land, review ready.

## What run 1 showed (drove the push-2 fixes)
- Simulator frames are 30-65 ms apart during touches, so Lean's fixed 50 ms "lifted" rule called a per-frame cadence throttled: stepsLifted now takes the median frame gap (lifted iff 2 * median step gap < frame gap + 100 ms). unthrottle: step gap 43-59 ms at frame 32-42 ms; default 83-122 ms.
- Timeline windows overran: spans of 73-157 s, g1 = 12, and a frame denominator that included the start latency. Lean winCounts leaves out windows past gesture 5 or 20 s; frames are now the window's RenderingFrame records. Cost columns of run 1 are not usable.
- Failures in run 1: job 3 default and touch-first (done without a record / touchesFailed), job 4 unthrottle Timeline.stop timed out 120 s, job 5 threaded touchesFailed.

## State
- Lean: lean/Fw/Measure/MorphEndCount.lean Tb block (stepsLifted frame gaps, frameGapCs, tbPass.frameCs, winPhase, winCounts, armVerdict, flagVerdict); golden kinds tb-steps, tb-gestures, tb-onsets, tb-pass, tb-verdict, tb-hz, tb-win, tb-wincount in packages/contracts/golden/device/morph-end-count.jsonl (regenerate: `lake build Fw.Measure.MorphEndCount` first, then `lake env lean --run scripts/MorphEndCountGolden.lean`).
- TS twin: packages/measure-webkit/src/throttle/toolbar.mjs; glue toolbar-page.mjs, toolbar-probe.mjs (windowWatcher), toolbar-plan.mjs, toolbar-cli.mjs, toolbar-report.mjs; test/throttle-toolbar.test.mjs replays the golden.
- Workflow: `[throttle:toolbar]` mode in toolbar-throttle.yml; out files `out/<vm>-throttle.json`.

## Conventions and limits
- One Timeline window per pass, opened at gesture 4, closed at gesture 5 or 10 s; counted only if lean winCounts holds. Layout/RecalcStyle per RenderingFrame.
- Look-change arms (touch-first, open-once, overscroll-lock) never enter a preset; part.json untouched (promotion is a follow-up).
- Same look is judged on the morph state trace, not pixels.
- Lost VMs are named failures with run id and job number.
