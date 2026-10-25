# toolbar-sim-lane handoff
Branch worktree-wf_bf9846c7-37b-1, worktree .claude/worktrees/wf_bf9846c7-37b-1, last commit eb755ffb4 (CI branch ci/toolbar-sim-lane, same sha).
CI runs (toolbar-throttle.yml, 10 jobs, push 1 of 3): 40236328441 queued.
Verified: package tests 862 pass, ci-paths test 56 pass; Lean MorphEndCount builds, golden regenerated (106 lines, --check ok). check.sh run pending.
Open: CI result of run 1; top-ups (push 2/3) with `[toolbar-top:N] [toolbar-plan:a+b,...]` for arms with < 3 usable passes beside a same-job default; note research/notes/2026/10-2x-toolbar-sim-lane.md; ledger entry; merge main, plan lint, dry land, review ready.

## State
- Lean: lean/Fw/Measure/MorphEndCount.lean has the toolbar reducers (stepFrames/stepGaps/stepsLifted, perGesture, onsetFrames, refreshHz/foldOf, tbPass, sameLook, armVerdict/flagVerdict, enters, winPhase) with theorems; golden kinds tb-steps, tb-gestures, tb-onsets, tb-pass, tb-verdict, tb-hz, tb-win in packages/contracts/golden/device/morph-end-count.jsonl. MorphMountToolbar.lean gained unthrottle_costs_twelve_fold_120hz.
- TS twin: packages/measure-webkit/src/throttle/toolbar.mjs; glue toolbar-page.mjs (recorder + gesture index), toolbar-probe.mjs (pass + bounded Timeline window), toolbar-plan.mjs, toolbar-cli.mjs, toolbar-report.mjs; test/throttle-toolbar.test.mjs replays the golden.
- Workflow: `[throttle:toolbar]` mode in toolbar-throttle.yml (matrix, MODE, step, report). Out files `out/<vm>-throttle.json`.

## Conventions and limits
- Timeline is NOT run over the whole touch pass: a touch window of minutes held 20-40k records and its stop timed out (research/notes/2026/10-2x-sim-touch-reliable.md). One window of gesture 4 only (Lean winPhase, closed at gesture 5 or 10 s). Layout/RecalcStyle per frame comes from that window.
- Look-change arms (touch-first, open-once, overscroll-lock) are measured for the user's review, never enter a preset (enters). part.json untouched: promotion is a follow-up.
- Same look is judged on the morph state trace (peak floor, gestures with an onset, settled), not pixels.
- Lost VMs are named failures; run id and job number in the note.

## Read first
Lean block "stepFramesFrom" in MorphEndCount.lean, then toolbar-probe.mjs windowWatcher, then toolbar-report.mjs.
