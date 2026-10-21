# fw reap: detect and stop this project's unused processes

`pnpm -s fw reap --list` (default, signals nothing) prints what Lean selects; `pnpm -s fw reap --stop` stops it
gracefully. Exit 2 if a selected process survives KILL.

## Detection (Lean `Fw.Ops.Reap`, identity only: pid + start second)
- A: old rule (lake serve of a gone lean-lsp-mcp, console with dead cwd, removed checkout); one theorem per branch.
- B: a tool (lean, lake, fwcore, node, esbuild, playwright browsers) whose cwd is in a removed worktree id.
- C: a tool whose ancestor is selected by A or B (descendant of a dead owner).
- Never: cwd in a live checkout, the recorded console, pid <= 1, MCP servers, protected pids.

## Stop plan (Lean `plan`, `killPlan`, `Stage` script)
read table, TERM the group (only if every member of the group is selected, else per pid), wait up to `graceMs` (3000),
re-read, KILL only survivors with unchanged (pid, start) (`reuse_guard`), wait `killWaitMs` (1000), verify.
Start time has 1-second resolution (accepted limit).

## Triggers
- `fw reap --stop`; `fw land` stops after a worktree is removed; `fw watch` stops on each tick (and after each stream
  diff). `FW_WATCH_REAP=0` turns the watch trigger off.
- Each stop appends `{type:"reap.stopped",at,kind,pids,freedKb}` to `.fw-console/reap.jsonl` and prints a `REAP stopped` line.

## Limits
MCP servers are not stopped; unselected processes still need the user; the console does not yet display `reap.stopped`.
Tests: `apps/runner/test/reap-stop.test.ts` (real process trees), `reap.test.ts` (stubbed table).
