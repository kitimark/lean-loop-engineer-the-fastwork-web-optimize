# Writes closure lint

- Branch `worktree-wf_29c7f846-55b-1`, worktree `.claude/worktrees/wf_29c7f846-55b-1`, base main f3248e954.
- Last code commit 7ba9e279b; no CI runs (check.sh, runner tests, ci-paths, dry land all pass locally).

## What exists
- `lean/Fw/Plan/WritesClosure.lean`: `kindOf` (golden / script / module / workflow / other), `freshOf` (new / existing /
  open against tracked files, matched with `Fw.Ops.PathCheck`), `implied`, `required` (new artefacts), `mayNeed` (open
  globs), `missing` / `missingOpen` = `violations (landScope ...)`, `findings` (`writesClosure` error,
  `writesClosureOpen` warn). Theorems: per-kind iffs, `required_eq_nil_iff`, `required_{golden,script,module,workflow}`,
  `mem_missing_iff`, `missing_nil_iff_land_ok` (lint passes exactly when `landVerdict` of the closure is `.ok`), `one_call`,
  `done_silent`, `error_iff`. `#guard`s replay graph rows r322, r323, r325, r328, r330, r331, r334 before/after.
- Golden `packages/contracts/golden/plan/writes-closure.jsonl` (`lake env lean --run scripts/WritesClosureGolden.lean
  [--check]`), check.sh job, lean.yml input row in `Fw.Ci.Trigger`, triggers.jsonl regenerated.
- `apps/runner/src/plan-closure.ts`: TS mirror of kind/fresh/implied (replayed against the golden in
  `test/plan-closure.test.ts`); fwcore `console.landScope` answers the scope check, one process per lint.
- `fw plan lint` merges the closure findings; errors exit 1.

## Verified
- Live graph at f3248e954: 38 `writesClosure` errors on 33 open rows (mostly `lean/Fw/Ci/Trigger.lean` for a new
  golden; `ci-offload-checks`, `touch-first-scroll-probe`, `safari-macos-ci` miss CI tables), 81 open-glob warnings.
- Accepted limits: tool docs (r331 `docs/team/tools/*.md`) and existing files later named (r330, r334) are not derived.

## Open
- Lead: widen the 33 flagged rows, or accept them; `fw plan sync` does not run the lint (fw-main.ts outside writes).
- Read first: the case table at the end of `WritesClosure.lean`, then `plan-closure.ts`.
