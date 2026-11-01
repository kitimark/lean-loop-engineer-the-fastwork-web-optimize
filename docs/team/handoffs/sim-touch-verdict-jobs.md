# Handoff: sim-touch-verdict-jobs (measure-engineer, finisher)

Branch `worktree-wf_66b63664-0d9-1`, worktree `.claude/worktrees/wf_66b63664-0d9-1`, CI branch `ci/sim-touch-verdict-jobs`. Last commit: `git log -1` (round 2 code fa58e3706 plus this file).

## CI runs (2 dispatches allowed, 2 used once dispatch 2 is pushed)
- 41345594217 (smoothness, dispatch 1, 6b9a16a34): complete, failure (job 4 crashed). 5 of 5 jobs started at once, all ended inside 45 min (22 to 32 min), 5 files, 0 decisive jobs, across-jobs end touch verdict insufficient. Causes: setup 11 to 13 min under load left too little of a 25 min walk (jobs 1, 5 budgetShort), driver not ready in 240 s (jobs 2, 3, touch off), undici `setTypeOfService EINVAL` crash (job 4). Numbers: the note section "Verdict jobs".
- 41349666358 (smoothness, dispatch 2, 33937b435): complete, success. 5 of 5 jobs started, 5 files, 2 decisive, across-jobs end touch verdict insufficient (3 needed); no job cut by the 60 min limit. Lost: driver not ready in 480 s (job 5), pageLost and 120 s evaluate hangs (jobs 3, 4). Table in the note.

## Verified (local, no result claims)
`sh lean/scripts/check.sh` green at fa58e3706; measure-webkit 1114 pass; ci-paths 56; runner land-inputs 73 (read of `.github/workflows/smoothness.yml` declared in `apps/runner/src/land.ts:174`, outside the row writes).

## Built
Round 1 (d3be56307): Lean `Fw/Measure/WalkBudget.lean` jobsNeeded 5, `plan_across`, tail-quantile `blockMs`, shapes, `groupsFor`; TS `walk-budget.mjs`, `sim-cadence.mjs planSim`, `report.mjs jobsTable`; 5-job matrix, `FW_MATRIX_JOB`.
Round 2: job timeout 60 min (deadline 40 min), `readyAllowMs` 480 s, `setupWorstMs` + `ok_at_worst_setup`, `repsWant` 6, `guardSocketFault`.

## Open
- Premise "one run not insufficient" closed as a finding (0 then 2 of 3 decisive). Follow-up: 10-job matrix in two waves (max-parallel 5), and end a job early when the driver is not ready.
- Cap row: `webkit-sim` in `Fw.Ci.Pool.Caps` is now the plan bound `simWallDm` (cap 60, INFERRED), golden and `scripts/ci-paths.test.mjs` updated (outside the row writes).
- Follow-up: `[touch-lock]` lane (4 arms, 2 jobs) has no `planReps`; `touchlock-run.mjs` not in the row writes. The matrix does not split arms over jobs (only `repPlan.groups` reports it). `windowSecs` is the 216-window sample, dispatch 1 windows are slower. webkit-mac plus 5 sim jobs is 6 macOS jobs without `[sim-only]`.

## Read first
The note section "Verdict jobs" in `research/notes/2026/10-2x-sim-touch-reliable.md`, then `lean/Fw/Measure/WalkBudget.lean` from `## Jobs`.
