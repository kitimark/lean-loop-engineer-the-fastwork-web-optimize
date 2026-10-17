# where-cleanup handoff

State: committed on the worktree branch (`git log --grep "Task: where-cleanup"`); `sh lean/scripts/check.sh` green,
ShadowLint 0, quantifier warnings unchanged (92 / 521).

## Done
- 63 dangling `where`/`with` clauses outside `Fw.Measure` moved into their `$$` blocks (Obs.Health 29, Gate 16,
  Console.Alert 3, Board 1, Store 6, Serve 2, Site 2, Ops 2, Parts 1, Plan 1), plus 7 `Here $o = …$ and $\Sigma = …$`
  clauses in Obs.Health (same defect, not caught by the lint). Shape: `…,\quad \text{where } X = …$$`, `\begin{cases}`
  for "X, or ε when it is ⊥", an `aligned` row (`\\ & \text{where …}`) for aligned blocks. Docstrings only.
- `lean/MathViewMain.lean` `WhereLint.definedSym m after`: left-hand sides only (first name before `=`, `\coloneqq`,
  `\equiv`, `\iff`; a relation-free snippet only when the prose goes on with `is`/`are`). `#guard`s for `true`/`STALE`.
- WhereLint is an error (exit 1, counted in `failing (…, N dangling-where)`), except `Fw.Measure.*` (`warnOnly`,
  marked `TODO(where-cleanup)` in `warnOnly` and in `main`), still a warning.
- Avoid `p\ (\bot …)` after a bound `p`: ShadowLint reads it as `p(…)`; write `p \text{ (} \bot \text{ …)}`.

## Open items (Fw.Measure, owned by zone-baseline-lean)
- `Fw.Measure.SelfCheck.maxDiff_zero_iff`: `(with $r[i] = 0$ for $i \ge |r|$, as in diffVs)` after the block (the 1
  remaining warning).
- `Fw.Measure.Snapshot.census`: `where $|[\,x \in X \mid P(x)\,]|$ is the length …` and the `(the second-to-last entry
  …)` note: a notation clause; the old first-word rule flagged it (`l`), the LHS rule does not.
- When both are fixed: delete `warnOnly` and the partition in `main` (all modules error).
- Not caught by the lint: `Here …` clauses and notation-only clauses (`Fw.Gate.digitsVal`, `$\dot-$`).

## Read first
`lean/MathViewMain.lean` (WhereLint, main), `docs/team/handoffs/math-r10-fix.md`.
