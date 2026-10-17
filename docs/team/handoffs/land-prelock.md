# land-prelock handoff

State: branch of this worktree; code in apps/runner/src/land.ts (`preLock`, `claimLandWt`, `checkoutLandWt`, `prelockAction`),
tests apps/runner/test/land-prelock.test.ts, docs/team/tools/land.md.

- Lean: Land.lean not changed (the decision `prelockAction` + bounded-retry theorem already exist in LandSpeed.lean). `prelockAction`
  is a TS stand-in (golden-checked); open item: an fwcore op `landSpeed.prelock` so land.ts asks Lean.
- Old-protocol tests (open merge, intruder refused, MERGE_HEAD gone, HEAD moved) now pass `prelock: false`.
- Flake root cause (land-task "merges with --no-ff..." timed out at 5019 ms): vitest's 5 s default test timeout against tests that
  start tens of git and fwcore child processes, worse under check-dag's parallel load; and `askCore` killed fwcore after 5 s
  (spawnSync timeout), which makes a land REFUSE with "fwcore is not available" under load. Fixes: land-guard askCore timeout 30 s
  (it only catches a hang, no decision depends on time); test/land-timeout.ts (120 s bound, imported by every land test).
  No test asserts wall-clock time.
- Fixture note: tests that want the evidence edit must commit docs/team/work-graph.json (untracked files are not in the land worktree).
- First use of a land worktree runs scripts/wt-prep.sh and an offline pnpm install (best effort); later lands reuse them.
- Concurrent lands each take a slot (`.claude/land-wt/<n>.claim` pid file); a dead pid's claim is taken over.
- Load (lead's second request): Lean `poolSize cores loadCeil = max 1 (cores - loadCeil)` in LandSpeed.lean (4 theorems, #guards;
  compiles, check.sh green); TS stand-in `poolSize` in land.ts (no fwcore op / golden yet: open item). A check that fails with a
  timeout message (LOAD_FAILURE_RE) is re-run once alone, as a span "(retry alone ...)". vitest.config.ts in apps/runner and
  apps/console-api sets 120 s test timeouts. Replaced the one wall-clock land test (land-post overlap) with a rendezvous test.
  Left: runner test/hooks.test.ts "timing: under 100 ms" is a wall-clock assertion (not a land test); flake risk under load.
- MEASURED local (fixture repo, trivial checks, loadavg 31-37): lock held 0.19 s (ff 0.05-0.07 s); total land 2-3 s.
