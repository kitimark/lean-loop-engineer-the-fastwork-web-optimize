# Handoff: ci-wait-lag

State: branch worktree-wf_cbc5b0eb-d56-2, instrumentation committed (see `git log`). Tests green: gh-budget `pnpm test`, apps/runner
`pnpm test` (1054), `node --test scripts/ci-paths.test.mjs`. Not pushed to CI (nothing to measure there; real waits are on the
user's host).

Read first: `research/notes/2026/10-19-ci-wait-lag.md`.

What exists
- `fw ci wait` spans carry `runIds` + `phases` (wait.ts `WaitPhases`, cli.ts `lastWaitPhases`, fw.ts `spanExtra`).
- `pnpm fw timings --lag [--since h]` splits each `done` wait into list/pickup/view/verdict/cleanup/ingest/exit (timing-ci.ts).
- Ingest cost bookkeeping fixed 2 -> 3.

Verified: ordering of phases, no extra gh calls, partition identity (tests in `packages/gh-budget/test/wait.test.ts`,
`apps/runner/test/timing-lag.test.ts`).
Not verified (MEASURED later): real component shares. Run `pnpm fw timings --lag` after >= 30 waits on the merged code.

Open items (follow-ups, not done here)
- Build ingest spans from the cached jobs response (drops one gh view per run); needs charged/core (ci-wait-lean owns them).
- Parallel lane jobs views; fewer fwcore spawns per wait.
- wait-guard: deny `gh run watch` and gh poll loops (Lean `Fw.Ops.Wait` + golden; hook unchanged).
- `ciwait-check.md` was not found from this worktree; only finding 1 was answered.

Conventions: extra span key is `runIds` (never `runId`, `seenRuns` matches it). TS stand-ins: lagParts, lagView, waitSpanExtra.
