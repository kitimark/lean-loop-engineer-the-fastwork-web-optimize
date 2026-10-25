branch: worktree-wf_5e997045-0e6-1 (CI branch ci/webkit-sim-relaunch)
worktree: .claude/worktrees/wf_5e997045-0e6-1
last commit: see `git log -1` on the branch
pushes used: 2 of 3 (second adds the bounded `Host state on failure` step in webkit-sim.yml)
CI runs (all dispatched with `pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref ci/webkit-sim-relaunch`; a push run is skipped without "[ci:webkit-sim]" in the head message):
- 40162207231 push run, skipped by the guard
- 40162251194 success, 3 of 3 sim jobs green (r1 21m, r2 32m, r3 38m), commit 17527314e
- 40162538610 cancelled, 2 of 3: r1 hit the 35 min step bound then `Host state on failure` hung 16 min; r2 never ended the sessions step; r3 passed (commit 17527314e)
- 40170046006 failure, 1 of 3 (commit 0de529106, bounded Host state): r2 green (889 s); r1 named failure (reboot of the Simulator failed: `simctl shutdown` ETIMEDOUT, `lsof` ETIMEDOUT, load 900; logs uploaded); r3 REAL RECOVERY (log: "the device is not booted", shutdown 0 s, boot 9 s, bootstatus 75 s, Safari relaunched, "recovered; the inspector answers") then the 35 min step bound ended it (sessions 2170 s) = the open SimBound item

## State
- Lean: `lean/Fw/Device/SimRelaunch.lean` (call machine, pass machine, rank, seconds bound, golden `run`); golden `packages/contracts/golden/device/sim-relaunch.jsonl`; wired in `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/Fw/Ci/Trigger.lean` (lean.yml row), `triggers.jsonl` regenerated.
- JS: `packages/measure-webkit/src/guard.mjs` (twin of the machine, reboot path in `createGuard`, options `reboot`, `deviceUp`), `src/sim.mjs` (`CALL`, `deviceBooted`, `rebootDevice`, list = 2 tries of 90 s). Tests: `test/sim-relaunch.test.mjs` (golden replay, scenarios, fake xcrun), `test/guard.test.mjs` adapted.
- Workflow: `Host state on failure` runs in the background and is abandoned after 45 s.
- Note: `research/notes/2026/10-2x-webkit-sim-relaunch.md` (causes with run ids, sources, limits).

## Verified (local)
- check.sh green; init-cost lint 1636 constants; measure-webkit tests 730 pass; land-inputs 73 pass; ci-paths 56 pass; plan lint 0 errors.

## Open
- The step bound has no room for a late reboot: `SimBound.perSessionMin` needs `recoverMin` (13 min) more; outside this task's writes.
- No fault injection of a device shutdown on CI (`fault.mjs`, `session.mjs` are not in the writes); the recover path is proved in Lean and replayed in tests only; no passed VM ran it.
- A sessions step that does not end at its bound is inc-sim-step-unbounded (task sim-step-watchdog).

## Read first
- The note, then `SimRelaunch.lean` (theorems `pass_ends`, `pass_time_le`, `retry_after_answer`), then `guard.mjs` `recover`.
