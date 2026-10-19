# exit-scoped-var handoff

State: branch `worktree-wf_f4cccc1d-568-1` at 64716c9f (round 2 code at eca2efc2, main merged; CI copy
`ci/exit-scoped-var` at fad89503). Note: `research/notes/2026/10-20-exit-scoped-var.md`.

Verified:
- `hero.exit:scoped`: the variant registers both exit properties with `inherits: false`. The stage gets
  `data-exit-scope`, and 7 gated rules pass the values down by `inherit` on the chain classes.
- `Fw.Engine.Restyle` models the Chromium independent-inherit clone path per node. The flags are vars, slow, hidden,
  inh, explicit and reads; the source lines are cited in the docstrings and the note.
- `Fw.Parts.HeroExitOpt` section Scoped:
  - `cr_units`: narrow 99 / 9, wide 172 / 17. `wk_units`: 123 / 9 and 215 / 17. `narrow_delta` = 90.
  - `readers_exact`, `chain_covers`, `defaults`, `reduced_scatter`, `scatter_eq`.
- Golden `hero.exit.scoped.json` (stage defaults, trees, units, zone 9306 / 846); `--check` passes in check.sh.
- `scoped.test.ts` derives the flags from the CSS over the SSR DOM at 15 widths. It checks the trees, units, readers,
  inherit rules and stage defaults against the golden.
- MEASURED median per frame: 136 → 45 (Δ 90-91; the model gives 90). The scoped split is 9 for the exit writer (model)
  and 36 for others (measured difference).

Open:
- elementCount is quarantined, and the WebKit win is source-only (accepted limits).
- The per-writer split needs a per-pass trace dump in the harness.
- The land-inputs test fails 2 rows on main too (gate-breakpoints serve.mjs reads `apps/site/dist/aot`; measure-webkit).
  This branch touches neither.

Conventions: a new reader must sit on a chain class (`scoped.test.ts` fails otherwise). A new chain class goes into
`inheritRules` and `heroTree`; then regenerate with `cd lean && lake env lean --run scripts/ExitScopedGolden.lean >
../packages/contracts/golden/parts/hero.exit.scoped.json`.

Read first: the note, then `lean/Fw/Engine/Restyle.lean`, then section Scoped in `lean/Fw/Parts/HeroExitOpt.lean`.
