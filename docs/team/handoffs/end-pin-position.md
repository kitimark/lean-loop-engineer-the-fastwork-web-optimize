branch: worktree-wf_871d2df0-421-1 (CI branch ci/end-pin-position)
worktree: .claude/worktrees/wf_871d2df0-421-1 (under the repo checkout)
last commit: 04e6cdb3d (CI trigger commit; code at 9ed6503a4, Lean at 86a25e556)
CI run 41380162402 (smoothness, touch-lock lane, 12 jobs, 3 waves): in_progress, dispatch 1 of 2 (pushed 2026-11-02)
verified: Lean TouchLock builds clean, golden touch-lock.jsonl (192 lines) --check up to date, package tests 1125/1125 pass
open: CI result, across-jobs verdict by position, note research/notes/2026/11-0x-end-pin-position.md, ledger row morph.tween:end-pin

## State
- Lean (lean/Fw/Measure/TouchLock.lean): rest metric (restOf: notReached / atEnd / over / short; tolerance 10 px, margin 3, floor 3 reached windows per arm), settle after the last touch, restCmp, jobVerdict with the liveWrites guard (live > 0 never ranks pin better), acrossRest via Fw.Gate.Smooth.acrossDecisive; golden cases for each.
- TS twin: packages/measure-webkit/src/touchlock-rest.mjs, wired into touchlock.mjs (windows table, summary line, across report); tests packages/measure-webkit/test/touchlock-rest.test.mjs replay the goldens.
- touchlock-run.mjs passes readyMs: READY_ALLOW_MS (480 s) to both startServer paths.
- Offline check on end-pin-rank run 41369102226 (results/end-pin-position/offline-across.md): pin rests at the end in 30 of 33 reached windows, base 19 of 36; 6 of 11 jobs decisive, 4 needed, across verdict second (pin rests better); every job has liveWrites 0. So the current walk can rank by position; no walk variant built.

## Read first
results/end-pin-position/offline-across.md, then the Lean section before `inductive Arm` in TouchLock.lean.

## Conventions
CI waits: pnpm -s fw ci wait --branch ci/end-pin-position --workflow smoothness; results: pnpm fw ci <runId>. At most 2 dispatches.
