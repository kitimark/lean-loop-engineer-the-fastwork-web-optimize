# land-pool-fair handoff

State: branch `worktree-agent-af45f361145d7025e`. The land check pool now uses Lean `poolFair`; the timeout re-run is decided by Lean.

Changes
- `lean/Fw/Console/LandPool.lean`: added `rerunAlone`, `rerunPool`, `settle` with `rerunAlone_pass/noload/timeout`, `rerunPool_le`,
  `settle_rerun/norerun/first`, `verdict_pool_free` (= `verdict_perm`: pool size and order change no verdict).
- Ops `console.landPool` {cores, load} -> {pool} and `console.landRetry` {passed, loadFailure} -> {rerun, pool} in
  `lean/Fw/Wire/Console.lean`; goldens `packages/contracts/golden/console/console.land{Pool,Retry}.jsonl` (from `Fw/Ops/Golden.lean`).
- `apps/runner/src/land.ts`: `poolFor` and `rerunAlone` call fwcore (`askCore`); the TS `poolSize` stand-in is gone. No fwcore: pool 1,
  no re-run (the failure stands). Tests: `apps/runner/test/land-prelock.test.ts`, `land-hardening.test.ts` (golden replay).

MEASURED (real check set of a runner+lean change, this worktree, 3 pairs, interleaved; load 10 to 54 on 8 cores; install excluded)

| mode | pool | total (s) |
|---|---|---|
| serial (old rule) | 1 | 55, 60, 50 |
| poolFair | 4 | 31, 33, 33 |

Timed out and re-ran: 0 of 9 checks per run, in all 6 runs; no flaky test under pool 4. Under pool 4 a check takes 1.5 to 3 times
longer (runner 19 -> 27 s, gh-budget 10 -> 24 s), still a net win. Total is bounded by check.sh (5 s) then apps/runner (27 s):
the 30 s ceiling is met only barely; next lever is the runner suite itself (it is the critical path).

Open: math-reviewer on the new theorems; `checkDeps` makes everything wait for check.sh, so pool 4 is never full early on.
Read first: `lean/Fw/Console/LandPool.lean` tail, `apps/runner/src/land.ts` (`poolFor`).
