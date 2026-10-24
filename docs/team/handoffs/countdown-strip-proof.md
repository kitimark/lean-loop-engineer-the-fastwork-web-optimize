# countdown-strip-proof handoff

- Branch `worktree-wf_193723c6-362-1`, worktree `.claude/worktrees/wf_193723c6-362-1`, last commit: see `git log -1`
  on the branch (WIP commit of the Lean module, golden, site test).
- CI runs (ref `ci/countdown-strip-proof` at bbd203c7f):
  - webkit-sim 40081936555 (target rewrite, fw hero.countdown:strip,morph.countdown:strip): in progress.
  - breakpoint-gate 40081933958: failed in smoke, the flag string was not prerendered (the prerendered key is
    `?fw=morph.countdown:strip,hero.countdown:strip`, morph first). Both dispatches of the budget are spent.
- Faithful baseline for the census: webkit-sim 39897814980 (target rewrite, no flags, sha 540130e9; countdown code
  unchanged since).

## Verified
- `lake build Fw.Parts.MorphCountdownStrip` green; axioms of `same_face_px`, `phase_same`: propext, Classical.choice,
  Quot.sound; layer theorems none or propext.
- Golden `packages/contracts/golden/parts/morph.countdown.strip.jsonl` is checked by `#guard jsonl == include_str`.
- `apps/site/src/parts/morph.countdown/strip.test.ts` replays it through `createCountdownDriver`: 17 tests pass.

## Open
- Read the census of 40081936555 against 39897814980 (countdown layers and backing MB in the finish zone).
- Gate verdict for the strip pair needs a third dispatch with the morph-first flag order (lead decides).
- Note `research/notes/2026/10-2x-countdown-strip-proof.md`, ledger row, `import Fw.Parts.MorphCountdownStrip` in
  `lean/Fw.lean` (lead).

## Read first
`lean/Fw/Parts/MorphCountdownStrip.lean` (driver model `upd`/`drive`, `same_face_px`, `layers_80_to_16`).
