# land-wallclock-off-gate (console-builder)

State: branch worktree-wf_95ca6613-c51-2, one commit. Tests green: console-api (325), runner (1029 + land-inputs), ci-paths, scripts/lint-wallclock.test.mjs (19).

## Done
- Sweep of land-selected tests (apps/runner, console-api, console-web test dirs, scripts/*.test.mjs). Real absolute bounds were only two:
  `console-api/test/serve.test.ts` replay `< 5000` became `replayMs < n * apply-p50 * 4` (same run, load scales both; measured 2.3 s vs 18 s bound);
  `console-api/test/crash.test.ts` elapsed `< 3000` dropped (only a lower bound `>= deadline - 50`), deadline 150 ms and 5 s call cap now
  env knobs `FW_TEST_DEADLINE_MS` (1500) and `FW_TEST_CALL_MS` (30000). No test case dropped.
- `hooks.test.ts:99-101` was already a ratio of interleaved minima (no ms literal): left as is. Hook ask timeouts: spawn-guard fixed earlier
  (ac5db43c); `land-guard.mjs` 30 s spawnSync cap is a hang cap in a hook, left.
- Lean `lean/Fw/Console/WallClock.lean` (Site, isBound, reasonOk, refuse; 4 theorems with LaTeX; golden
  `packages/contracts/golden/console/wallclock.jsonl`, regenerate with `Fw.Console.WallClock.writeGolden`).
- `scripts/lint-wallclock.mjs` (+ `.test.mjs`): lexes sites, decision equals the golden; `scripts/wallclock-allow.json` whitelists 18 generous hang-catcher
  timeouts (>= 30 s) with a reason; stale entries fail. Root `pnpm lint` runs it; the land runs it through `test/wallclock-lint.test.ts` in runner and console-api.

## Open
- TS `refuse` is a stand-in copy of the Lean decision, replay-checked only (no fwcore op). Lexing is regex, line-based: a bound built across lines is missed.
- Scope is the three app test dirs + scripts tests, not packages/*/test or apps/site parts tests.
- The land does not set the env knobs (defaults are already generous).
- `lake build` of the whole `Fw` library not run, only `Fw.Console.WallClock`.

Read first: lean/Fw/Console/WallClock.lean, scripts/lint-wallclock.mjs.
