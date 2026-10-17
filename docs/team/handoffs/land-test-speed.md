# land-test-speed handoff

State: branch `worktree-agent-a05cc2c15112880a8`, main merged, lean `check.sh` and the three suites green.
Times are local debug runs under load 10-22 on 8 cores (not results; CI is the record).

| suite | before | after | cause and fix |
|---|---|---|---|
| packages/gate-breakpoints test | ~108 s | ~6 s | `lake env lean --run` interpreted ScopeGen (100 s); now compiled `breakgen --scope` (4 s) |
| packages/gh-budget test | 81 s | ~11 s | a node spawn of the fake gh per replayed call; now `Env.exec` in-process fake (`test/fake-gh-core.ts`) |
| apps/runner vitest | 44 s | ~20 s | real 10 s busy-lock wait, 15 s lock poll + 2 s pause in the SIGTERM test, fwcore/gh spawn per call in run-budget |

Conventions: Lean first. New pure decision `Fw.Gate.ScopeGen.checkCode` (+ `checkCode_eq_zero_iff`, `checkCode_self`).
gh-budget decisions were already Lean ops with goldens (fwtest); the TS replay only exercises glue, so the fix is
infrastructure. `Env.exec` is test-only (production never sets it). Tests were not weakened: same assertions;
the SIGTERM test now waits for a started marker (event) instead of a fixed pause.

Proposal, not wired: `lean/Fw/Console/LandPool.lean` (`poolFair c l = max (max 1 (c/2)) (c-l)`; never below
`poolSize`, equal when unsaturated, others keep >= 2/3). MEASURED: the load is running processes (state R), not idle
`lake serve` (state S, 0% CPU), so the saturation is real; the floor is fair-share. Lead decides on land.ts.

Open items:
- math-reviewer: `checkCode_eq_zero_iff`, `checkCode_self`, the `poolFair*`/`share_mono`/`others_share_floor` set.
- Optional: add `breakgen --scope --check` to lean/scripts/check.sh; `DRIVER_RUN` entries for Fw.Gate.Scope/ScopeGen in
  lean/scripts/check-imports.mjs are now stale but harmless.
- Remaining runner cost is process-bound (outside my write set): ~0.5 s `makeRepo` per land test in
  apps/console-api/test (clone a template repo instead), `git maintenance` auto runs (set `maintenance.auto=false` via
  GIT_CONFIG env), one fwcore spawn per `askCore` in hooks/land-guard.mjs (reuse one process).
- `wt-prep.sh` skipped the lean clone because an idle `lean --server` in the main lean dir looked busy; false positive.

Read first: packages/gate-breakpoints/scripts/scopegen.mjs, packages/gh-budget/test/util.ts, lean/Fw/Console/LandPool.lean.
