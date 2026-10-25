# toolbar-proof-morph handoff

- Branch `worktree-wf_af7c2028-837-1`, worktree `.claude/worktrees/wf_af7c2028-837-1`, CI branch `ci/toolbar-proof-morph`; last commit = `git log -1` (round 3 started at tip e13a8ada8; round 3 changed prose only).
- CI runs: `40213443051` trajectory-probe `fw=morph.mount:touch-first` widths 390,1280 both engines: success (Chromium 0 new fails,
  44 undecided; WebKit 2000/2000 pass). `40214808662` trajectory-probe `fw=morph.mount:open-once` same inputs: success (Chromium 0 new, 44 undecided; WebKit 2000/2000). Pushes used: 2 of 3.
- Verified: Lean `MorphMountToolbar` (proofs, no sorry), golden `morph-mount-toolbar.jsonl` (225 rows) replayed by `gesture.test.ts`;
  footprint, footprint-diff, preset outputs regenerated; `lean/Fw.lean` imports the two modules.
- Read first: `research/notes/2026/10-2x-toolbar-proof-morph.md`, then `lean/Fw/Parts/MorphMountToolbar.lean`.
- Round 2: all three flags are proposals (L) in look-change.candidates.jsonl; same look under touch unproven until toolbar-sim-lane. Lanes (a),(c1) split to toolbar-sim-lane, toolbar-wktr-gate. Refuted premise in ledger.
- Open, with owners: Simulator count lane: toolbar-sim-lane. WKTR forced-inset fixture: toolbar-wktr-gate. Candidate (d) container
  scroll: its own task, not filed. Measured cost of unthrottle (f): toolbar-sim-lane. Cause of the 8-41 reopens: toolbar-sim-lane.
