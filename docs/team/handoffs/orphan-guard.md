# orphan-guard handoff

State: items 1 (list mode), 8, 9 of research/notes/2026/10-20-resource-audit.md. No process is signalled anywhere.

Delivered
- Lean `Fw.Ops.Reap` (lean/Fw/Ops/Reap.lean), op `ops.lspReap`: rows (pid, ppid, pgid, start, cwd inode, argv kind), live
  inodes, lean-lsp-mcp pids -> rows to stop (pid, start, kind, group flag, reason). Theorems: `selected_named_and_dead`,
  `live_never_selected`, `group_leader`, `lsp_parent`, `console_orphan`, `not_init`, `no_mcp_no_lsp`, `antitone_live`.
  Deviation from the task text: the mcp input is a list (`mcps`), since each Claude session has its own lean-lsp-mcp.
- Golden: packages/contracts/golden/ops/lspreap.jsonl from lean/scripts/ReapGolden.lean (stage in lean/scripts/check.sh).
- Glue (TS, gathering and printing only): apps/runner/src/reap.ts; `fw reap --list`; `LandOptions.reap` prints the list in
  the land report after a worktree removal (wired in fw.ts landOpts). Test: apps/runner/test/reap.test.ts replays the golden
  through fwcore.
- pipe:true at census.mjs, shell-measure.mjs, gate-breakpoints/src/gaps/engines.mjs; e2e-land.sh traps INT/TERM/HUP;
  docs/team/handoffs/task-preview.md recipe uses `fw console start`.

Conventions: the glue adds the root, lean/ and apps/console-api/ inode of every live checkout to `live` (a console runs in
apps/console-api). An unreadable cwd is never selected.

Open (follow-ups, not in this task): stop mode (needs the CLAUDE.md kill rule amended); `reapable` line in fw watch
(watch-incremental owns watch-collect.ts); upstream lean-lsp-mcp LRU patch. Chrome from non-pipe launchers is not a Lean kind.

Read first: lean/Fw/Ops/Reap.lean, apps/runner/src/reap.ts.
