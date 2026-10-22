# lsp-reap handoff

State: branch `worktree-wf_4f02b054-959-1`, work commit 52efd98e (main 33d24878 merged).

Delivered (unit: branch D of `fw reap`, an idle lean-lsp-mcp server stack in a worktree with no live session):
- `lean/Fw/Ops/Reap.lean`: kind `mcpIdle`; `InputD extends Input` (now, uses, bases, locks, mcpWt), so `Input`, `Row`
  and `Mcp` keep main's shape (Fw.Sup and Fw.Wire.Sup build them positionally); `pickD`, `quiet`, `stackIdle`,
  `sessionLive`, `pickAll` (serena chain refused first), `reapAll`, `planAll`, `rebase`; op `ops.reapIdle`; `ops.lspReap`
  and `ops.reapPlan` now answer with every branch. Theorems `never_live_mcp_parent`, `serena_row`, `live_session_row`,
  `busy_stack_row`, `main_row`, `idle_row`, `all_safe`, `all_shielded`, `all_not_init`, `planAll_group_inside`,
  `rebase_quiet`, `rebase_busy`, `busy_not_quiet`, `no_mcp_no_idle`; A, B, C statements unchanged.
- Goldens `packages/contracts/golden/ops/reap-idle.jsonl` (21 cases; `lean/scripts/ReapGolden.lean`, outside the graph
  writes); `lspreap.jsonl` and `reap.jsonl` unchanged.
- `apps/runner/src/reap.ts`: CPU time (`ps -axo pid=,time=`), worktree locks from `git worktree list --porcelain`, each
  lean-lsp-mcp's worktree id, baselines in `<console dir>/reap-idle.json`, serena classification, `--list` MB + total.
- `apps/runner/test/reap-idle.test.ts` (stubbed facts, no signal), `docs/team/tools/reap.md`.

MEASURED on this Mac (`FW_CONSOLE_DIR` = a scratch dir, runs 05:30:49 and 05:44:43 +07, 2026-10-22):
both print `reap: nothing leftover`, 0 rows, 0 MB. The only lean-lsp-mcp stack (`lake serve` 44 MB, `lean --server`
318 MB, one worker 486 MB) runs in this task's own locked worktree, so it is kept; serena-lean's `lean --server` is
kept too. The second run came 14 min after the first, inside the 20-min window, so no stack could pass yet.

Verified: `sh lean/scripts/check.sh` and `pnpm --filter @fw/runner test` through `fw slot run` (Node 24.22.0); axioms
standard; dry land.

Open (accepted limits): serena/serena-lean out of scope until the user approves; idle is INFERRED from CPU time;
`idleSec` 1200 s and `cpuTolCs` 300 cs are first values; a lock holder is matched by pid only (reuse keeps a stack);
`fw watch` ticks now also stop D stacks once main runs this code.

Read first: `docs/team/tools/reap.md`, then the "Branch D" section of `Reap.lean`.
