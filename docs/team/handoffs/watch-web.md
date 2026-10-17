# watch-web handoff
State: console Health tab on branch worktree-agent-ae95afa7f34159201 (commit trailer `Task: watch-web`).
Files: apps/console-api/src/health.ts (reads the newest valid line of .fw-console/health.jsonl from the tail, zod-checked,
joins output rows to input names/facts), route `GET /api/health` in src/app.ts (null before any check),
test/health.test.ts (synthetic fixture); apps/console-web/src/Health.tsx + a Health button in App.tsx.
Tab: alerts in Lean order (passed through), system table (disk, memory, sim lock, CI, docker, worktrees; each row shows
the Lean system alert codes for it, `stale` badge from input.system.stale), agents with state counts and a table.
Conventions: no thresholds in TS. The only TS logic is presentation: agent rows grouped stalled/active/idle/parked/done
(Lean returns rows in input order), and the row-to-alert-code mapping in sysRows. TS stand-ins: none for decisions.
The API serves the logged `output` of the last `fw watch`; it does not call obs.health itself, so the tab is as fresh
as the last `pnpm fw watch` (run `--interval 300`). The web polls every 10 s.
Gates: console-api test 201 passed (needs FW_CORE_BIN to the main build when the worktree has no lean/.lake);
console-web build and typecheck pass. No web tests exist.
Open: restart the console on 8787 after merge; optionally let the API run obs.health on the logged input for freshness.
