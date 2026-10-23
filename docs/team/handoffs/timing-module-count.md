# timing-module-count handoff

- Branch `worktree-wf_44e4ecbb-fdc-1`, worktree `.claude/worktrees/wf_44e4ecbb-fdc-1`. No CI run (none needed).
- State: Lean + TS done and committed; check.sh and runner tests run via slot; dry land and review ready close the task.

## What changed
- `Fw.Ops.CheckMap.heavy : Check → Bool` (total match). `Fw.Obs.Timing.heavyChecks` = `(order.filter heavy).map checkName`
  (`heavyChecks_eq` pins it). tscProject stays light: MEASURED 283-449 ms per package (`checkmap.mjs file tsc`).
- Work dimension `mods`: `modsLow n` = 0, else the largest power of 4 ≤ n; `spanWork … (built : Option Nat := none)`
  orders checks, mods, width. Span member `lake: {built}`; old spans have none and keep their old key (accepted limit,
  `judgeQ_unbuilt`). Proved: `modsLow_le`, `lt_modsLow`, `mods_same_lt`, `mods_same_zero`, `modsWork_eq_iff`,
  `spanWork_mods_ne`, `judgeQ_other_mods`.
- `builtLine`/`builtModules`: lake's `[i/n] Built <name>` lines, names without `:`; golden `timing-lake.jsonl`.
- polish.ts `stagedSpan` runs the staged lakeBuild command before `git commit` (hook build then no-ops) and notes
  `lake`; land.ts sums `builtModules` over dry check outputs and notes `lake` on `fw/land dry` when the step is lake.

## Re-judged (Lean golden cases, `#guard`)
- land dry lake 43470 (17cb8b6, 24 modules, MEASURED from land log): pooled `slow`; keyed `mods=16` n=9 p50 50000 `ok`.
- polish commit 38160 (aa96a910f, 40 modules INFERRED from import closure): keyed `checks=lakeBuild,mods=16` n=4
  `noBaseline` (no alert).

## Open
- land.ts lake note has no unit test (land tests are outside this task's files); builtModules is golden-checked.

## Read first
`lean/Fw/Obs/Timing.lean` (search `modsLow`, `landDryData`), `apps/runner/src/polish.ts` `stagedSpan`.
