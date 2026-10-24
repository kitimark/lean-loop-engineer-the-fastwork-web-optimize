# Handoff: accent-same-look (lean-prover)

- Branch `worktree-wf_59cdc4a2-046-1`, worktree `.claude/worktrees/wf_59cdc4a2-046-1`.
- Last sha: see `git log -1` on the branch (this file is in the commit it describes).
- CI runs: none dispatched (round 2 accepted limit: no CI dispatch).
- Verified: `lake build Fw.Engine.StyleDiffAccent`; golden `--check` up to date; `sameLook.test.ts` green; axioms
  of the new theorems are propext, Classical.choice, Quot.sound only.
- Round 2 (review findings 1, 2): sprite moved to pending (WebKit timeline time is 1 ms steps, so `frames_miss`
  does not apply); `userDecision` on n=55.
- Open: sprite, canvas and glide pixel checks (MEASURED-pending); review findings 3-6 are follow-ups.

## State
- Lean `Fw.Engine.StyleDiffAccent`: `Search`, `srow`, `verdict` (with `#guard`s), `frames_miss`,
  `clip_coverage_differs`, `glide_same`, `glide_eased`, `jump_differs`, `combo_54`, `pending_exact`,
  `stroke_pending`, `pending_nolayout`. Golden rows `search` and `combo` in
  `packages/contracts/golden/parts/hero.accent.nolayout.jsonl`.
- Ledger: `userDecision` (rejected 2026-10-24) on n=55 and n=56, new rows n=59..65 `accent.same.*`.
- No new flag or variant: nothing is proved same-look and WebKit layout-free.

## Follow-ups (outside this task's writes)
- `packages/measure-webkit/src/pathpix-exit-draw-webkit.mjs` DRAW_FLAGS: add sprite, canvas and glide arms for the path-pix
  sim-draw run (run plan in the note).
- Glide needs the hero part's neighbour spans (cross-part write to `apps/site/src/parts/hero/`).
- `lean/Fw/Preset/Gen.lean` `lookDecisions`: an entry for the n=56 rejection if the preset should carry it.

## Read first
`research/notes/2026/10-2x-accent-same-look.md`, then the `srow` table in `lean/Fw/Engine/StyleDiffAccent.lean`.
