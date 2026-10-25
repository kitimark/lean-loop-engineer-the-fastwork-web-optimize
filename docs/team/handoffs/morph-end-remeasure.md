branch: worktree-wf_1025224f-bba-1 (CI branch ci/morph-end-remeasure, 3 pushes used of 3; no more pushes)
worktree: .claude/worktrees/wf_1025224f-bba-1
last commit: 9e681f4eb (the push-3 commit; CI branch ci/morph-end-remeasure is at the same sha)
CI runs: push 1 (067846590): toolbar-throttle 40158609202 FAILED (all 4 six-arm jobs lost; partial artifacts of jobs 1, 2 pooled), smoothness touch-lock 40158609210 success (results/morph-end-remeasure/touch-lock-run-40158609210.md), lean 40158609183 failure (init cost 1640; fixed b653fff4e). Push 2 (ba761c109): toolbar-throttle 40167641467 finished (jobs 1,3-8,10 success, job 2 failed at 90 min, job 9 cancelled but its artifact exists), lean 40167641470 success. Push 3 (9e681f4eb): toolbar-throttle 40193540518 RUNNING at fresh-builder start (sim 1, 3 lost 'runner lost communication' at 94 and 104 min; sim 2 exit 130 watchdog; sim 4,5,6,7 success; 8 running; 9, 10 queued, at 17:40 UTC), lean 40193540707 queued.
verified: local check.sh green; measure-webkit 721 tests; ci-paths 56; runner land-inputs + overflow-widths 80 (max-parallel 3 after the widths test named 4); fw plan lint: no writesClosure line for this task
open: pool run 40193540518 into scratchpad/mer/pool (relabel job vm: node-free script scratchpad/mer/relabel.py), regenerate results tables, write research/notes/2026/10-2x-morph-end-remeasure.md, dry land, review ready
results so far: results/morph-end-remeasure/ (pooled tables of runs 40158609202 and 40167641467, pins.md, touch-lock table)

State and conventions
- Lean: lean/Fw/Measure/MorphEndCount.lean (event counting by finger direction, spring-back fight, brick verdict, golden generator); golden packages/contracts/golden/device/morph-end-count.jsonl; check.sh job "morph-end-count golden check"; Trigger rows for lean.yml and toolbar-throttle.yml.
- TS twin: packages/measure-webkit/src/throttle/morph-end.mjs (golden replayed by test/throttle-morph-end.test.mjs); report morph-end-report.mjs (brickRow, three tables).
- Workflow: toolbar-throttle.yml morph-end matrix [1..10], three arms per job (rewrite first, then two compositions taken in turn from flip release all all-unthrottle in push 3, from clamp flip release all all-unthrottle in push 2), 4 cycles, rotate 0, max-parallel 3 (the Lean widths table).
- "release" and "release with the hold rule on main" are the same page: the held bit lives in end.logic.ts release.
- Touch-push lane: only the smoothness [touch-lock] job exists (arms orig/base/lock in src/touchlock-cli.mjs, outside this task's writes); run as-is as the lane reference.
- TS stand-ins left: faithful-passes-in-same-jobs selection (brickRow) and report glue.
- Read first: lean/Fw/Measure/MorphEndCount.lean, packages/measure-webkit/src/throttle/morph-end.mjs, research/notes/2026/10-2x-morph-end-measure.md
