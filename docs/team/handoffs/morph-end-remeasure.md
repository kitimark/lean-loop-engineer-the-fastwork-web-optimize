branch: worktree-wf_1025224f-bba-1 (CI branch ci/morph-end-remeasure, 3 pushes used of 3; no more pushes)
worktree: .claude/worktrees/wf_1025224f-bba-1
last commit: see git log (note and pooled tables committed after run 40193540518)
CI runs: push 1 (067846590): toolbar-throttle 40158609202 FAILED (4 six-arm jobs lost; jobs 1, 2 partial), smoothness touch-lock 40158609210 success, lean 40158609183 failure (fixed b653fff4e). Push 2 (ba761c109): toolbar-throttle 40167641467 finished (job 2 failed 90 min, job 9 cancelled, artifact kept), lean 40167641470 success. Push 3 (9e681f4eb): toolbar-throttle 40193540518 COMPLETE failure (sim 1, 3, 10 lost runner 94, 104, 80 min, sim 2 exit 130, sims 4-9 success), lean 40193540707 success.
verified: pooled all three runs (scratchpad/mer/pool3, relabel.py c-prefix); results/morph-end-remeasure/ has pooled-runs-...-40193540518.md, run-40193540518.md, pins.md; note research/notes/2026/10-2x-morph-end-remeasure.md written (verdicts clamp no-win, flip no-win, release/all/all+unthrottle win on first stretch only).
done: main merged (Trigger.lean, check.sh, triggers.jsonl regenerated from Lean), tests green (measure-webkit 840, ci-paths 56, runner 3575), check.sh green, dry VERDICT dry morph-end-remeasure, review ready VERDICT review-ready.
open: lead lands; phone step for release second-cycle re-open; macos-vm-evidence owns lost-VM evidence

State and conventions
- Lean: lean/Fw/Measure/MorphEndCount.lean (event counting by finger direction, spring-back fight, brick verdict, golden generator); golden packages/contracts/golden/device/morph-end-count.jsonl; check.sh job "morph-end-count golden check"; Trigger rows for lean.yml and toolbar-throttle.yml.
- TS twin: packages/measure-webkit/src/throttle/morph-end.mjs (golden replayed by test/throttle-morph-end.test.mjs); report morph-end-report.mjs (brickRow, three tables).
- Workflow: toolbar-throttle.yml morph-end matrix [1..10], three arms per job (rewrite first, then two compositions taken in turn from flip release all all-unthrottle in push 3, from clamp flip release all all-unthrottle in push 2), 4 cycles, rotate 0, max-parallel 3 (the Lean widths table).
- "release" and "release with the hold rule on main" are the same page: the held bit lives in end.logic.ts release.
- Touch-push lane: only the smoothness [touch-lock] job exists (arms orig/base/lock in src/touchlock-cli.mjs, outside this task's writes); run as-is as the lane reference.
- TS stand-ins left: faithful-passes-in-same-jobs selection (brickRow) and report glue.
- Read first: lean/Fw/Measure/MorphEndCount.lean, packages/measure-webkit/src/throttle/morph-end.mjs, research/notes/2026/10-2x-morph-end-measure.md
