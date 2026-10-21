# fw reap: detect and stop this project's unused processes

`pnpm -s fw reap --list` (default, signals nothing) prints what Lean selects; `pnpm -s fw reap --stop` stops it
gracefully. Exit 2 if a selected process survives KILL.

## Detection (Lean `Fw.Ops.Reap`, identity only: pid + start second)
Repo identity first: every branch needs the cwd inside THIS repo, decided by (device, inode) of the repo root and of its
`.claude/worktrees` directory, never by a path string (`membership` in reap.ts). A stop run with another repo as top selects
nothing of the user's real repo (theorems `in_repo`, `console_in_removed_wt`, `lsp_in_removed_wt`, `removed_branch`).
- A: a `lake serve` whose parent is this repo's live lean-lsp-mcp, or an orphan console-api (ppid 1), whose cwd is in a
  non-live `.claude/worktrees/<id>` of this repo. One theorem per kind.
- B: a tool (lean, lake, fwcore, node, esbuild, playwright browsers) or a `lake serve` (also an orphan, ppid 1) whose cwd is
  in a non-live worktree id of this repo.
- C: a tool whose cwd is inside this repo and whose ancestor is selected by A or B (descendant of a dead owner).
- Never, on every branch: cwd in a live checkout, the console recorded in `.fw-console/api.json` (of the repo and of the
  checkout the tool runs from) and everything below it (`live_console_never_selected`), pid <= 1, the stopper's own pid and
  ancestors. B and C never take MCP servers.

## Stop plan (Lean `plan`, `termPlan`, `killPlan`, `guardOk`, `Stage` script)
read table, read again and let Lean re-check each identity (`term_present`), TERM the group (only if every member of the
group is selected, else per pid), wait up to `graceMs` (3000), re-read, KILL only survivors with unchanged (pid, start)
(`reuse_guard`), wait `killWaitMs` (1000), verify. Every signal first passes `guardOk` against an explicit scope of pids
(production: the Lean selection; a test: the pids it started), which refuses a pid outside the scope, pid <= 1 and a
group with a member outside the scope (`guard_scope`). Start time has 1-second resolution (accepted limit).

## Triggers
- `fw reap --stop`; `fw land` stops after a worktree is removed; `fw watch` stops on each tick (and after each stream
  diff). `FW_WATCH_REAP=0` turns the watch trigger off.
- Each stop appends `{type:"reap.stopped",at,kind,pids,freedKb}` to `.fw-console/reap.jsonl` and prints a `REAP stopped` line.

## Limits
MCP servers are not stopped; unselected processes still need the user; the console does not yet display `reap.stopped`.
Tests: `apps/runner/test/reap-stop.test.ts` (real process trees), `reap-safety.test.ts` (a console-like process of another
repo), `reap.test.ts` (golden replay of `lspreap.jsonl` and `reap.jsonl`, stubbed table).
