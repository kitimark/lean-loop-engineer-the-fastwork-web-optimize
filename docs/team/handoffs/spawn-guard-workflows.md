# Handoff: spawn-guard-workflows

State: done, committed on branch worktree-agent-a2498d257fde25ea0. `FW_CORE_BIN=<main>/lean/.lake/build/bin/fwcore pnpm --filter ./apps/runner test`: 66 of 66 pass (without fwcore, 13 fwcore-dependent tests fail as before).

What changed
- `apps/runner/hooks/emit.mjs`: `background_tasks` count (SPK-p part 3); `unseenSpawn()` writes a SpawnGuard record
  (`verb: "observed"`, `seen_by: "subagent-start"`) for a SubagentStart no guard marker claims.
- `apps/runner/hooks/spawn-guard.mjs`: records carry `role, want_kind, got_kind, has_name, isolation, depth, seen_by:
  "pre-tool-use"`; writes `.fw-console/spawn-pending/` marker.
- Tests: `apps/runner/test/hooks.test.ts`, `spawn-guard.test.ts`. Note: `research/notes/2026/10-17-spk-drafts/spk-p.md`.

TS STAND-INs (replace by Lean): `kinds()` (mirror of `effKind`/`roleOf`), the marker claim by role + recency in `unseenSpawn`.
Open: the controlled wake test is not run; console-api should count SpawnGuard by `seen_by`, and the board should not double-count
a guard record plus its observation (they never both exist for one spawn). `.fw-console/spawn-pending/` is new state outside the event log.
Read first: spk-p.md "Update" section.
