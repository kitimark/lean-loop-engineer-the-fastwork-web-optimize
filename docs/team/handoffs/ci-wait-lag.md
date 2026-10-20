# Handoff: ci-wait-lag (round 2)

State: branch worktree-wf_cbc5b0eb-d56-2, main merged (2026-10-20), see `git log`. Green: gh-budget `pnpm test` (60), apps/runner
`pnpm test` (1417), `node --test scripts/ci-paths.test.mjs`, `sh lean/scripts/check.sh`. Not pushed to CI.

Read first: `research/notes/2026/10-19-ci-wait-lag.md` (Round 2 section).

What exists
- `fw ci wait` spans carry `runIds` + `phases` (wait.ts `WaitPhases`); `pnpm fw timings --lag [--since h]` splits each `done` wait.
- Lean `Fw.Ci.Lag` (partition, `parts_sum`) with golden ci-budget/lag.jsonl replayed by `lagParts`.
- Lean `Fw.Ci.Attempt` + fwcore op `ci.attempt`: verdict keyed on the run attempt (cache reuse, stale view, floor, 30 s freshness of finished rows).
- Fake gh knows `attempt`/`viewAttempt`; tests "rerun: ..." in packages/gh-budget/test/wait.test.ts.

Baseline: `fw timings --lag` on this host printed "no spans with phases yet" (pre-instrumentation). Run it after >= 30 waits on merged code.

Open items (follow-ups)
- Real component shares (MEASURED later); parallel jobs views; fewer fwcore spawns per wait (each wait now also calls `ci.attempt`).
- Ingest from the cached jobs response (needs charged/core owners); wait-guard (deny `gh run watch` and gh poll loops, Lean `Fw.Ops.Wait` + golden).
- A finished-run wait answered from a poller file > 30 s old waits for a tick; it is counted `done`/`late` and inflates `list` (accepted; note Round 3).
- Rerun inside the 30 s freshness window can still show the old attempt (accepted limit).

Conventions: span key is `runIds` (never `runId`). TS stand-ins: lagView, waitSpanExtra (formatting, no decisions). lagParts replays Lean; waitKind and critIndex (wait.ts) replay golden lag-kind.jsonl (Lean `Fw.Ci.Lag.kind`, `crit`).
Wire.lean still holds older `$$` blocks of other ops (not ours); our docstrings have none.
Written outside the task's writes: none (work-graph.json untouched).
