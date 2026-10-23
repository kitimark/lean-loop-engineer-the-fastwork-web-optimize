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
- D (`pickD`, task lsp-reap): every process of an idle lean-lsp-mcp server stack (a `lake serve` whose parent is a
  lean-lsp-mcp process, its `lean --server` and `lean --worker`s), kind `mcpIdle`, when all of these hold:
  - the row's cwd is in a `.claude/worktrees/<id>` of this repo, the same id as its `lake serve`;
  - the worktree has no live session: no worktree lock whose reason names a pid (`(pid P ...`) that is in the process
    table, no lock that names no pid, and no lean-lsp-mcp process whose own cwd is in that worktree;
  - every row of the stack used at most `cpuTolCs` (300 cs = 3 s) of CPU since its baseline, and that baseline is at least
    `idleSec` (1200 s = 20 min) old (`quiet`).
  D is the one branch that takes a row in a live checkout. `never_live_mcp_parent`: a D selection is a quiet row with an
  MCP root in its chain of the same worktree id, no lean-lsp-mcp started in that worktree and no live lock on it.
- E (`pickE`, task reap-watch-one-rule): an `until [ -s <path> ]` loop shell (kind `orphanLoop`) in this repo whose tool
  call has ended (parent is init), at least `orphanMinSec` (60 s) old, and that no live `fw ci wait` of the same worktree id
  writes (its stdout file is the awaited path, its pid and start are in the table). `live_writer_kept`, `call_live_kept`,
  `orphan_selected`. The watch alert `agent.held` is `ops.reapHeld` on the same facts (`held_in_plan`: every alerted identity
  is a TERM target of `ops.reapPlan`), so `fw reap --stop` applies what the alert names; the tick stops it.
- F (`pickF`): a Simulator device process of ours (`fw-` name) that started before the last sim slot release (`simIdleSince` of
  the slot `state.json`), with no sim slot held and `simGraceSec` (15 s) passed (kind `simBooted`). `sim_selected`,
  `sim_held_kept`, `sim_after_release_kept`, `sim_grace_kept`.
  Goldens: `packages/contracts/golden/ops/reap-one.jsonl` (generator `lean/scripts/ReapGolden.lean`), test `apps/runner/test/reap-one.test.ts`.
- Serena: a row with a serena process in its chain (itself included) is never selected, by any branch (`serena_row`).
  reap.ts classifies argv with a `serena` word or a `/.serena/` path as `serena`; the serena-lean `lean --server` is kept
  through its serena parent.
- Never, on every branch: cwd in a live checkout, the console recorded in `.fw-console/api.json` (of the repo and of the
  checkout the tool runs from) and everything below it (`live_console_never_selected`), pid <= 1, the stopper's own pid and
  ancestors. B and C never take MCP servers.

## Stop plan (Lean `plan`, `termPlan`, `killPlan`, `guardOk`, `Stage` script)
read table, read again and let Lean re-check each identity (`term_present`), TERM the group (only if every member of the
group is selected, else per pid), wait up to `graceMs` (3000), re-read, KILL only survivors with unchanged (pid, start)
(`reuse_guard`), wait `killWaitMs` (1000), verify. Every signal first passes `guardOk` against an explicit scope of pids
(production: the Lean selection; a test: the pids it started), which refuses a pid outside the scope, pid <= 1 and a
group with a member outside the scope (`guard_scope`). Start time has 1-second resolution (accepted limit).

## CPU baselines (Lean `rebase`, op `ops.reapIdle`)
Each run reads the CPU time of every row (`ps -axo pid=,time=`) and stores Lean's baselines in `reap-idle.json` of the
console directory (`FW_CONSOLE_DIR` or `<main>/.fw-console`): per (pid, start) of an MCP stack row, the old baseline while
the row stays within `cpuTolCs` of it, else a new one at `now` (`rebase_quiet`, `rebase_busy`). A stack becomes selectable
`idleSec` after the run that first saw it quiet, so D needs two runs at least 20 min apart (watch ticks count).
`fw reap --list` prints the RSS of each `mcpIdle` row and a total line `mcpIdle: N process(es), X MB RSS`.

## Triggers
- `fw reap --stop`; `fw land` stops after a worktree is removed; `fw watch` stops on each tick (and after each stream
  diff). `FW_WATCH_REAP=0` turns the watch trigger off.
- Each stop appends `{type:"reap.stopped",at,kind,pids,freedKb}` to `.fw-console/reap.jsonl` and prints a `REAP stopped` line.

## Limits
The MCP processes themselves (the lean-lsp-mcp launcher and its Python) are not stopped; D stops only the `lake serve`
stack below one, which lean-lsp-mcp 0.31.0 restarts on its next request to that worktree (a client whose process ended is
replaced: lean_lsp_mcp/client_utils.py:156-187@lean-lsp-mcp 0.31.0, `_get_or_create_shared_client` returns the client
only while `client.alive` (:168), else closes it and calls `_start_client` (:187); `alive` is leanclient/aio/transport.py:75
(process returncode is None); CONFIRMED). Serena and serena-lean are
out of scope until the user approves them. Idle is INFERRED from CPU time (a stack waiting on a request without CPU looks
idle). A lock holder is checked by pid only, so a reused pid keeps the stack (the safe side); a teammate session whose
worktree is not locked counts as live only through a lean-lsp-mcp started there. Unselected processes still need the user; the console does not yet display `reap.stopped`.
C may select a tool whose cwd is a deleted directory anywhere in this repo when its ancestor is selected by A or B.
A process a group member forks after the pre-signal table read is in the group and gets the group signal (it is a child
of a selected process).
Tests: `apps/runner/test/reap-stop.test.ts` (real process trees), `reap-safety.test.ts` (a console-like process of another
repo), `reap.test.ts` (golden replay of `lspreap.jsonl` and `reap.jsonl`, stubbed table), `reap-idle.test.ts` (golden replay of
`reap-idle.jsonl`, the CPU-time and lock parsers, serena classification, `--list` with MB; stubbed facts, no signal).
