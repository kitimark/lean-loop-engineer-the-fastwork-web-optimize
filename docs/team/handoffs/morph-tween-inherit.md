# morph-tween-inherit (handoff)

State: branch `worktree-wf_eaaf093f-63e-1`, CI branch `ci/morph-tween-inherit`. Fix commits f1dd18a5 (`--morph`
inherited) and efa737cf (`--morph-fade` registered); ledger note, header docstrings and this file in the last commit.

## What changed
- `lean/Fw/Parts/MorphTweenOpt.lean` section MT-R: `seenAt` (CSS inheritance down a path), `readers` (every reader of
  `--morph` / `--morph-fade` with its depth below the element that sets it), `needsInherit`, `origInheritsOf` (the
  original's unregistered, so inherited, properties), `registrations` (`--morph` and `--morph-fade` inherit, the two
  flags do not), `sees_iff`, `registrations_rule` (inherits = need ∨ original inherits), `registrations_see`,
  `panel_blind_without_inherit` (the bug), `morph_scope_eq` (same recalc set and values as the original for every
  property the original inherits). Engine citations in the section note (Chromium f842f52, WebKit 862f17d).
- `goldenJsonl` ends with 4 registration rows and 7 reader rows; the 11 prediction rows are unchanged.
- TS: `REGISTRATIONS` and `PROP_FADE` in `waapi.logic.ts`, used by `index.tsx`; `waapi.golden.test.ts` checks them
  against the golden and scans nav/morph/platform CSS modules for readers.

## Verified
- check-fast ok (53 s, math-view lint incl.); axioms standard; apps/site 5029 tests + typecheck; ci-paths 32;
  runner land-inputs 35, premises + ledger-merge 78.
- Gate runs 39187616419 (default) and 39187623386 (fw=morph.tween:waapi): morph and platform rows pass in every cell,
  chromium pass, webkit incomplete only for matchMedia phone-rotation not-comparable (unrelated). Before the
  `--morph-fade` fix, waapi run 39184893562 failed the chromium platform row on the `--morph-fade` serialization.

## Open
- `Fw.Ops.Premise` `css.inherits-false` still lists `waapi_vis`; it should point at `panel_blind_without_inherit` /
  `registrations_see` (outside this task's writes).
- No golden generator script: rewrite with a one-off `lake env lean --run` of
  `IO.FS.writeFile ... Fw.Parts.MorphTweenOpt.goldenJsonl`.
- INFERRED, not checked: on the waapi arm `data-fw-morph` is written only at a tween's start and end (`hint`), so the
  panel's discrete attributes (nav/index.tsx:123) would flip at the tween's end, not on the threshold frame.
- The gate never pushes the morph (m = 0 only); it cannot see this bug or the fix.

Read first: MorphTweenOpt.lean section "MT-R", then waapi.golden.test.ts describe "registrations".
