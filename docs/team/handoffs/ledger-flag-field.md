# ledger-flag-field handoff

State: branch `worktree-wf_02570387-b4e-1`. Commits: 5050c274 (ledger `flags`, Lean matching and errors), f9e1c259
(goldens, TS reader), 6ccda4d7 (compose doc), then this handoff. `sh lean/scripts/check.sh` green; axioms standard.

Verified:
- Every one of the 70 ledger rows has `flags` (list, `[]` for none), inserted after `status`; no other field changed.
- `Fw.Console.Compose`: `matchRow` reads `flags` only; `explicitKeys`, the text rules, `extraRows` and `varRows` are gone;
  card rows are `rowsFor`. `flagErrors` (missing field, unknown key, `flag` not in `flags`) and `crossErrors` (a superseding
  row lacking a flag of the row it supersedes, part of `supersedeErrors`) fail `console.compose`.
- Theorems: `mem_rowsFor`, `flagErrors_nil_iff`/`_missing`/`_unknown`/`_flag_not_in`, `crossErrors_nil_iff`,
  `supersedeErrors_nil_iff`/`_cross`/`_nil_about`, `rowsFor_successor`, `rowsFor_reaches_live`, `partOut_rows_about`,
  `partOut_superseding`.
- Real ledger: the new reply equals the pre-change `fwcore` reply byte for byte (golden case "the real registry and
  ledger", `cmpReal` in `Fw.Ops.Golden`). Every older compose golden reply is unchanged.
- Tests: console-api 685, contracts 7, ci-paths 49, runner land-inputs 55, all pass.

Open items (follow-ups):
- Rows 12, 15 name `morph.panel:rest`, not in `part.json`; rows 40, 42, 44 (engine.scene) name no registered variant.
  All are `[]`; see the table in `docs/team/tools/compose.md`.
- "Other findings" still groups by the `part` text (`rowParts`); it decides no class.
- `Fw.Preset.Gen` still reads the single `flag` field; `flags` is Compose-only.

Conventions: a new ledger row needs `flags`; a superseding row keeps every flag of the row it supersedes.
Read first: `docs/team/tools/compose.md`, `lean/Fw/Console/Compose.lean` (sections Flag errors, Superseded rows).
