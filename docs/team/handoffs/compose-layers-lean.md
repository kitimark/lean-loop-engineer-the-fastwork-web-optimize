# compose-layers-lean (lean-prover)

State: branch `worktree-wf_a9545149-400-1`, commits cf333e33..HEAD on base e715dcdc. `sh lean/scripts/check.sh` green;
site, console-api and runner tests green; `#print axioms` on every Layers theorem shows standard axioms only.

Done:
- `lean/Fw/Console/Layers.lean`: units (pick, change, layer option), `clash` (I1-I4 links, `clash_symm`), expansion
  (`expandedPicks`, `expand_one_owner`, `expand_idem`), closed refusal list (`Refusal`, one theorem per code), fix
  (`fixOf`, `fix_closed_requires`), look grade E/E1/Q/L (`look_E_sound`, `look_L_of_unit_L`, `option_not_E`),
  premises (`premises_complete`, `snap_drops_C5`, `text_composite_C1`), fwl search (`searchOf`, `link_resolves`),
  `registryErrors`, `decideArm`; `#guard`s on every refusal code over `exPage`.
- `lean/Fw/Engine/Compose.lean`: `lego_swap_visible_set`, `lego_swap_visible_units`.
- `lean/Fw/Console/BuildsOpen.lean`: `?fwl=` entries, `layerErrors` with one theorem per refusal.
- Extractor `apps/site/scripts/part-footprint.mjs`: per-record `variants`, `variantFiles`, `layerDecls` in FootprintData.
- Wire: `lean/Fw/Wire/Layers.lean` (`console.compose` with `arms`; reply without `arms` unchanged), registry `layers`
  for `console.buildsSearch`. Goldens `golden/console/layers.jsonl`, `layers-search.jsonl` (from `Fw.Ops.Golden`).
- okChar: `declaredLayerErrors` (`#guard ... == []`) checks every extracted `layerDecls` id with `validate`; the site
  test no longer parses Lean source (`footprint.test.ts` keeps `layerDecls` equal to the part.json files).
- Site test `layers.component.test.ts` renders every listed variant with every impl, uses fwId `morph-countdown-clock`.

Accepted limits: no site change, no CI measurement, Q/L cells unmeasured; `hero.countdown:*` (branch in a shared
file) and `hero.exit:threaded` (no files listed) are refused as not extractable.

Open (follow-ups): console-api glue for `arms` (TS), ledger `changes` column, CSS declaration/keyframe extraction
(props, will-change, snap paths), unmapped cross-part selectors, branch-level attribution, files for the other parts,
a `fix_allowed` theorem, site reading `?fwl=`, per-variant I2/I4 rows, verdict/hyps for refused arms.

Read first: `lean/Fw/Console/Layers.lean` header, then `lean/Fw/Wire/Layers.lean`, then `layersCases` in
`lean/Fw/Ops/Golden.lean`.
