# reap-auto-stop handoff (round 2)
Branch worktree-wf_19c39b39-743-1. Read first: docs/team/tools/reap.md, lean/Fw/Ops/Reap.lean, apps/runner/src/reap.ts.

State
- Lean: every branch (A console, A lspServe, B, C) needs the cwd inside THIS repo; A and B need a non-live worktree id
  (`goneWt`), C `inRepo`. Theorems: in_repo, console_in_removed_wt, lsp_in_removed_wt, removed_branch, descendant_branch.
  The recorded console and everything below it is shielded on all branches (`live_console_never_selected`). B/C also take an
  orphan `lake serve`. New ops: `ops.reapTerm` (identity re-read right before TERM, `term_present`) and `ops.reapGuard`
  (`guardOk`, `guard_scope`: no signal outside the scope, none to pid <= 1).
- TS: `membership`/`repoIdOf` decide repo identity by (dev, inode) of the repo root and `.claude/worktrees` (no path string);
  `recordedConsoles` also reads the console dir of the checkout the code runs from. `stopSelected(..., scope?)`: scope =
  Lean's selection in production, the test's own pids in tests; every signal passes `ops.reapGuard`.
- Golden: lspreap.jsonl (26) and reap.jsonl (38), both replayed by reap.test.ts.
- Tests: reap-safety.test.ts (console-like orphan in ANOTHER temp repo: nothing selected; recorded console + its child never),
  reap-stop.test.ts (real trees, scope refusal, pre-TERM re-read, pid reuse).

Round 1 incident: the test run at 04:15:47 TERMed the live console (pids 4444 and 4480 were console-api and its fwcore).
Cause: branch A console was repo-agnostic (no this-repo condition); fixed in round 2 (first fix commit a5cc66b8; theorems above).
Record in docs/team/incidents/ledger.json (inc-reap-console-kill exists on main).

Verified: runner test 1745/1746 (the one failure is incidents lint: inc-reap-console-kill evidence .fw-console/console.log is not in git), check.sh green, ci-paths 52/52, land-inputs 55/55. Linux CI land run 39545711452: reap-stop (10) and reap-safety (2) green (the run concluded failure only on the incidents lint of main's ledger evidence path, since fixed on main); lean run 39545711435 green.

Open (follow-ups)
- Console display of reap.stopped (contract command plus console-api/web edits).
- checks.ts spawnRunner (land checks) still spawns without its own process group.
- No local `fw reap --stop` run on this Mac (classifier denies it); the real-process tests are the evidence.
- 1-second start-time resolution; inode collisions across devices can only add a live inode (a kept row).
- C is now rarely different from B: it labels descendants whose cwd is a deleted directory of this repo.
- MCP servers are not stopped.
