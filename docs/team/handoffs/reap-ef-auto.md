# reap-ef-auto handoff
Branch worktree-wf_8b584c64-792-1, worktree .claude/worktrees/wf_8b584c64-792-1. CI runs: none (accepted limit).
Done: (1) `recordHeld` (reap.ts) logs every E/F selection per watch tick as `reap.held` in reap.jsonl; (2) Lean exit rule
`exitRule`/`promoted`/`ops.reapExit` (Reap.lean, 5 theorems + guards), golden `reap-exit.jsonl`; E and F stay OUT of
`autoKinds`; (3) writer evidence by inode (`sameFile`, lsof -Fpfin + stat; path string only when the awaited file has no inode
yet); (4) slot release/expiry records `simUdids` (slot.ts `bootedUdids`), gather's `ownSims` reads them, `ownSimUdids`
(fw- prefix) is gone; (5) F alert = `REAP advice simBooted <pid>` line from `reapTick`, once per identity.
Round-3 follow-ups: (a) `awaitOk` char allowlist (letters, digits . _ / -), TS `awaitAllowed`; (b) guard scope = plan
targets; (c) `reapStopLines` counts targets, advice on its own line; (d) mixed-plan test in reap-one.test.ts.
Verified: lake build Fw.Ops.Reap, golden regenerated; vitest test/reap (189) green.
Open / limits: no caller folds reap.jsonl into `Seen` (later 7-day task); inode not paired with st_dev; udids recorded at
release are all devices booted then (Lean's acquire..release window narrows them); gather() not run end to end.
Convention: goldens via `cd lean && lake env lean --run scripts/ReapGolden.lean` (scripts/ReapGolden.lean is outside the
task writes). Read first: Reap.lean "Exit rule" section, docs/team/tools/reap.md "Action class".
