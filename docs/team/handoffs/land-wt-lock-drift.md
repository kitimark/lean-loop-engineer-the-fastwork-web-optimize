# land-wt-lock-drift handoff

Branch: worktree-wf_ba3bf2ed-e75-1. Worktree: .claude/worktrees/wf_ba3bf2ed-e75-1. CI runs: none (no CI push needed; local gates only).
Last code commit: a1319b4da (check the branch tip for the handoff commit).

## Round 2
Stamp is cleared before every install (`clearStamp` in StampFs); Lean `installStep` refusal returns `(some .install, none)`; theorems `installStep_refusal` (.2 = none), `installStep_refused_next_land_installs`; golden row stampAfter null; `landExit(res)` in land.ts maps result to exit (used by fw-main); tests: A/B/A, clear-before-install, exit 19 via landExit, no land-logs file in the real both-fail land. CI runs: none.

## Done
- Lean `LandVerdict.lean`: `installNeeded`, `installStep` (lockfile stamp), theorems `installStep_checks_see_current_stamp`, `installStep_refusal`, `installNeeded_reused_*`, `installNeeded_new`, `installStep_behind_*`.
- Lean `LandDry.lean`: `DStage.install` + `Outcome.installs` (between conflict and reads), stamp golden rows (`landVerdict.installStamp`), 256 run cases; goldens regenerated (land-dry, land-dry-merge).
- `land.ts`: `landInstallStamped` (stamp file node_modules/.fw-lock-stamp), `INSTALL_TIMEOUT_MS` 10 min, stderr tail in REFUSED, `installExec`/`installFs` injection in LandOptions, dry install refusal carries an Outcome.
- Tests: apps/runner/test/land-wt-lock-drift.test.ts (stubbed exec and fs, e2e both-fail dry and real through land()).
- land.md paragraph.

## Verified
lean/scripts/check.sh green; runner package test (tsc + vitest, 94 files) green; scripts/ci-paths.test.mjs green.

## Files outside the task's writes (follow-on of the Outcome field)
apps/runner/src/land-verdict.ts, apps/runner/test/land-verdict.test.ts, lean/Fw/Console/LandDry.lean, lean/Fw/Spec/Incidents.lean, lean/Fw/Spec/Props/LandDryDemo.lean, packages/contracts/golden/console/land-dry-merge.jsonl.

## Open
- TS stand-ins: `installNeeded`/`installStep` in land-verdict.ts (checked against the golden). The execFileSync timeout itself is not unit-tested (fixed constant).
