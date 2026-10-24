# countdown-strip-proof handoff

- Branch `worktree-wf_193723c6-362-1`, worktree `.claude/worktrees/wf_193723c6-362-1`; work through 085bb458
  (variant role, Fw root import), note, ledger and this file in the commit after it.
- CI runs:
  - webkit-sim 40081936555 (bbd203c7f, fw hero.countdown:strip,morph.countdown:strip): pass; 80 face layers become
    8 strip layers in every zone, finish zone 128/124 to 56/56 (note has the table).
  - breakpoint-gate 40081933958 (bbd203c7f) and 40089874311 (085bb458): both failed in smoke. `fw run --gate`
    sorts the flags (lean/Fw/Wire/Store.lean:45, :111) to `hero.countdown:strip,morph.countdown:strip`; the build
    prerenders only `morph.countdown:strip,hero.countdown:strip` (apps/site/src/entry-server.tsx:23). Budget spent.
- Faithful baseline for the census: webkit-sim 39897814980 (target rewrite, no flags, sha 540130e9; countdown code
  unchanged since).

## Verified
- `lean/scripts/check.sh` green; `Fw.Parts.MorphCountdownStrip` is imported by `lean/Fw.lean`.
- `pnpm --filter gate-breakpoints test` green with the morph.countdown strip variant role.
- Axioms of `same_face_px`, `phase_same`: propext, Classical.choice, Quot.sound; layer theorems none or propext.
- Golden `packages/contracts/golden/parts/morph.countdown.strip.jsonl` is checked by `#guard jsonl == include_str`.
- `apps/site/src/parts/morph.countdown/strip.test.ts` replays it through `createCountdownDriver`: 17 tests pass.

## Open
- Gate verdict (lead dispatch, keeps the order): `gh workflow run breakpoint-gate.yml --ref ci/countdown-strip-proof
  -f engines=both -f fw=morph.countdown:strip,hero.countdown:strip`.
- Flag order fix (outside writes): prerender the sorted key too, or sort before the page lookup.
- Strip backing 3.9 times the faces per digit at y 0; the 12 vs 10 cell model does not explain it.

## Read first
`lean/Fw/Parts/MorphCountdownStrip.lean` (driver model `upd`/`drive`, `same_face_px`, `layers_80_to_16`), then the
note `research/notes/2026/10-2x-countdown-strip-proof.md`.
