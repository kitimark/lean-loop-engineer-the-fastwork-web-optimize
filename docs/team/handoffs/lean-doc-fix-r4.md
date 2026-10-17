# Handoff: lean-doc-fix-r4 (fixes from math review round 4)

State: all 71 disagreements of `research/notes/2026/10-17-math-review-r4-740b06c.md` applied, docstrings only (no
statement or proof changed; no correction asked for a Lean change). Based on main 226c35b. `lean/scripts/check.sh`
green; page rebuilt: 747 agree / 84 stale (71 + 13 below) / 0 pending.

## Docstring edits
- 66 rows: the `$$` block replaced by the review's corrected math (the span from its first to its last `$$`, so
  `insKey` now has two blocks). 5 English-only rows (`Class.le`, `stable_frames_unsound`, `gap1000`,
  `null_prob_3v3`, `null_prob_5v5`) and the English of `valAt_cons_zero`, `inv_foldl`, `inv_stats`.
- Trailing notes added after the math for `Tally`, `Reduced`, `WZone`, `CRow`, `symDiff_terms_comm`,
  `length_rows_tag`, `framesAt_spec` (the review's parenthetical remarks).
- Beyond the 71 (free variables in Classes/Tolerance, ∀ added; round 5 should re-check): `mem_pairVals`,
  `of_mem_pairVals`, `le_maxOf`, `maxOf_le`, `le_obs`, `obs_le`, `valAt_cons_succ`, `valAt_nil`,
  `forall_nat_split`, `typeOk_sound`, `noMoreWork_sound`, `promise_total`, `noMoreWork_cost` (also its cost
  selectors written `e |-> e.v'`).

## Quantifier lint (`lake exe mathview --lint`, warning only, never fails)
- `MathView.lean`: `Entry.binders` (data binders, explicit and implicit, incl. those after the colon),
  `binderZones`, `warnEntry lenient`. A binder is quantified when its name is in a `\forall`/`\exists` zone, or in
  the list before `\in`, `\notin`, `\subseteq` or `:`. Lenient mode also accepts the initial letter in either case
  (`fs` as `F`) and `s`/`l`/`k` as `\sigma`/`\ell`/`\kappa`.
- Numbers (lenient / strict-name): before the fixes 181 / 307, after 71 / 236 (831 declarations, 380 theorems).
- Remaining 71: about 45 are real free `e` (BreakpointFacts `*_iff`, `e \models ...`) and similar in EngineScroll
  (`role`), Flags, Cost, Verdict; those are outside this round. False positives: renames the heuristic cannot
  map (`st` written `(\ell,h,b)`, `l` written `x_1..x_m`, `fs` written `R`, `stack`, `target`), bound names inside the
  statement after the colon (`p`, `r`). It misses a name used in a loose position (e.g. only on the right of `=`).

## Open items
- Fix the remaining real free variables (BreakpointFacts `e`, Flags `resolve_sound`, EngineScroll `role`) in a later
  round; then flip the lint to an error.
