# Handoff: flip-cell-pixel-hang (finisher, graph r613)

State: branch worktree wf_400db961-014-1, CI branch `ci/flip-cell-pixel-hang`, pushed at d6dcdce9a with [ci:breakpoint-gate]. CI run 41231318047 (first attempt, both engines): green; WebKit 0 faults, 0 late waits, longest screenshot 7883 ms. One green run does not show the bad-host path.

Done and verified locally (not a result):
- Lean `lean/Fw/Parts/MorphGeomReady.lean` (ready, wait, attempt/outcome, retry, cellsPass/cellsKept, limits) and `MorphGeomVerify.lean` (leaveCountOk, bandOk, runVerdict); golden lines in `packages/contracts/golden/morph-geom-timed.jsonl` from `MorphGeomTimedGen.lean`. `sh lean/scripts/check.sh` rc 0 at edb060b27.
- TS: `packages/gate-breakpoints/src/bounded.mjs` (limits from the golden, bound, call, closeBounded, waitCell, takeCell), used by `flip-cell.mjs` and `packages/premise-tests/src/look.mjs`; `flip-verify.mjs` per-cycle `beginCycle`, leave count = cycles, `runVerdict`.
- Workflow: step `timeout-minutes` 15 / 15 / 40 on Flip-state cell, geom-timed, Pixel look report.
- Tests: gate-breakpoints 856 pass, premise-tests 20 pass, ci-paths 56 pass, runner land-inputs 73 pass (land.ts premise-tests reads gained bounded.mjs).

Open:
- More first-attempt WebKit runs (cause A is INFERRED host slowness; B is lazy mount plus unsettled transitions).
- look.mjs is glue with no local test (TS stand-in for the per-cell loop; the decision rules are Lean-golden checked).

Read first: `research/notes/2026/11-01-flip-cell-pixel-hang.md`, `bounded.mjs`, `MorphGeomReady.lean`.
