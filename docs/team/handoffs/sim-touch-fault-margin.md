# sim-touch-fault-margin handoff (checkpoint 1: CI run in progress)

Branch `worktree-wf_8b157c2a-318-1`, code commit 6399bbd7d, CI trigger commit 8cf84b94b (empty, tags
`[ci:smoothness] [webkit-cadence] [earn-bound] [sim-only]`), CI branch `ci/sim-touch-fault-margin` at 8cf84b94b.

## State
- Dispatch 1 of at most 2: smoothness run 41357917479 (10 webkit-sim jobs, two waves of max-parallel 5). Running.
- Do not push again to the ci branch while it runs (the workflow's tip re-check marks jobs stale).
- Wait: `pnpm -s fw ci wait --branch ci/sim-touch-fault-margin --workflow smoothness`; fetch with `pnpm fw ci 41357917479`
  or `gh run download 41357917479`.

## Done and tested locally
- Lean `Fw.Measure.WalkBudget`: fault rate input (plan 2/5 decisive, pooled 2/10), `jobsNeeded` = 10, reach theorems, waves,
  `never_at_once` (start-at-once replaced by two waves; sim-only 10 jobs, 120 min bound), driverFault goldens.
- TS twins and goldens in `packages/measure-webkit` (1117 tests pass), early end on driver-not-ready in sim-cadence and
  touchlock (`planLock`), fault column in profile report, workflow matrices, Caps derived row for the sim lane.

## Open
- Read the run: decisive count, across-jobs end-touch verdict, dominant fault.
- Refresh `windowSecs`/`tailEvery` in WalkBudget.lean from the new windows; regenerate golden (lake build first); sync TS.
- Update Caps `simWalls` with the new successful walls; regenerate pool-caps golden.
- Note section in `research/notes/2026/10-2x-sim-touch-reliable.md`.
- Then check.sh, package tests, ci-paths test, apps/runner land-inputs test, merge main, `fw plan lint`, dry land, `fw review ready`.

## Read first
`lean/Fw/Measure/WalkBudget.lean` (reach, waves), `packages/measure-webkit/src/profile/sim-cadence.mjs` (driverEnd).
