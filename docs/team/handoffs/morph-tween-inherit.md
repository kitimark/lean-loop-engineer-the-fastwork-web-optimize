# morph-tween-inherit (handoff)

State: branch `worktree-wf_eaaf093f-63e-1`, CI `ci/morph-tween-inherit`. f1dd18a5 (`--morph` inherited), efa737cf
(`--morph-fade` registered, gated), 05f64847 (ledger, handoff); fix round 1 (golden `#guard`, wording) last commit.

## What changed
- `lean/Fw/Parts/MorphTweenOpt.lean` section MT-R: `seenAt`, `readers` (depths entered by hand, not checked against
  the DOM), `needsInherit`, `origInheritsOf`, `registrations` (`--morph`, `--morph-fade` inherit; flags do not),
  `sees_iff`, `registrations_rule`, `registrations_see`, `panel_blind_without_inherit` (the bug), `morph_scope_eq`
  (same recalc set and values as the original per inherited property; the waapi arm's extra `--morph` on the platform
  section hits a subtree both arms invalidate through `--morph-fade`, Chromium computed_style.cc:472-475@f842f52).
- `goldenJsonl` (11 predictions, 4 registrations, 7 readers) equals the committed jsonl (`#guard`, `include_str`).
- TS: `REGISTRATIONS`, `PROP_FADE` in `waapi.logic.ts`, used by `index.tsx`; `waapi.golden.test.ts` checks them
  against the golden and scans the CSS modules for reader class names (not depths).

## Verified
- check-fast, axioms standard, apps/site tests + typecheck, ci-paths, runner land-inputs (numbers in the report).
- Gate on efa737cf, runs 39187616419 (default) and 39187623386 (waapi): morph and platform rows pass in every
  reachable cell (webkit: 2 columns UNREACHABLE 4, same on both arms). Chromium pass: default 7048 pass, 1 fail,
  8 excused of 7056; waapi 7049 pass, 0 fail, 7 excused. Webkit incomplete on both (6763 pass, 0 fail, 291 excused),
  only matchMedia phone-rotation not-comparable. Waapi run 39184893562 (before the `--morph-fade` fix) failed the
  chromium platform row on the `--morph-fade` serialization.

## Open
- `Fw.Ops.Premise` `css.inherits-false` still lists `waapi_vis` (should cite `panel_blind_without_inherit`).
- INFERRED: on the waapi arm `data-fw-morph` flips at a tween's end, not on the threshold frame (nav/index.tsx:123).
- The gate checks m = 0 only and cannot see the panel bug. Engine-check 39131146372 measured the inherits:false build.
- Golden rewrite: one-off `lake env lean --run` writing `Fw.Parts.MorphTweenOpt.goldenJsonl`.

Read first: MorphTweenOpt.lean section "MT-R", then waapi.golden.test.ts describe "registrations".
