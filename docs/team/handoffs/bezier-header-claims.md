# Handoff: bezier-header-claims

State: branch `worktree-wf_f3657445-cd9-1`, one commit on top of `b028c434` (see `git log -1`). Docstrings only, no new
theorems, no proof or code change.

## Done
- `lean/Fw/Parts/Bezier.lean` header (2 lines): for `0 < t < 1`, `ease` is `y` at `bisect` (definition), the midpoint of the
  40-step bracket (`bisect_eq_mid`); `bracket_cut` for every such `t` when `0 ≤ x_1, x_2 ≤ 1`; with all control values in
  `[0,1]`, core `ease_err` (`3 / 2^41`) at a rational root `s ∈ [0,1]`; at the real root `FwMath.Bezier.ease_err`
  (`3 / 2^41`) and `ease_exact` (unique root, `1 / 2^40`, `3 / 2^40`), both in lean-math. The "solves `x(s) = t`" wording is gone.
- Docstrings now state each theorem's hypotheses (`bracket_inv`, `bisect_value_err`, `coord_lipschitz`, `ease_nonpos`,
  `ease_ge_one`, `ease_mem`, `corners_pos`, `slope_pos`); unproved side remarks removed (Bernstein weights, "never
  overshoots" for both curves, "approximation, not the exact `s`"); `q00..q11` and `bracket` cite `slope_mix` /
  `bisect_eq_mid`.
- `lean-math/FwMath/Bezier.lean` `ease_exact` docstring: "The header claim of" became "The real-root claim the
  `Fw.Parts.Bezier` header cites" (the old header text it referred to is gone).

## Verified
- `sh lean/scripts/check.sh` exit 0 (all lean/ gates green).
- lean-math not built locally (docstring-only edit); its CI lane triggers on `lean/Fw/Parts/Bezier.lean`.

## Checked, unchanged
- Importers (`OverlayDrawer`, `OverlaySignup`, `NavEarnOpt`, `OverlayGolden`), TS `logic.ts` comments, handoffs and
  `research/notes/2026/10-21-mathlib-poc.md`: none claims more than the theorems (the note quotes the old header as history).

## Open
- Optional `bisect_close` lemma not added (no header sentence needs it).
