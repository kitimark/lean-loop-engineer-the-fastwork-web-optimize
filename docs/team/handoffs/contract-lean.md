# contract-lean handoff

State: branch `worktree-wf_ed01bde3-026-2` (page-root-clip merged in), commit "contract-lean: Fw.Parts.Contract".

Delivered
- `lean/Fw/Parts/Contract.lean`: `Signal`, `Group` (g1-g5, solo), `PartSpec` (34 rows, one per dir under
  `apps/site/src/parts`, cites in each row docstring), `i1`-`i4`, `independent`/`Independent`, `groupKey`,
  `scenariosFor`, JSON render, `run`. Theorems by `decide`: `parts_ids`, `groups_partition` (G4 excluded),
  `g4_couples`, `layoutLocal_iff`, `moved_eq`, `scenarios_known`. Axioms: propext only.
- `lean/scripts/ContractsGolden.lean` (`--contracts`, `--scenarios`, `--check <c> <s>`; the check also needs
  `profiles/<id>.json` next to the scenarios file). Goldens: `packages/contracts/golden/parts/contracts.gen.json`,
  `packages/measure-chromium/scenarios.gen.json`. Job "contracts golden check" in `lean/scripts/check.sh`.

Verified: `lake build` ok, mathview lint ok, check-partial and check-imports ok, golden check exit 0.

Code-wins findings (`moved_eq`): 20 rows differ from the plan. G4 and G5 merge into G2, except engine.scroll: its
variant reschedules every registered callback, so it couples to all of them (`g4_couples`) and stays page-level.
commission joins G2 by I4: its callback ends with a style write and platform starts with a rect read. morph.panel,
morph.columns and morph.countdown are solo: the panel host sets `--morph: 0` itself and gets no `writerRef`.
nav.langMenu joins G2 because it reads `is-on-dark`. pain.notes joins G1 because it writes the pain section. G3 and
G5 are empty. There is no `push` profile, so G2 maps to swipe-wheel-v1 and swipe-touch-v1.

Conventions: `cssVar`/`className` names are `<name>/<owner part>`. `targets`, `outputs` and `listAccess` are
frame-time may-traces under the faithful engine. Mount, resize and click writes are excluded (click/key writes go in
`onEvent`). Hover-gated people.o `place` is excluded because no profile hovers.

Open: I5 is recorded, not proved. I4 checks pairs only and does not model clock-subscriber order. When
morph-group-integrate hosts the panel in nav, the morph.panel/countdown rows must change, which regenerates the goldens.
Read first: the `i4` and `groups_partition` docstrings, then `moved_eq`.
