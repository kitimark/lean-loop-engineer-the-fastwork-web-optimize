# Handoff: sim-touch-verdict-jobs (measure-engineer, finisher)

Branch `worktree-wf_66b63664-0d9-1`, worktree `.claude/worktrees/wf_66b63664-0d9-1`, CI branch `ci/sim-touch-verdict-jobs` (pushed tip 6b9a16a34, dispatch 1 of 2).
Last commit: see `git log -1`.

## CI runs
- dispatch 1 (push of 6b9a16a34, tags `[ci:smoothness] [webkit-cadence] [earn-bound] [sim-only]`): run id pending (read with `pnpm -s fw ci --branch ci/sim-touch-verdict-jobs`), state running.

## Verified (local, no result claims)
- `sh lean/scripts/check.sh` green at d3be56307 tree (replayed); measure-webkit 1112 pass; ci-paths 56; runner land-inputs 73 after declaring `.github/workflows/smoothness.yml` for `packages/measure-webkit` in `apps/runner/src/land.ts:174` (outside the row writes).

## Built (first builder d3be56307)
Lean `Fw/Measure/WalkBudget.lean`: `jobsNeeded` 5, `plan_across`, tail-quantile `blockMs`, `planReps`/`outcome` per shape, `groupsFor`, slack 8 min; TS `walk-budget.mjs`, `sim-cadence.mjs planSim` (plan after boot, driver, Safari), `report.mjs jobsTable`; `smoothness.yml` 5-job matrix, `FW_MATRIX_JOB` on the morph step. Premises table: `research/notes/2026/10-2x-sim-touch-reliable.md` section "Verdict jobs".

## Open
- CI result of dispatch 1 (jobs started, jobs with results, across-job end-touch verdict).
- Follow-up: the `[touch-lock]` lane (4 arms, 2 jobs) has no `planReps` (fixed 6 reps, deadline cut only); `touchlock-run.mjs` is not in this row's writes.
- The matrix does not split arms over jobs; 5+ arms report `repPlan.groups` only.
- webkit-mac (max-parallel 1) plus 5 sim jobs is 6 macOS jobs when `[sim-only]` is absent.

## Read first
The note section above, then `lean/Fw/Measure/WalkBudget.lean` from `## Jobs`.
