# sim-touch-reliable handoff

- Branch `worktree-wf_b60a7b2e-e1c-1`, worktree `.claude/worktrees/wf_b60a7b2e-e1c-1`, last commit see `git log -1`. Round 3 (findings after run 39957772249) pending its CI proof.
- CI runs: `39934951574` complete (round 2 code, 52 of 53 pushes ok); `39957772249` complete (job 1 cancelled at the 45-min job limit, jobs 2 and 3 success; evidence for round 3); round 3 proof run `39981414973` (push `d6413d23d`, `[sim-walk-cap=8]` cuts job 1) complete, cancelled: job 1 (cap 8) success with partial sim.json; job 2 success; job 3 walk step ended 4.4 min after its timeout, upload cancelled by the job timeout, no artifact (harness blocked in spawnSync, starved runner); round 3b adds a hard stop + incremental sim.json + upload first; second proof run: see below if present; read: `pnpm -s fw ci wait --branch ci/sim-touch-reliable --workflow smoothness`.
- Round 3 cause (CONFIRMED, step times of the jobs API): walk step `timeout-minutes: 50` above job `timeout-minutes: 45`; the job timeout cancelled the step, `!cancelled()` post steps were skipped, so no sim.json/log was kept. Non-touch windows have no per-window bound (Timeline.stop 60 s, retries, 107 to 291 s end windows in job 3).
- Round 3 change: Lean `Fw.Measure.WalkBudget` (deadline = 45 - 10 post - 2 grace - 1 slack = 32 min from job start; golden `packages/contracts/golden/measure/walk-budget.jsonl`, 12 lines);
  `packages/measure-webkit/src/walk-budget.mjs` (stand-ins + CLI, test `test/walk-budget.test.mjs`); `sim-cadence.mjs` (`deadlineMs`: no window starts without 30 s left, window in flight abandoned at the deadline, partial rows kept);
  `profile/cli.mjs` (`--deadline-ms`, explicit exit); `smoothness.yml` webkit-sim job (Job clock, Walk budget step, dynamic walk `timeout-minutes`, per-step timeouts, post steps `always()`, upload `warn`, `[sim-walk-cap=N]` in the commit message cuts job 1's walk N min after it starts).
- Verified: lean check, measure-webkit tests, ci-paths test, actionlint clean. Not verified: the workflow on CI (dynamic `timeout-minutes` expression) until the proof run.

## Open
- Files outside the task writes: `.github/workflows/smoothness.yml`, `lean/Fw/Measure/WalkBudget.lean`, `lean/scripts/WalkBudgetGolden.lean`, `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/Fw/Ci/Trigger.lean`, `packages/contracts/golden/ci/triggers.jsonl`, `packages/contracts/golden/measure/walk-budget.jsonl`, `packages/measure-webkit/src/walk-budget.mjs`, `packages/measure-webkit/src/profile/cli.mjs`, plus round 1 and 2 Lean files (`TouchPush.lean`, `TouchPushGolden.lean`, `touch-push.jsonl`).
- Control arm (`FW_TOUCH_VARIANTS=safari`), report.mjs `timeline:false` label, starved Simulator hero windows: follow-ups.

## Read first
`research/notes/2026/10-2x-sim-touch-reliable.md` section "Job-level bound", `lean/Fw/Measure/WalkBudget.lean`, the webkit-sim job of `.github/workflows/smoothness.yml`.
