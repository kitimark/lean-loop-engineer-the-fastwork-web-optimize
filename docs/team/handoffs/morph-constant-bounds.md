# morph-constant-bounds (part-builder) handoff

- Branch `worktree-wf_966da1fd-1d2-1`, worktree `.claude/worktrees/wf_966da1fd-1d2-1`, CI branch `ci/morph-constant-bounds`.
- Final design commit b4cd0105 (pushed to the CI branch); results commit 3157d260; then a merge of main.
- Runs (4 of 4 dispatches used): breakpoint-gate first design 39744563175 FAIL (wrapper element); webkit-sim base
  39744614747 pass; webkit-sim first design 39744653093 pass; breakpoint-gate final design 39747969466 pass.

## Verified
- Lean `lean/Fw/Parts/MorphConstBounds.lean`: `paint_eq`, `visible_iff`, `pivot_same`, `inset_width_eq`, `backdrop_eq`,
  `varBox_rest`, `varBox_const`, `end_same`, `off_nonneg`, `orig_resizes_h/w`, `colW_mono`, `pitch_scaled_ne`; golden
  `packages/contracts/golden/parts/morph-const-bounds.jsonl` (162 rows, `#guard`).
- Site: `morph.panel` variant `const-bounds`: class `cb` on the panel, CSS under `:global(.is-morphing) .cb`, no extra
  element. `const-bounds.golden.test.ts` evaluates the CSS against the rows. Site test, typecheck green.
- Gate both engines on the final design: pass. Ledger n=45, preset, footprint, note, `results/morph-constant-bounds/report.json`.

## Open
- The final design has no webkit-sim run (cap spent on the first design). Command:
  `gh workflow run webkit-sim.yml --ref ci/morph-constant-bounds -f target=rewrite -f lag=true -f cost=on -f fw=morph.panel:const-bounds`
  (base 39744614747 is valid for it); reduce both with `packages/measure-webkit/src/lag/cli.mjs cost-report`.
- PathPix has no lane code; IOSurface creations are not recorded by the lane.

## Conventions
- Golden regen: copy MorphConstBounds.lean without the `include_str` line into the scratchpad, add
  `def main : IO Unit := IO.print (Fw.Parts.MorphConstBounds.boundsJsonl ())`, `lake env lean --run`.
- Edit source, then `part-footprint.mjs --write`, `Fw.Preset.Gen.run []`, `ContractsGolden --rows/--diff` before a dry land.
- Read first: `research/notes/2026/10-2x-morph-constant-bounds.md`.
