# Handoff: morph-tween-curve (MT1, MT2, RG8)

Branch worktree-agent-ad6546f8244a24f2d; commit in the report to the lead.

## What is there
- `lean/Fw/Parts/MorphTweenOpt.lean` (imported from `lean/Fw.lean`), Mathlib-free, all `Rat`:
  - `bez` (Bernstein form), `Coeffs`/`coeffs` (engine c, b, a), `horner` (engine Horner sampling);
    `horner_eq_bez`: the engine polynomial is the Bézier for any control coordinates.
  - `coeffs_x` = (1, 0, 0), `coeffs_y` = (3, -3, 1) for `cubic-bezier(1/3,1,2/3,1)`.
  - MT1 `bezier_eq_ease` (X(s) = s, Y(s) = 1-(1-s)^3 for every s), `curveY_eq_ease` (= `MorphTween.ease` on [0,1]),
    `solver_exact_zero` (exact solve gives the ease exactly).
  - MT2 `solver_exact` (t, x in [0,1], |X(t)-x| < eps gives |Y(t) - ease x| <= 3 eps), via `curveY_sub` and `slope_mem`.
  - Over R: not done (no Mathlib in this project).
- `apps/site/src/parts/morph.tween/curve.golden.test.ts` (RG8): IEEE double replica of Chromium `cubic_bezier.cc`/`.h`@f842f52
  and WebKit `UnitBezier.h`@862f17d (fetched by raw curl at the pinned sha; not in the sparse clones), 10^4 points.
  - MEASURED (Node): cx === 1.0, bx = ax = 0 in double; every solve exits on the first Newton test;
    max |engine - (1-(1-x)**3)| = 3.33e-16 for both the Chromium eps 1e-7 and the WebKit eps 1/(1000*0.68); max |t-x| = 1.11e-16.
  - Print the numbers with `pnpm --filter ./apps/site exec vitest run src/parts/morph.tween/curve.golden.test.ts --silent=false`.

## Open items
- Premise (INFERRED, untested): both CSS parsers keep `cubic-bezier` numbers as the doubles JS prints for 1/3, 2/3
  (the test only checks that `String(1/3)` round-trips in JS).
- MT3/MT4 (waapi_eq_tween, flags_same_frame) and MT-W are separate tasks; reuse `curveY_eq_ease` and `solver_exact`.
- wt-prep note: an idle `lean --server` in the main lean dir makes `scripts/wt-prep.sh` skip the clone; I copied
  `lean/.lake` by hand with `cp -c -R`.

Read first: the module header of `MorphTweenOpt.lean`, then the test's header comment.
