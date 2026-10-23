# sim-touch-reliable handoff

- Branch `worktree-wf_b60a7b2e-e1c-1`, worktree `.claude/worktrees/wf_b60a7b2e-e1c-1`, last commit see `git log -1`. Round 3 (findings after run 39957772249) pending its CI proof.
- CI runs: `39934951574` complete (round 2, 52 of 53 pushes ok); `39957772249` cancelled (job 1 hit the 45-min job limit, jobs 2 and 3 success; evidence); `39981414973` cancelled (first proof, job 3 overran: harness blocked in spawnSync); `39995201296` failure (second proof, `f50ab2ba3`, cap 8 + hang 6): job 2 hard stop fired and all artifacts kept, job 3 success 26.6 min, job 1 harness stopped on its deadline (0 windows, starved host) but the main upload timed out at 2 min (bound held, 17.7 min job); round 3c (host state into result/, one upload + one retry) proof run `40003317485` (push `c0cb0f0dd`, `[sim-walk-cap=10] [sim-walk-hang=6]`) running; read: `pnpm -s fw ci wait --branch ci/sim-touch-reliable --workflow smoothness`.
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
