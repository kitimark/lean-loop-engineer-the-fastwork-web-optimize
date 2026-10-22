# dispatch-latency handoff (checkpoint 1)
- branch: worktree-wf_8a73457e-659-1 (CI branch ci/dispatch-latency); worktree: .claude/worktrees/wf_8a73457e-659-1 (under the repo root)
- last commit pushed: e4afd7ad9 (split instrumentation), on ci/dispatch-latency
- CI runs (push of e4afd7ad9, state unknown at write time): lean 39867724572, premise-tests 39867724714, difftest 39867724575, breakpoint-gate 39867724763, lean-math 39867724673
- verified: runner typecheck + run-phases/span-names/run tests green locally
- done: run-phases.ts GhClock/phasedEnv split (run plan, run dispatch lock|backoff|call), watch pass gh lock/call/other (watch.ts, watch-collect.ts)
- open: before/after real dispatches (max 4), Lean RunSplit in Fw.Obs.Timing + goldens, the lighter change, docs/team/tools/timings.md step names, research note, fw land --dry, review ready
- cause hypothesis (INFERRED): ghCharged holds the shared gh-budget lock across the whole gh process (packages/gh-budget/src/charged.ts chargedOnce), so concurrent dispatches and watch gh calls serialise; fwcore keeps one pending slot (Budget.lean observe), so unlocking during gh needs a Lean redesign (follow-up)
