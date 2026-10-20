# land-queue-unreachable (console-builder), round 2

State: branch worktree-wf_be3f7e90-9a2-1 (commit in report). `sh lean/scripts/check.sh` green; runner `pnpm test` green on Node 24.14.0 and 24.22.0.

## Mechanism (local times 2026-10-20; spans from .fw-console/timings.jsonl + land-queue.jsonl)
Six `unknown "fetch failed"` results, not five (pool-caps twice). All: first console request of the next entry's `land()` (`GET /api/plan`), 168-530 ms long.
| entry | prev res | last verify end | cleanup span | rebuild span | failed attempt | verify->attempt | console restart span |
|---|---|---|---|---|---|---|---|
| console-idle-cpu | 19:31:05.421 | 19:30:58.699 | 19:30:59.652 +5.8 s | 19:31:05.446 +0.9 s | 19:31:06.397 +192 ms | 7.7 s | 19:31:10.186 +8.1 s |
| trajectory-probe | 20:16:23.642 | 20:16:16.468 | 20:16:19.779 +3.9 s | 20:16:23.656 +0.8 s | 20:16:24.499 +168 ms | 8.0 s | none |
| orphan-guard | 20:33:33.117 | 20:33:26.838 | 20:33:27.762 +5.4 s | 20:33:33.130 +1.0 s | 20:33:34.201 +169 ms | 7.4 s | 20:33:36.312 +2.8 s |
| pool-caps (1) | 21:37:51.926 | 21:37:40.280 | 21:37:42.613 +9.3 s | 21:37:51.957 +1.8 s | 21:37:53.893 +530 ms | 13.6 s | 21:38:00.291 +5.8 s |
| pool-caps (2) | 22:20:28.797 | 22:20:20.490 | 22:20:23.955 +4.8 s | 22:20:28.810 +0.7 s | 22:20:29.569 +171 ms | 9.1 s | 22:20:31.591 +2.0 s |
| trajectory-admission | 22:29:56.452 | 22:29:47.336 | 22:29:51.026 +5.4 s | 22:29:56.467 +0.8 s | 22:29:57.328 +321 ms | 10.0 s | 22:30:00.334 +2.6 s |
- Ruled out (MEASURED by timestamps): a restart before the failure. Every restart span starts 2.0-6.0 s AFTER its failure (it is the post-land routine reacting to the queue exit); trajectory-probe had none, and a parallel `fw land` reached the console 0.6 s after that failure.
- Fits all six (INFERRED): the queue process makes no console request for 7.4-13.6 s, mostly in sync calls (worktree cleanup, fwcore rebuild), past the console's `Keep-Alive: timeout=5`; the next fetch reuses the closed pooled socket -> `TypeError: fetch failed`, cause ECONNRESET. No log holds `err.cause.code` (the queue stored only `.message`).
- Reproduction (MEASURED, but a race): in-process server (the block also stalls the server timer), one fetch, block the loop in spawnSync past its keepAliveTimeout, fetch again: ECONNRESET in about 1/10-1/30 tries on 24.14.0 (reviewer: 1/8); `connection: close`: 0 of 56. It does not reach the 6/6 seen in the real process, so the rate there stays unexplained. Run the repro: `FW_KEEPALIVE_REPRO=1 pnpm exec vitest run test/land-queue-unreachable.test.ts -t repro` in apps/runner.

## What changed
- Fix 1 (root cause): `httpFor` (land.ts) sends `connection: close`: one socket per request, nothing to reuse. Test (deterministic): plain fetch pools sockets, httpFor opens one per request across a blocked loop and the server sees `close` each time.
- Fix 2 (kept from round 1): bounded health wait + retry (Lean `attemptNext`, golden, TS twin) for any remaining unreachable console.
- Fix 3: land.ts around `requestLand` in the locked merge block: ConsoleUnreachable -> `merge --abort` (if the merge is still ours) then rethrow. Test `land-card-unreachable.test.ts` (fails without the catch; the retry then lands). The pre-lock request (before the lock) needs no abort.
- Lean docstring and premise row `land.consoleStaysUp` now cite the real test; "a restart after the queue's fwcore rebuild" removed.
- Wallclock lint (merged from main) flagged round-1 literals in land-queue-unreachable.test.ts; replaced by named constants.

## Accepted limits / follow-ups
- Refusal kind is `busy` + reason `console-unreachable`; a dedicated LandVerdict kind is a follow-up. A console up but blocked stays `unknown`.
- Writes outside the graph list: apps/runner/src/fw.ts (allowed), apps/runner/test/land-card-unreachable.test.ts (new, runner tests).
- Read first: LandQueue.lean section "An unreachable console", land.ts `httpFor`, land-queue.ts `runQueue`.
