# exit-scoped-var handoff

State: branch `worktree-wf_f4cccc1d-568-1`, round 3 (final design round, text only) at ROUND3 on main merge 8767921b;
round 2 code at eca2efc2; CI copy `ci/exit-scoped-var` at fad89503. Note: `research/notes/2026/10-20-exit-scoped-var.md`.

Verified:
- `hero.exit:scoped`: the variant registers both exit properties with `inherits: false`. The stage gets
  `data-exit-scope`, and 7 gated rules pass the values down by `inherit` on the chain classes.
- `Fw.Engine.Restyle` models the Chromium clone path per node (flags vars, slow, hidden, inh, explicit, reads).
- Section Scoped of `Fw.Parts.HeroExitOpt`: `cr_units` 99 / 9 and 172 / 17, `wk_units` 123 / 9 and 215 / 17,
  `narrow_delta` = 90, `readers_exact`, `chain_covers`, `defaults`, `reduced_scatter`, `scatter_eq`.
- Golden `hero.exit.scoped.json` (stage defaults, trees, units; `zone` is the swipe-v1 window 10-103 with 93 write
  frames, model totals only); `--check` passes in check.sh.
- `scoped.test.ts` derives the flags from the CSS over the SSR DOM at 15 widths. It checks the trees, units, readers,
  inherit rules and stage defaults against the golden.
- MEASURED Δ per exit-write frame 90-91 (model 90), one Δ 56 frame per profile at scrollY ≈ 890 (timing matches the
  `pointer-events: none` write; size not derived); per-writer split not measured. Exit range by scrollY (< 950).

Open:
- elementCount is quarantined, and the WebKit win is source-only (accepted limits).
- The per-writer split and the 7-node question need a per-pass elementCount dump (follow-up
  chromium-per-pass-elementcount). Restyle units are validated only as between-arm deltas.
- Run `node scripts/refs-fetch.mjs chromium` to materialise core/dom (element.cc, document.cc) before checking cites.
- The land-inputs test fails 2 rows on main too (gate-breakpoints, measure-webkit); this branch touches neither.

Conventions: a new reader must sit on a chain class (`scoped.test.ts` fails otherwise). A new chain class goes into
`inheritRules` and `heroTree`; then regenerate with `cd lean && lake env lean --run scripts/ExitScopedGolden.lean >
../packages/contracts/golden/parts/hero.exit.scoped.json`.

Read first: the note, then `lean/Fw/Engine/Restyle.lean`, then section Scoped in `lean/Fw/Parts/HeroExitOpt.lean`.
