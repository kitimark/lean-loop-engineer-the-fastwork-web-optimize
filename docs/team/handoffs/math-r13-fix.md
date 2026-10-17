# math-r13-fix handoff

## State
- Base `79606bb` (math review r13 at `0cee322`). One commit on the worktree branch (see `git log -1`).
- All non-Land disagree rows of `research/notes/2026/10-18-math-review-r13-0cee322.md` (69) fixed. `Fw.Console.Land.*`
  rows are left to land-hardening.
- Only docstrings changed: no Lean definition, statement or proof changed (no note showed a Lean bug).
- `sh lean/scripts/check.sh` green: mathview lint 0 failing (ShadowLint and WhereLint hold), standard axioms only.

## Conventions followed
- The math says exactly what the Lean says: Rat/Nat semantics written out (`\dot-` for Nat subtraction, `\lfloor\cdot\rfloor_{\mathbb N}`),
  Option shown as `some(d) ? … : null` or a `none` case, empty-list cases stated.
- Long golden tables are written as exact comprehensions `[f | a ∈ A, b ∈ B]` (generators run left to right, outer to inner)
  joined with `\mathbin{+\!\!+}`; helper lists are named in a trailing `\text{with } …` line *inside* the `$$` block
  (WhereLint forbids a where/with clause right after `$$`). No "lines" placeholders.
- Whole-table defs (`Gate.Scope.pilotParts`, `PlatformEntries` entry tuples) list every entry in source order.

## Files touched
- lean/Fw/Parts/{PlatformEntries,PlatformGlint,PlatformGolden,PlatformSection,PlatformMarquee,PlatformSweep,Golden,
  HeroExitOpt,MorphMountOpt,MorphPanelOpt,PainNotes}.lean
- lean/Fw/Engine/{Chromium,WebKit}.lean, lean/Fw/Gate/Scope.lean, lean/Fw/Plan/Lint.lean

## Open items
- `PlatformEntries` Bez and View structure docstrings still repeat their `$$` block three times (not a review row).
- Non-failing mathview "binder not quantified" warnings remain on theorems outside the r13 rows (e.g. `bis_inv`,
  `solve_mem`, `progress_mem`, `cycView_periodic`, `lenAt_le`, `interp_between`, `pos_periodic`).

## Read first
- The r13 note above, then `lean/MathView.lean` (english = text before the first `$$`; ShadowLint, WhereLint).
