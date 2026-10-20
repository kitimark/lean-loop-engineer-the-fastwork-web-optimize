# orphan-guard handoff (round 2)

State: items 1 (list mode), 8, 9 of research/notes/2026/10-20-resource-audit.md. No process is signalled anywhere.

Delivered
- Lean `Fw.Ops.Reap` (lean/Fw/Ops/Reap.lean), op `ops.lspReap`: input rows (pid, ppid, pgid, start, cwd inode, argv kind),
  `live` inodes (this repo's checkouts incl. nested Lean dirs), `mcps` [{pid, cwd}], `keep` [{pid, at}] (recorded console).
  Per-row theorems (no uniqueness hypothesis): live_row, kept_row, init_row, unnamed_row, unreadable_row, foreign_mcp, group_iff;
  selection lemmas: selected_named_and_dead, lsp_parent (mcp cwd in a live checkout), console_orphan, not_init, no_mcp_no_lsp,
  antitone_keep; corollaries live_never_selected, group_leader.
- Golden packages/contracts/golden/ops/lspreap.jsonl (17 cases, lean/scripts/ReapGolden.lean, stage in check.sh).
- Glue (TS, gathering/printing only): apps/runner/src/reap.ts, `fw reap --list`, `LandOptions.reap` after a worktree removal.
  Failed listing prints "leftover processes: could not list (...)". Tests: apps/runner/test/reap.test.ts, land-reap.test.ts.
- pipe:true at census.mjs, shell-measure.mjs, gate-breakpoints/src/gaps/engines.mjs; e2e-land.sh traps INT/TERM/HUP.
- task-preview recipe: worktree console with `FW_CONSOLE_DIR=$PWD/.fw-console` (start and stop), lead's console untouched.

Round-1 fixes: recorded console kept by identity (api.json pid + startedAt second, 60 s window, in Lean); only mcps whose own cwd is
in a live checkout count; nested dirs under a live checkout are live (lsof path under the checkout and stat inode equal); land test.
Accepted limit: inodes carry no st_dev (a cross-device collision can only keep a row, never select one).

Writes beyond the graph entry (lead to update orphan-guard.writes; reap-stop names Reap.lean, not LspReap.lean): apps/site/scripts/
census.mjs, shell-measure.mjs, apps/runner/src/{lib.ts,reap.ts,fw.ts,land.ts}, apps/runner/test/{reap,land-reap}.test.ts,
lean/Fw/Ops/Reap.lean, lean/Fw/Wire.lean, lean/scripts/{ReapGolden.lean,check.sh}, docs/team/handoffs/task-preview.md.

Open (follow-ups): stop mode (task reap-stop); `reapable` line in fw watch; upstream lean-lsp-mcp LRU patch.
Read first: lean/Fw/Ops/Reap.lean, apps/runner/src/reap.ts.
