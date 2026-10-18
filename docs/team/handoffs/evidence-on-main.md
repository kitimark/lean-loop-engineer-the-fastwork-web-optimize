# evidence-on-main handoff

State: committed on the worktree branch (task `evidence-on-main`; incidents `inc-evidence-before-land`,
`inc-upsert-keeps-evidence`). Main merged; `lake build`, `lake test` and `pnpm -r test` green.

## What it does
- `task.define` carries `evidenceOnMain` (missing/null = true, so old logs replay unchanged). Lean `Fw.Plan.check`
  refuses a define whose commit-kind evidence (`Lint.evKind`) is off main: `evidence not on main: <sha>`, state kept.
  Run ids, user decisions and prose are never checked.
- `Task.landed`: evidence came from `task.done`. `upsert` keeps landed evidence (`keepEv`); otherwise the define's
  evidence replaces it, so removing the field from the graph returns the task to its derived state.
- Theorems (lean/Fw/Plan/Core.lean): `upsert_cannot_mark_done_early`, `define_offMain_refused`,
  `define_offMain_reason`, `define_removes_unlanded_evidence`, `land_never_undone`, `run_land_never_undone`,
  `done_needs_landed_evidence`, `exec_isDone`/`step_isDone` (with hypothesis). "Done is monotone" is false now;
  Console.lean `apply_isDone`/`project_isDone` became `apply_isLanded`/`project_isLanded`.
- Lint code `evNotOnMain` (error, `Lint.evNotOnMain_iff`); `plan.lint` reads per-task `evidenceOnMain`.
- Glue: `syncCommands(..., onMain)` in packages/contracts/src/plan-sync.ts adds `evidenceOnMain: false` only when
  off main (keys of on-main rows unchanged; the off-main key differs, so the row is re-sent after the land).
  Facts come from `git merge-base --is-ancestor` (runner `gitOnMain`, reconciler `isAncestor`).
- On main now: 0 of 161 commit evidences are off main.

## Open items
- A task done by define evidence never gets `landed` (task.done is refused for a done task); harmless.
- `fw land`'s after-sync throws when the graph holds off-main evidence (it names the sha).
- Math view (docs/plan/loop-plan.html) still lists apply_isDone/project_isDone; regenerate with `lake exe mathview`.
- Outside the writes list: lean/Fw/{Console,Wire/Plan,Wire/Console}.lean, apps/runner/src/fw.ts,
  apps/runner/test/plan.test.ts, packages/contracts/{schema,golden/plan}.

Read first: Core.lean module doc bullet "Evidence on main", then section "Done and landed".
