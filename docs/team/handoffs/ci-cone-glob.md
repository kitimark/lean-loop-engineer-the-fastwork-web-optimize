# Handoff: ci-cone-glob

State: worktree branch of task ci-cone-glob (commits "ci-cone-glob: ..."), follow-up to ci-trigger-lean.
Read first: `lean/Fw/Ci/Trigger.lean` section "Coarse push filter, precise guard", then `.github/scripts/changed-inputs.mjs` header.
What changed
- `on.push.paths` no longer list cone files: each `@cone:<Root>` is written as `coneGlobs` = `lean/Fw/**`, `lean/*.lean`
  (Lean `pushPaths`, which takes no cone). A new module under `lean/Fw` changes no workflow file.
- The guard job computes the precise inputs at run time: the workflow's Lean row (golden `triggers.jsonl`) with the cones read
  from the checkout (`preciseInputs`; fallback without a row: the workflow's own `on.push.paths`, a superset). `starts_iff` holds.
- Lean: `coarse_sound` (if every cone file is literal and inside `coneGlobs`, `ConeWithin`, the precise scope is inside the
  coarse scope), `push_filter_passes` (guard starts => static filter passes), `paths_stable_under_new_module` (adding a literal
  file inside `coneGlobs` keeps `ConeWithin`, same paths still sound), helpers `mem_expand_setMap`, `literal_prefix`.
- Golden: table line has `coneGlobs`; each case has `filtered` (static filter result); new case "a new module under lean/Fw".
- `scripts/ci-paths.mjs`: cone reader, `setMap`/`expand`, `loadGolden` moved into the guard script (re-exported); `run` writes
  coarse paths and fails on `coneProblems` (a cone file outside `coneGlobs` or with `*` = `ConeWithin` broken).
Conventions: TS/JS hold no decision; the table stays the single place to change a trigger. Regenerate:
`cd lean && lake test -- --write-ci-trigger-golden`, then `node scripts/ci-paths.mjs --write`.
Open items
- The golden and `scripts/ci-paths.mjs` are not workflow inputs: a table edit that only changes a cone-free input still
  rewrites the yml (so it starts); a guard-only change starts nothing until `changed-inputs.mjs` changes (it is an input).
- A cone `include_str` outside `lean/` (none today) would fail the lint; add its path to `coneGlobs` then.
- Math view: the new theorems are unsigned; run math-reviewer.
- wt-prep.sh treats an idle `lean --server` with cwd main/lean as a running build and skips the clone (seen here; cloned by hand).
