# graph-schema-precommit handoff
State: branch worktree-wf_529e3a24-f84-2 at a4dc4a79 (handoff fix is the tip). The pre-commit checkmap now validates docs/team/work-graph.json against the runner's schema.
- scripts/checkmap.mjs `file json`: for docs/team/work-graph.json it also calls checkGraph (imported from apps/runner/src/plan-check.ts).
- apps/runner/src/plan-check.ts: runs syncCommands (the contract Command.parse) one task at a time, deps stubbed, so each
  refusal prints `docs/team/work-graph.json task <id>: <field>: <message>`; then the whole graph (cycles, unknown deps).
  No limit is copied; the 32 cap stays in packages/contracts/src/index.ts.
- apps/runner/test/plan-check.test.ts: 33 writes refused (exit 1, "big: writes"), 32 accepted, 33 deps named, current graph passes.
Verified: apps/runner pnpm test (57 files, 1622 tests), scripts/ci-paths.test.mjs 49 pass, scripts/test-checkmap.mjs no FAIL.
Time: whole `checkmap file json` on the current graph 210-240 ms wall (node start plus schema).
Open: the routing is a TS special case on the path in checkmap.mjs; Lean CheckMap.lean has no rule kind for it (follow-up: a
workGraph kind emitting `file graph`). Lean check.sh not run (no Lean change).
Read first: scripts/checkmap.mjs fileMode, apps/runner/src/plan-check.ts.
