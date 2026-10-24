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
- E (`pickE`, task reap-watch-one-rule), kind `orphanLoop`: a shell whose argv is an `until [ -s <path> ]` loop (`classify`
  gives `untilLoop`), in this repo, whose tool call ended (`callLive` false: glue sets it from `ppid > 1`, unproved), at
  least `orphanMinSec` (60 s) old, and with no live writer: a `fw ci wait` of the same worktree id whose stdout (lsof fd 1,2)
  is the same file as the awaited path and whose (pid, start) is in the table (`writerLive`; `live_writer_kept`,
  `writer_identity`, `orphan_selected`). Same file (`sameFile`): by inode number when both are known (`lsof -Fpfin` for the
  waiter, `stat` of the awaited path for the loop; `writer_inode_match`, `sameFile_inode_differs`), so a hard link or a
  symlinked directory still counts as the writer and a replaced file does not; when the awaited file does not exist yet the
  canonical path string decides (`sameFile_path_fallback`). Accepted limit: the inode number is not paired with st_dev, a
  collision across devices reads as the same file (the loop is kept). Path allowlist: only an absolute awaited path of
  letters, digits, `.`, `_`, `/`, `-` can select (`awaitOk`, `awaitAllowed` in reap.ts; `relative_await_kept`,
  `dollar_await_kept`, `backtick_await_kept`, `await_char_kept`): `out.log`, `$HOME/x`, a backtick, `*`, `?`, `[ ]`, `~` or a
  space keeps the loop. The glue canonicalises only such a path (`canonAwait`: `canonPath`, realpath of the directory +
  basename, raw if it fails; the lsof path always) so `/private/tmp/x` and `/tmp/x` match. The watch's `agent.held` for a wait
  loop is `ops.reapHeld` (the E selections) and nothing else: a TERM target of the explicit `ops.reapPlan` (`auto` false)
  with the same pid and start (`held_in_plan`). The `NEXT <id> killOrphan pid= start=` line of `Fw.Obs.Next` is the same held entry, in the agent's own worktree (`kill_iff`).
- F (`pickF`), kind `simBooted`: a Simulator device process (`launchd_sim`, device id in argv) that this project boots
  (`ownSims`: the row's (pid, start) is in the glue's list of devices whose udid the slot recorded at the release of its last
  sim run, `simUdids` of `state.json`: the Simulators booted since the acquire, `simNew before after` = booted at the release minus booted at the acquire (`simBefore`), upper-cased; a device already up before the run is not ours; no device-name prefix), that started between the acquire second of the released sim slot run (`simAcquired`, kept in the slot
  `state.json` on release and expiry) and the release (`simIdleSince`), while `Fw.Sup.Adapt.simAction` (the slot's own
  rule, default `simIdleS` 600 s, `simVerdict`) says `shutdown` for the sim slots still held and for `legacyHeld`, whether
  the legacy `scripts/sim-lock.sh` lock `.local/locks/sim` is live (`legacyLive` of slot.ts; a missing fact counts as
  held, `sim_legacy_kept`). Theorems: `sim_selected`, `sim_legacy_kept`,
  `sim_held_kept`, `sim_after_release_kept`, `sim_before_acquire_kept`, `sim_not_own_kept`, `sim_idle_kept`,
  `sim_no_release_kept`, `sim_no_acquire_kept`. The stop is not a signal: `stopSelected` calls `simctlShutdown(udid)` of
  slot.ts (the call `fw slot sim` uses), never TERM or KILL of `launchd_sim`.
- Serena: a row with a serena process in its chain (itself included) is never selected, by any branch (`serena_row`).
  reap.ts classifies argv with a `serena` word or a `/.serena/` path as `serena`; the serena-lean `lean --server` is kept
  through its serena parent.
- Never, on every branch: cwd in a live checkout, the console recorded in `.fw-console/api.json` (of the repo and of the
  checkout the tool runs from) and everything below it (`live_console_never_selected`), pid <= 1, the stopper's own pid and
  ancestors. B and C never take MCP servers.

## Action class (Lean `planSel`, `autoKinds`)
E and F are advice: `fw reap --list` lists them, the watch raises `agent.held` for E, and only an explicit
`fw reap --stop` stops them. The request field `auto` picks the plan: the watch tick (`reapTick`) and the land report
(`reapStopLines`) send `auto: true` and get targets of the kinds in `autoKinds` (A to D) only
(`auto_plan_no_loop_sim`, `planSel_auto`); `fw reap --stop` sends false and gets every selection (`planSel_explicit`).
`reap.jsonl` is folded by Lean (`ops.reapLog`, `ops.reapFold`; golden `reap-fold.jsonl`). Each watch tick (`recordHeld`) appends
`{type:"reap.held",at,kind,pid,start}` once per new E/F identity (first sight, `newHeld`: no repeat while the identity stays
selected) and one `{type:"reap.tick",at,live:[{kind,pid,start}]}` row with the E/F identities selected then. `reap.stopped`
rows carry `targets [{pid,start}]` (the identities the stop TERMed). The glue reads the last 4 MiB of the log (`readLog`; a cut
first line and torn rows are dropped). The F alert is the watch's `agent.held`.
Lean's `foldSeen` turns the rows into one `Seen` per identity (first sight, outcome stopped by a `reap.stopped` target /
ended = a later tick no longer selects it / alive). `fw reap --exit` prints the verdict and signals none.
Coverage (Lean `covered`, `slotSec` 1800 = 6 ticks of 300 s): the log must reach back 7 days and hold a tick in every 1800 s slot of the 7 days (`covered_slot`, `covered_gap`): two consecutive ticks are less than 3600 s apart, and the last tick is less than 1800 s before now; until then the verdict is `not yet 7 days of coverage` and nothing is
promoted. Today this is a MEASURED verdict. With 7 days covered, E and F are promoted
by `exitRule` into `InputD.promote`, `autoSet = autoKinds ++ promote` (E/F only), and `reapTick` sends the promoted kinds in
the auto plan (`auto_plan_promoted`); `promote = []` keeps `auto_plan_no_loop_sim`.
An explicit `fw reap --stop` of an E or F process counts as a true orphan stop, so it is evidence for promotion; a `kill` outside `fw reap` is not logged as a stop: the next tick no longer selects the process, so the fold marks it `ended`, which keeps its kind out of the automatic plan.

Exit rule (Lean `exitRule`, `promoted`, op `ops.reapExit`, golden `reap-exit.jsonl`): a kind joins `autoKinds` only when it
is E or F, its log goes back at least 7 days, it has at least one identity `stopped` by an explicit `fw reap --stop` (a true
orphan) and no identity `ended` by itself (`exit_selected`, `exit_short_kept`, `exit_no_orphan_kept`, `exit_ended_kept`,
`exit_other_kind_kept`). E and F start OUT of `autoKinds`; the log fold above feeds the rule (task reap-exit-fold):
`fw reap --exit` and `reapTick` read the log each time.

The guard scope of `stopSelected` is the plan targets, not the selection, so an orphan loop in the process
group of an A-D target gets no signal and the group falls back to per-pid. The land report counts the targets
(`leftover processes stopped: N of M`) and prints the advice rows on their own line.

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
- `fw reap --stop` (all kinds); `fw land` stops after a worktree is removed and `fw watch` stops on each tick (and after
  each stream diff), both A to D only. `FW_WATCH_REAP=0` turns the watch trigger off. A Simulator of case F is not stopped by them; the slot's own `simCheck` still shuts it on the next slot command after 600 s idle.
- Each stop appends `{type:"reap.stopped",at,kind,pids,freedKb}` to `.fw-console/reap.jsonl` and prints a `REAP stopped` line.

## Limits
The MCP processes themselves (the lean-lsp-mcp launcher and its Python) are not stopped; D stops only the `lake serve`
stack below one, which lean-lsp-mcp 0.31.0 restarts on its next request to that worktree (lean_lsp_mcp/client_utils.py:156-187@lean-lsp-mcp 0.31.0, `_get_or_create_shared_client` returns the client
only while `client.alive` (:168), else closes it and calls `_start_client` (:187); `alive` is leanclient/aio/transport.py:75
(process returncode is None); CONFIRMED). Serena and serena-lean are
out of scope until the user approves them. Idle is INFERRED from CPU time (a stack waiting on a request without CPU looks
idle). A lock holder is checked by pid only, so a reused pid keeps the stack; a teammate session whose
worktree is not locked counts as live only through a lean-lsp-mcp started there. The console does not yet display `reap.stopped`.
C may select a tool whose cwd is a deleted directory anywhere in this repo when its ancestor is selected by A or B.
A process a group member forks after the pre-signal table read gets the group signal.
Tests: `apps/runner/test/reap-stop.test.ts` (real process trees), `reap-safety.test.ts` (a console-like process of another
repo), `reap.test.ts` (golden replay of `lspreap.jsonl` and `reap.jsonl`, stubbed table), `reap-idle.test.ts` (golden replay of
`reap-idle.jsonl`, the CPU-time and lock parsers, serena classification, `--list` with MB; stubbed facts, no signal).
`reap-one.test.ts` (golden replay of `reap-one.jsonl`: branches E and F, canonical paths, the Simulator stop through `simStop`, the watch alert equals the stop plan).
