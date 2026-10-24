branch: worktree-wf_b0986207-a8f-1
worktree: .claude/worktrees/wf_b0986207-a8f-1
last commit: see `git log -1` (work in 597796af8 and 006d2f266)
CI runs: none (no dispatch in this task)

State: delivered.
- `lean/Fw/Preset/Gen.lean`: `lookDecisions` has `hero.accent:draw-nolayout-full`, 2026-10-25, `rejected`, review `done`,
  WebKit material runs 40030735082 and 40035116432 (artifacts webkit-sim-r1..r3, expire 2026-11-22), Chromium `pending`.
  Guards updated for 3 decisions, plus guards for the new row.
- Ledger row `accent.drawin-width-nolayout`: status `refuted`, userDecision with reason and source chat.
  Row `accent.draw-nolayout`: `next` points to the note.
- `apps/site/src/parts/hero.accent/part.json`: both wipe arms `proposal`, `visClass: L` (outside the graph writes);
  `drawNoLayout.test.ts` asserts that (outside the graph writes).
- Goldens `packages/contracts/golden/preset/*` from `Gen.run`; `--check` green.
- Note `research/notes/2026/10-2x-accent-look-refused.md`: draw-nolayout is a look change of the accent text, glide kept.

Verified: `sh lean/scripts/check.sh` green; @fw/site test (7355 pass) and typecheck; @fw/contracts test; ci-paths 56;
runner land-inputs 73; plan lint 0 errors.
Open: the user's own decision on `hero.accent:draw-nolayout`; `ledgerDisagreements` checks only Chromium material.
Convention: "refused" is the verdict word `rejected` (`Fw.Wire.Review.verdictOf`).
Read first: the note, then `Gen.lookDecisions` and `Fw.Engine.StyleDiffAccent` (`armFrame`, `slotChanges`).
