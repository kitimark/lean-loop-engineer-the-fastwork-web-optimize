# test-batch-2 handoff

State: committed on branch worktree-wf_ad887758-4a8-1. Test files only; no production code or golden data changed.

Changes
- apps/runner/test/wait-guard.test.ts: the false-positive describe (allow/deny/review/review3, ~83 verb() spawns) now uses ONE
  fwcore (lazy, ids = index in the deduped command list, LEAN_ABORT_ON_PANIC=1, reply count asserted). One test keeps the
  per-call ask() path and checks it equals the batch. The golden batch also sets LEAN_ABORT_ON_PANIC and asserts one reply per request.
- apps/runner/test/timing-alert.test.ts: golden obs.timing (22 cases) and obs.slow (22 cases) go through two fwcore processes
  (ids, count asserted); each golden case is still its own named test; the 4 hand-written core() tests keep the per-call path.
- packages/measure-chromium/test/fwcore.test.mjs: fakeRuns() classifies all (run, arm) pairs in one call() instead of one per pair.

Measured (one run each, wall seconds; load average at start in brackets; Mac was heavily loaded by other lanes)
| suite / file | before | after |
| wait-guard.test.ts | 68 s [74] | 7 s [42] |
| timing-alert.test.ts | 62 s in full-suite run [32] | 11 s [51] |
| measure-chromium pnpm test | 54 s [34] | 28 s [36] |
| apps/runner full (tsc + vitest) | 137 s [32] | 134 s [43] (other files dominate) |
Load differs, so part is less contention; spawn counts fell: wait-guard ~86 -> 3, timing-alert ~48 -> 6, freeze fixtures 30 -> 5 per fakeRuns.

Open (not done, why)
- apps/runner is still ~134 s: land-hardening (29 cases, 2-7 s each), land-prelock, land-scope, land-dry, land-post are real-git
  integration cases; each builds a git fixture (makeRepo) and runs land(); no per-case fwcore batch applies. Next lever: share a
  fixture repo per describe (clone per case) in apps/console-api/test/reconcile-fixture.ts, or split the runner suite across
  vitest shards in the land check.
- gate-breakpoints: slow cases (devicecells 12-15 s, gaps 11 s, scope.gen 17 s) call production verdict.mjs call() once per
  function call; ESM exports cannot be swapped, so batching needs a production hook or a memoizing fwcore shim. scope.gen.json check runs lake. Untouched.
- console-api: 61 s, evenly spread over files (preview 52 s over 21 cases, preview-facts-gen 32 s single git case). Untouched.
- land-inputs.test.ts "apps/site: sources and tests read only 88 declared globs" fails on this base: apps/site/src/parts/people/assets.ts
  reads snapshot/site/selling/sellers (not from this change).
- Land wall time is mostly machine load (load average 30-100 here); the 90 s target needs the land pool to cap concurrency as well.
