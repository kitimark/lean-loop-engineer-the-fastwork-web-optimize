# contract-lean handoff

State: branch `worktree-wf_ed01bde3-026-2` (main merged), final design round commit "contract-lean final round:
premise field, people.o regroup, g4_iff".

Delivered
- `lean/Fw/Parts/Contract.lean`: 34 `PartSpec` rows, `affects`, `effOut`, `i1`-`i4`, `independent`, derived `pageLevel`,
  `groupKey`, `scenariosFor`, `premise`, JSON render, `run`. Theorems by `decide`: `parts_ids`, `groups_partition`,
  `g4_couples`, `scroll_writer_couples`, `scroll_writers`, `pagelevel_env_only`, `g4_iff` (new), `layoutLocal_iff`,
  `moved_eq`, `scenarios_known`. Axioms: propext at most.
- Goldens: `packages/contracts/golden/parts/contracts.gen.json` (new top-level `"premise":"declared-rows-unverified"`),
  `packages/measure-chromium/scenarios.gen.json` (people.o groupKey g1). Job in `lean/scripts/check.sh`.
- Final round: people.o reads clock and rect people.card (`#future-heading`), writes `data-o-stack`; people.card reads
  it (card.module.css:170, width ≤ 860px) so people.o joins G1 (moved: 21 rows). people.carousel reads rect people.

Verified: `lake build Fw.Parts.Contract` ok, golden `--check` exit 0, `sh lean/scripts/check.sh` green (28 s).

Premise: everything is certified relative to the declared rows; row completeness is unverified (split task
contract-rows-from-code / part-io-lint). Stated in PartSpec, groups_partition, scenariosFor and the golden.

Known gaps (data, not patched): pain.notes `cardSelector` (index.tsx:40) and nav.hitTest `EXCLUDE_SELECTOR`
(logic.ts:19) match no element under CSS-module renaming (apps/site/scripts/build.mjs:41); faithfulness findings for
those parts. Rule for the rows task: rows declare the code's intended selectors. Any further undeclared coupling a
reviewer finds is appended here and to contract-rows-from-code's first cases.

Conventions: `cssVar`/`className` names are `<name>/<owner part>`; rows are frame-time may-traces under the faithful
engine; accepted limits listed in the `PartSpec` and `groups_partition` docstrings.

Open: contract-rows-from-code (code-derived footprints); morph-group-integrate edits morph.panel/countdown rows;
contract-compose-bridge (`Independent P Q → Indep`).
Read first: `affects`, `i3`, `pageLevel`, the `groups_partition` docstring, then `moved_eq`.
