# math-r10-fix handoff

State: committed on the worktree branch (see `git log --grep "Task: math-r10-fix"`); `sh lean/scripts/check.sh` green.

## Done
- The 4 `disagree` rows of `research/notes/2026/10-17-math-review-r10-c6fada5.md`:
  - `Fw.Gate.pilotParts`: math now lists per part (id, O, C_orig, C_rw, X, Kn) as ordered lists with full ids
    (`mq.` prefix), the knee expressions e_h / e_g, and the dismissed ids D per part (reasons stay in the source).
  - `Fw.Gate.ScopeGen.unionJson`: math defines the output object (ids of S_∪, ids of K_∪) and matches by id.
  - `Fw.Gate.ScopeGen.hypothesisText`: option B, the docstring says it is a separate fixed paraphrase and the math
    quotes the whole string; the generated `scope.gen.json` bytes are unchanged. `#guard` on its first/last words.
  - `Fw.Measure.Arms.crossLevel_classify`: A_τ, B_τ defined inside the `$$` block.
- `lean/MathViewMain.lean` `WhereLint`: warns on a text segment right after a `$$` block that starts with
  `where` / `with` / `(where` / `(with` and whose inline `$…$` snippet's first symbol occurs in that block.
  Positive and negative `#guard`s. 64 warnings on the current 2171 entries, so it is a warning, not an error
  (printed as `N dangling-where warnings` in the lint summary line).

## Open items
- The 64 hits are real dangling clauses (Obs.Health 29, Gate 16, Console 4, Store 5, others) outside this task's
  files. Fix them by moving each clause into its `$$` block, then flip `WhereLint` to an error in `main`
  (append `wheres` to `bad`). A few symbol lists are noisy (`true`, `STALE`): the lint takes each snippet's first
  word, not only left-hand sides.
- Not caught: notation clauses whose snippet has no name token (`Fw.Gate.digitsVal`, `$\dot-$`).

## Read first
`lean/MathViewMain.lean` (ShadowLint, WhereLint, main), `lean/MathView.lean` (`mathBlocks`, `english`: why text
after `$$` is dropped).
