# TS stand-ins

A pure decision whose spec and proof are in Lean but which runs as TypeScript or JavaScript, checked against a Lean-generated golden
(rule: CLAUDE.md "Lean first"). Each row names the Lean source, the twin, the golden that pins it, and what would retire it.
Add a row when a task lands a twin; delete the row when the decision runs in `fwcore` or is generated.

| Twin | Lean source | Golden | Retire when |
|---|---|---|---|
| `apps/runner/src/run-pick.ts` `pickRun`, `isMine`, `validNonce`, `titleOf` | `Fw.Ci.Dispatch.pick` | `packages/contracts/golden/ci/dispatch.jsonl` (`test/run-pick.test.ts`) | `fw run` calls an fwcore op for the pick |
| `apps/runner/src/run-pick.ts` `dispatch`, `dispatchIn`, `pickWidths`, `legsOf`, `enginesOf`, `refusalText` (the mark rule of a trajectory dispatch) | `Fw.Gate.Trajectory.Dispatch`, `Fw.Gate.Trajectory.legs`, `enginesOf` | `packages/contracts/golden/gate/trajectory-dispatch.jsonl` (`test/run-dispatch.test.ts`) | `fw run --trajectory` calls an fwcore op for the decision; `refusalText` words stay glue |
| `.github/scripts/trajectory-line.mjs` `dispatch`, `dispatchIn`, `whyText`, the per-lane `pushProbe(wf, lane, msg)` (the same rule on the push line and the workflow input) | `Fw.Gate.Trajectory.Dispatch`, `Fw.Ci.Trigger.pushProbe` | `trajectory-dispatch.jsonl`, `packages/contracts/golden/ci/triggers.jsonl` (`trajectory-line.test.mjs`, run in the `site` job) | the workflow reads the decision from an fwcore op |
| `packages/gh-budget/src/want.ts` `dedupById`, `dupIds` (one row per run id before any select) | `Fw.Ci.Dispatch.dedupById`, `dupIds` | `packages/contracts/golden/ci/dispatch.jsonl` `dedup` lines (`packages/gh-budget/test/dedup.test.ts`) | the poller calls an fwcore op for the list |
