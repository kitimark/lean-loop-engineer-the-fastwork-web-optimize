branch: worktree-wf_b0986207-a8f-1
worktree: .claude/worktrees/wf_b0986207-a8f-1
last commit: see `git log -1` on the branch
CI runs: none (no dispatch in this task)

State: delivered, all inside the graph writes.
- `lean/Fw/Preset/Gen.lean`: `lookDecisions` has `hero.accent:draw-nolayout-full`, 2026-10-25, `rejected`, review `done`,
  WebKit material runs 40030735082 and 40035116432 (artifacts webkit-sim-r1..r3, expire 2026-11-22), Chromium `pending`.
- `decisionKept`/`staleIn` keep a refusal of a registered flag that is not class L (4 theorems). `refusedMembers` plus a
  `Gen.run` check keep refused flags out of v2-proved. `decisionOf` adds `userDecision` to every decisions-golden row.
- Ledger row `accent.drawin-width-nolayout`: status `refuted`, userDecision with reason and source chat.
  Row `accent.draw-nolayout`: `next` points to the note.
- Goldens `packages/contracts/golden/preset/*` from `Gen.run`; `--check` green; look golden unchanged.
- Note `research/notes/2026/10-2x-accent-look-refused.md`: draw-nolayout is a look change of the accent text, glide kept.

Verified: check.sh, @fw/site test and typecheck, @fw/contracts test, ci-paths, runner land-inputs, plan lint, dry land
(see the report).
Open: register both wipe arms as `proposal`, `visClass: L` in `apps/site/src/parts/hero.accent/part.json` and
`drawNoLayout.test.ts` (outside these writes); the user's own decision on `hero.accent:draw-nolayout`;
`ledgerDisagreements` checks only Chromium material.
Convention: "refused" is the verdict word `rejected` (`Fw.Wire.Review.verdictOf`).
Read first: the note, then `Gen.lookDecisions`, `Gen.decisionKept` and `Fw.Engine.StyleDiffAccent` (`armFrame`).
