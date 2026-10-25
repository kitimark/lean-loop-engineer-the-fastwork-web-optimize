branch: worktree-wf_1025224f-bba-1 (CI branch ci/morph-end-remeasure, 2 pushes used of 3)
worktree: .claude/worktrees/wf_1025224f-bba-1
last commit: 7f55ec6ae (CI branch ci/morph-end-remeasure is at 067846590, the push commit; later commits fix the init-cost lint and max-parallel 3)
CI runs: push 1 (067846590): toolbar-throttle 40158609202 FAILED, all 4 six-arm jobs lost (job 3 and 4 frozen runners at 69 and 110 min, job 1 cancelled at 110 min, job 2 step timed out at 90 min; 3+... usable passes in artifacts); smoothness touch-lock 40158609210 success (results/morph-end-remeasure/touch-lock-run-40158609210.md); lean 40158609183 failure (init cost lint 1640; fixed b653fff4e). Push 2: ten three-arm jobs, run id below once read
verified: local check.sh green; measure-webkit 721 tests; ci-paths 56; runner land-inputs + overflow-widths 80 (max-parallel 3 after the widths test named 4); fw plan lint: no writesClosure line for this task
open: read the push-2 toolbar-throttle run; pool with run 40158609202 (relabel its job vm); note; dry land; review ready

State and conventions
- Lean: lean/Fw/Measure/MorphEndCount.lean (event counting by finger direction, spring-back fight, brick verdict, golden generator); golden packages/contracts/golden/device/morph-end-count.jsonl; check.sh job "morph-end-count golden check"; Trigger rows for lean.yml and toolbar-throttle.yml.
- TS twin: packages/measure-webkit/src/throttle/morph-end.mjs (golden replayed by test/throttle-morph-end.test.mjs); report morph-end-report.mjs (brickRow, three tables).
- Workflow: toolbar-throttle.yml morph-end matrix [1..10], three arms per job (rewrite first, then two compositions taken in turn from clamp flip release all all-unthrottle; each composition in 4 jobs), 4 cycles, rotate 0, max-parallel 3 (the Lean widths table).
- "release" and "release with the hold rule on main" are the same page: the held bit lives in end.logic.ts release.
- Touch-push lane: only the smoothness [touch-lock] job exists (arms orig/base/lock in src/touchlock-cli.mjs, outside this task's writes); run as-is as the lane reference.
- TS stand-ins left: faithful-passes-in-same-jobs selection (brickRow) and report glue.
- Read first: lean/Fw/Measure/MorphEndCount.lean, packages/measure-webkit/src/throttle/morph-end.mjs, research/notes/2026/10-2x-morph-end-measure.md
