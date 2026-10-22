# compose-layers-lean (lean-prover)

State: branch `worktree-wf_a9545149-400-1`, worktree `.claude/worktrees/wf_a9545149-400-1`, commits cf333e33..HEAD,
round 3 fixes at 60bc8ff4 and the morph test fix after it, main 393f8223 merged at 6ba33212. No CI runs.
Round 3: reviewer counterexample `exShared` (two picks gave `[]`) now gives `["clash"]`.
After the merge: `part-footprint.mjs --check` clean, `ContractsGolden --diff/--rows` regenerate nothing, `--check`
green, `sh lean/scripts/check.sh` green, site, console-api, runner and ci-paths tests green, dry land run.

Done:
- `lean/Fw/Console/Layers.lean`: units, `clash` (I1-I4, `clash_symm`); `Unit.reads` covers every record of each
  picked variant, shared files included (round 3, finding 1; `#guard`s over `exShared`); expansion (`expand_one_owner`,
  `expand_idem`); closed refusal list (`Refusal`, one theorem per code); `fixOf`; grade E/E1/Q/L, where `E1` needs a
  `lean` name (round 3, finding 2; `varGrade` guard without one is `Q`); premises; fwl search (`link_resolves`);
  `declaredLayerErrors == []` over the extracted layer ids (okChar).
- `lean/Fw/Engine/Compose.lean`: `lego_swap_visible_set`, `lego_swap_visible_units`.
- `lean/Fw/Wire/Layers.lean`: `console.compose` with `arms`; variant files come only from `filesOf` (finding 3).
- Extractor `apps/site/scripts/part-footprint.mjs`: per-record `variants`, `variantFiles`, `layerDecls`.
- Goldens `golden/console/layers.jsonl` (one row changed in round 3: a faithful pick on `hero` beside `hero-pause`
  now also reports `clash`), `layers-search.jsonl`.
- Site test `layers.component.test.ts`: every listed variant x impl; the morph instance over every `hero.countdown`
  variant x impl with `inverse` and fwId `morph-countdown-clock` (finding 4).

Accepted limits: no site change, no CI measurement, Q/L cells unmeasured; `hero.countdown:*` and `hero.exit:threaded`
refused as not extractable.
Open (follow-ups): review findings 5 (lemma tying `coverReasons = []` and no clash to `Indep` in `look_E_sound`),
6 (JSONL rows for every refusal code), 7 (`fix_allowed`); console-api glue for `arms`, ledger `changes` column, CSS
extraction, branch-level attribution, files for the other parts, site reading `?fwl=`.

Read first: `lean/Fw/Console/Layers.lean` header, `lean/Fw/Wire/Layers.lean`, `layersCases` in `lean/Fw/Ops/Golden.lean`.
