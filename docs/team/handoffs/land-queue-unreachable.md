# land-queue-unreachable (console-builder)

State: branch worktree-wf_be3f7e90-9a2-1, one commit (see report). Lean `sh lean/scripts/check.sh` green at it; runner `pnpm test` (tsc + vitest, 1560) green; ci-paths test green.

## Mechanism (2026-10-20, local times)
| entry | previous res | failed res | gap |
|---|---|---|---|
| trajectory-probe | console-idle-cpu done 20:16:23 | unknown "fetch failed" 20:16:24 | 168 ms |
| orphan-guard | watch-incremental done 20:33:34 | unknown 20:33:34 | 169 ms |
| pool-caps | orphan-guard done 21:37:51 | unknown 21:37:54 | 530 ms |
- Failing request: the first console request of `land()` for a task, `GET /api/plan` (apps/runner/src/land.ts, scope step). undici throws `TypeError: fetch failed` (connection refused) at once; a blocked console would instead hit the 90 s `HTTP_DEADLINE_MS` abort. The land never started (the log `<task>-queue.log` is one 29-byte line, no `<task>-<sha7>.log`).
- MEASURED for pool-caps: fwcore binary mtime 21:37 (queue rebuild), console-api process start 21:38:02 (`ps`), failure 21:37:54: console was down for at least 8 s across a restart that followed the rebuild. The other two fit the same pattern (gap < 1 s after a land whose diff touched lean/) but their console start times are no longer observable (INFERRED). console.log has no timestamps; its fwcore `timed out after 10000 ms` lines (1792470604 to 1792483313) are a different, earlier load incident and not the cause (named only).
- Unthrown cause: `runQueue` turned the thrown error into kind `unknown` (final) with reason `fetch failed`.

## What changed
- Lean `Fw.Console.LandQueue`: `healthDelay/pollTime/healthBoundMs` (63750 ms), `healthReached`, `attemptNext` (+ theorems: `health_bounded`, `healthReached_within/_never/_late`, `attemptNext_bounded/_unreachable_not_unknown/_returns/_never/_late/_exhausted/_landed`, `healthWaitAfter_iff`), premise `land.consoleStaysUp`, 19 golden cases (ops landQueue.health/healthSchedule/attempt/healthAfter).
- TS twin in `apps/runner/src/land-queue.ts` (TS stand-in, golden-checked): `ConsoleUnreachable`, `waitHealth`, `attemptNext`; `httpFor` throws it; `fw.ts` passes a `/api/health` probe.
- Tests: `apps/runner/test/land-queue-unreachable.test.ts` (real HTTP fake console down N s then up; never up; after rebuild).

## Accepted limits / follow-ups
- Refusal kind is `busy` (exit 10) + reason `console-unreachable`; a dedicated Kind needs LandVerdict (outside writes).
- A console that is up but blocked (request timeout, fwcore call timeouts under load) is not covered; it stays `unknown`.
- A retry after an unreachable error mid-land is safe only because the error is thrown before the merge (scope step); a later console loss is a warning in the post-land steps, unchanged.
- Read first: LandQueue.lean section "An unreachable console", land-queue.ts `runQueue`.
