# ghb-runner handoff (runner gh calls through the request budget)

State: one commit on branch worktree-agent-a91d6811fe1a841ae. Read first: `apps/runner/src/run.ts` (section "gh (CI)"), `apps/runner/test/run-budget.test.ts`.
- `Gh` is now async. `chargedGh(env)` = `ghCharged` with `block: true` and a cost per command (`ghCost`, table from the research note §1; stand-in).
  A budget stop or a gh failure throws `gh <cmd> not made ...` / `gh <cmd> failed: HTTP ...` (exit 1 via fw.ts). `ghCli` is gone.
- `fw run`: dispatch, previous-run list, headSha view, download = charged. `gh run watch` and `newestRun` are gone: after a dispatch it
  does a branch wait (`waitFor`, newest run of the workflow created after the previous newest one, else `now - 60 s`); `--from-run` does a run
  wait. Exit 1 of the wait (run failed) throws like `--exit-status` did. `runMain`, `ciMain`, `runCli`, `ciCli` are async.
- `fw ci`: list/view/download charged. `fw watch`: `chargedRunner(base, env)` wraps `gh` in `collectSystem` (non-blocking: wait/stop/failure = null,
  so the previous value is carried, marked stale). A missing `gh` binary now also reads as a failed call (stale), not as "missing".
- TS stand-ins: `ghCost` table; `waitDecided` (repeat a timed-out 540 s slice, throw when the wait returned early = poller stopped, cap 4 h);
  workflow display name read from the local `.github/workflows/<file>` `name:` when the workflow has no earlier run.
- Not done: signal cleanup of waiters (`cleanups` is not exported by @fw/gh-budget; a killed `fw run` leaves a waiter marker that the next drop prunes by pid).
  `fw watch` could read `state.json` instead (0 requests) per the note; it still spends one charged `run list` (cost 3) per check.
- Tests: `pnpm --filter ./apps/runner test` 169 green; gh-budget suite green. Counts (fake gh): 1 waiter 14 gh calls, 1 fw run + 9 waiters 14;
  10 fw runs 32 (list 11 and created-view 1 as for 1; head 10, download 10). Land tests need `lean/.lake/build/bin/fwcore` in the worktree.
