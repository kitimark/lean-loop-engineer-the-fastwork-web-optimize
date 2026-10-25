branch: worktree-wf_5e997045-0e6-1 (CI branch ci/webkit-sim-relaunch)
worktree: .claude/worktrees/wf_5e997045-0e6-1
last commit: d9c04c714 (Lean machine, golden, guard reboot path); later commits on the branch
CI runs: none pushed yet (0 of 3 pushes used)

## State
- Lean: `lean/Fw/Device/SimRelaunch.lean` (call machine, pass machine, rank, seconds bound, golden `run`); golden `packages/contracts/golden/device/sim-relaunch.jsonl`; wired in `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/Fw/Ci/Trigger.lean` (lean.yml row), `triggers.jsonl` regenerated.
- JS: `packages/measure-webkit/src/guard.mjs` (twin of the machine, reboot path in `createGuard`, options `reboot`, `deviceUp`), `src/sim.mjs` (`CALL`, `deviceBooted`, `rebootDevice`, list = 2 tries of 90 s). Tests: `test/sim-relaunch.test.mjs` (golden replay, scenarios, fake xcrun), `test/guard.test.mjs` adapted.
- Note: `research/notes/2026/10-2x-webkit-sim-relaunch.md` (causes with run ids, sources, limits).

## Verified
- Lean module compiles without warnings; node tests of guard, target-lost and sim-relaunch pass; `node --test scripts/ci-paths.test.mjs` passes.

## Open
- The step bound has no room for a late reboot: `SimBound.perSessionMin` needs `recoverMin` (13 min) more; outside this task's writes.
- No fault injection of a device shutdown on CI (`fault.mjs`, `session.mjs` are not in the writes); the recover path is proved in Lean and replayed in tests only.
- Two 3-VM webkit-sim runs: dispatch with `pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref ci/webkit-sim-relaunch`.

## Read first
- The note, then `SimRelaunch.lean` (theorems `pass_ends`, `pass_time_le`, `retry_after_answer`), then `guard.mjs` `recover`.
