# exit-scoped-var handoff

State: branch `worktree-wf_f4cccc1d-568-1` (CI copy `ci/exit-scoped-var`); result note
`research/notes/2026/10-20-exit-scoped-var.md` holds the measured numbers and run ids.

Verified:
- `hero.exit:scoped` (design 2 of R1): the variant registers `--exit-opacity` and `--exit-scatter` with `inherits:
  false` in its effect, the stage gets `data-exit-scope`, and 7 gated rules pass both properties down by `inherit` on
  the chain classes. The driver and the stage CSS are unchanged.
- Lean: `Fw.Engine.Restyle` (`scoped_le`, `wk_le_cr_units`, `consumer_eq`) and section Scoped of
  `Fw.Parts.HeroExitOpt` (`cr_units` = `wk_units` = 21, `faithful_units` 275, `defaults`, `reduced_scatter`,
  `consumer_eq_scoped`). `Fw.Site.Stage.exit_owner_never_written`: no stage plan writes a rest value on hero.exit.
- Golden `packages/contracts/golden/parts/hero.exit.scoped.json` (check.sh job "exit scoped golden check");
  `apps/site/src/parts/hero.exit/scoped.test.ts` checks the reader list against the CSS and the tree against the SSR DOM.

- MEASURED (zone 10-103 elementCount): swipe 13145 → 4730, touch 12035 → 4328 (-64%). The breakpoint gate passes
  every hero.exit cell in both engines.

Open:
- elementCount is quarantined; the lead admits the win or keeps it as proved-unmeasured.
- Two gate cells fail on main as well and do not involve hero.exit: commission in the pain sweep and WebKit
  phone-rotation NC. See the note.
- WebKit win is source-only (no WebKit elementCount lane).

Conventions: a new reader of an exit property must sit on a chain class (scoped.test.ts fails otherwise); adding a
chain class means adding it to `inheritRules` and the tree, then regenerating the golden
(`cd lean && lake env lean --run scripts/ExitScopedGolden.lean > ../packages/contracts/golden/parts/hero.exit.scoped.json`).

Read first: the note, then section Scoped in `lean/Fw/Parts/HeroExitOpt.lean`.
