# toolbar-proof-morph handoff

- Branch `worktree-wf_af7c2028-837-1`, worktree `.claude/worktrees/wf_af7c2028-837-1`, CI branch `ci/toolbar-proof-morph`; last commit = `git log -1`.
- CI runs: `40213443051` trajectory-probe `fw=morph.mount:touch-first` widths 390,1280 both engines: success (Chromium 0 new fails,
  44 undecided; WebKit 2000/2000 pass). Second push (open-once probe): see `git log -1` and `fw ci wait --branch ci/toolbar-proof-morph
  --workflow trajectory-probe`. Pushes used: 2 of 3.
- Verified: Lean `MorphMountToolbar` (proofs, no sorry), golden `morph-mount-toolbar.jsonl` (225 rows) replayed by `gesture.test.ts`;
  footprint, footprint-diff, preset outputs regenerated; `lean/Fw.lean` imports the two modules (a write outside the task graph writes).
- Read first: `research/notes/2026/10-2x-toolbar-proof-morph.md`, then `lean/Fw/Parts/MorphMountToolbar.lean`.
- Flags: `morph.mount:touch-first`, `open-once`, `overscroll-lock` (look-change class L, never in a preset).
- Open: Simulator count lane (needs arms in `packages/measure-webkit/src/throttle/morph-end.mjs` + workflow), WKTR forced-inset
  fixture (`packages/measure-wktr`), candidate (d) container scroll, measured cost of unthrottle (f), cause of the 8-41 reopens.
