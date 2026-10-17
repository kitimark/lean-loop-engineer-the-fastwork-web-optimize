# proof-people-deck handoff

**Files:** `lean/Fw/Parts/PeopleDeck.lean`, one import in `lean/Fw.lean`, `packages/contracts/golden/engine/people-deck.jsonl`
(20 rows, all `=o`, generated from `goldenText`; regenerate with a driver
`def main := IO.FS.writeFile "../packages/contracts/golden/engine/people-deck.jsonl" goldenText` run by `lake env lean --run` from `lean/`).

**State:** proved, no sorry, standard axioms; `sh lean/scripts/check.sh` green. Commit: see `git log -- lean/Fw/Parts/PeopleDeck.lean`.

**Theorems.**
- Vis (exact ℚ): `deck_content`, `cqiShell_eq`, `usedShell_same`, `deck_vis` (VisSame E, every Env, via `c860`).
- Rounding (LayoutUnit 1/64 px, truncation; Chromium `layout_unit.h`@f842f52, WebKit `LayoutUnit.h`@862f17d):
  `crAspectRaw_eq` (Chromium original MulDiv is exact ⌊764r/353⌋), `snap_faithful`, `faithful_nonneg`, `faithful_exact`,
  `snap_exact`, `cr_snap_same`, `wk_snap_same`, `snap_nudged` (robust formula `round(down, 100cqi*764/353 + 1px/45184, 1px/64)`).
- Work: lifted engine `lift ε` (`ratioRelayout` dirties `layout` only), `lift_frameWork`, `deck_le`, `deck_lt`, `deck_cr`,
  `deck_wk`, `deck_run_dominates`, `swipe_eq`, `predict_self`.

**Variant spec fixed here:** in the `c860` block, deck `container-type:inline-size`; shell `flex:0 0 100cqi; width:100cqi;
height:calc(100cqi * 764 / 353); aspect-ratio:auto`. Desktop rules unchanged.

**Open premises.**
1. `Faithful` (float error < 1/353 raw unit): holds for exact/double; a float `Length` (Chromium `length.h:433`) can give
   +1/64 px at heights ≥ 1024 px (IEEE emulation: integer widths 770, 1123, 1187 px). The nudged formula removes the
   whole-unit side condition; part-builder may prefer it.
2. Relayout mechanism of the original (v1 toolbar step, WebKit finger only, 25.7 → 0.4 ms) is UNRESOLVED; the model takes
   `relayout` as a per-frame input. No CI lane has a toolbar step, so no `<o` golden row exists yet.
3. Container width step makes the variant relayout too (`widthStep`, INFERRED); inline-size containment does not change the
   deck width (INFERRED); scene is a function of the shells' used size.

**Read first:** the module docstring of `PeopleDeck.lean`; `MorphMountOpt.lean` golden section (reused types).
