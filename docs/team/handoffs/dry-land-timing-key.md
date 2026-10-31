branch: worktree-wf_57d9899b-52a-1
worktree: .claude/worktrees/wf_57d9899b-52a-1 (under the repo root)
last commit: see `git log -1`
CI runs: none pushed (the unit needs no CI measurement; Lean check.sh, runner tests and typecheck ran locally in slots)

State: done, ready for dry land and review.
- Lean rule: lean/Fw/Obs/Timing.lean `checkSetId`, `setWork`, `landWork`, theorems `checkSetId_perm`, `landWork_set_ne`,
  `judgeQ0_other_set`, `judge_new_set_noBaseline`, guards `setRun`; golden packages/contracts/golden/obs/timing-set.jsonl.
- Emit: apps/runner/src/land.ts (`dryIds`, `lintCheckId`, handoff via `writeHandoff`), apps/runner/src/timing.ts (`set` span
  member, `checkSetId`, `setWork`, `spanWork`, handoff read/write). slot.ts unchanged: it spreads `readLakeHandoff`.
- Tests: apps/runner/test/timing-work.test.ts (golden), land-dry.test.ts (dim on the real dry spans).
- Replay and findings: research/notes/2026/11-01-dry-land-timing-key.md (slow 291 to 200; the three alert samples to
  noBaseline live-like). Replay script: scratchpad/dltk-wf/ (not committed).

Verified: sh lean/scripts/check.sh green; `pnpm --filter ./apps/runner test` 3758 passed; typecheck; ci-paths test.
Open: TS `checkSetId` is a stand-in checked against the golden (sort by code unit equals Lean string order for ASCII ids).
Conventions: ids are a closed vocabulary without `+`; a dry land that fails before choosing checks writes no `set`.
Read first: the research note, then the Lean block after `modsWork`.
