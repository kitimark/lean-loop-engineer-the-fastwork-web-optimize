branch: worktree-wf_1025224f-bba-1 (CI branch ci/morph-end-remeasure, 1 push used of 3)
worktree: .claude/worktrees/wf_1025224f-bba-1
last commit: 067846590 (the CI push; head commit message carries [ci:toolbar-throttle] [throttle:morph-end] [ci:smoothness] [webkit-cadence] [sim-only] [touch-lock])
CI runs: toolbar-throttle morph-end and smoothness touch-lock for 067846590: pushed, run ids not yet read (state: running)
verified: after merging main (already up to date) `fw plan lint` has no writesClosure line for this task; the golden replay test passes locally (17 of 17); Lean check.sh queued behind the slot
open: Lean check.sh, package tests, ci-paths and runner tests through fw slot; read the CI runs; note research/notes/2026/10-2x-morph-end-remeasure.md; dry land; review ready

State and conventions
- Lean: lean/Fw/Measure/MorphEndCount.lean (event counting by finger direction, spring-back fight, brick verdict, golden generator); golden packages/contracts/golden/device/morph-end-count.jsonl; check.sh job "morph-end-count golden check"; Trigger rows for lean.yml and toolbar-throttle.yml.
- TS twin: packages/measure-webkit/src/throttle/morph-end.mjs (golden replayed by test/throttle-morph-end.test.mjs); report morph-end-report.mjs (brickRow, three tables).
- Workflow: toolbar-throttle.yml morph-end matrix [1,2,3,4], six arms per job (rewrite, clamp, flip, release, all, all-unthrottle), 4 cycles, rotate VM-1, max-parallel 4.
- "release" and "release with the hold rule on main" are the same page: the held bit lives in end.logic.ts release.
- Touch-push lane: only the smoothness [touch-lock] job exists (arms orig/base/lock in src/touchlock-cli.mjs, outside this task's writes); run as-is as the lane reference.
- TS stand-ins left: faithful-passes-in-same-jobs selection (brickRow) and report glue.
- Read first: lean/Fw/Measure/MorphEndCount.lean, packages/measure-webkit/src/throttle/morph-end.mjs, research/notes/2026/10-2x-morph-end-measure.md
