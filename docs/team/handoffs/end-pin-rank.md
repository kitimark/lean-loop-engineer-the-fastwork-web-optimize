Branch `worktree-wf_29839f53-3e5-1`; worktree `.claude/worktrees/wf_29839f53-3e5-1` (under the main checkout); last commit 797214995 (empty trigger on `ci/end-pin-rank`, tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock] [trajectory fw=morph.tween:end-pin]`); work commit 684cc6ad0.

## CI runs
- 41369102226 smoothness (dispatch 1 of 2): in_progress at the time of writing (12 simulator jobs, 3 waves, max-parallel 5).

## Verified (before the push)
- Lean `check.sh` green; measure-webkit 1121 tests pass; ci-paths 56; runner land-inputs 73.
- Lean: `Fw.Measure.FaultNames` (names, `driverEnd` by phase, `faultOf`), `WalkBudget` (`legsOf`, `lateJobs` 12, lock waves 3), `TouchLock` (`pinVerdict`, `acrossPin`, `liveWrites` replay). Goldens regenerated; TS twins replay them.
- Lane: `touchlock-cli.mjs across label=touch-lock.json ...` prints the per-job pin vs base table and the across verdict.

## Open
- Wait for the run (`pnpm -s fw ci wait --branch ci/end-pin-rank --workflow smoothness`), download artifacts smoothness-webkit-sim-N, run the across command, write the note and ledger row.
- plan lint, dry land, `fw review ready`.

## Read first
`lean/Fw/Measure/FaultNames.lean`, `lean/Fw/Measure/TouchLock.lean` (acrossPin), `packages/measure-webkit/src/touchlock.mjs` (acrossReport).
