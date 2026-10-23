# dispatch-latency handoff (final)
- branch: worktree-wf_8a73457e-659-1 (CI branch ci/dispatch-latency); worktree: .claude/worktrees/wf_8a73457e-659-1
- code commit pushed to CI: da93be409 (Lean RunSplit + goldens + gh bounds); later commits add the note and handoff only
- CI runs for da93be409: lean 39868489936 (in progress at write time); the other seeders were skipped by path rules. Earlier runs for e4afd7ad9: lean 39867724572, premise-tests 39867724714, difftest 39867724575, breakpoint-gate 39867724763, lean-math 39867724673
- real dispatches (all cancelled): before 39867859419, 39867864566; after 39868526163, 39868530589
- done: span split (run-phases.ts, watch.ts), Lean steps/bounds/goldens (lean/Fw/Obs/Timing.lean), bounds in packages/gh-budget (busy refusal, gh kill at timeout), note research/notes/2026/10-2x-dispatch-latency.md
- slow part: lock wait (gh-budget lock held across the whole gh process); gh call 2.2-2.7 s is GitHub's own time
- verified locally: runner and gh-budget typecheck, run-phases (14) and charged (9) tests, Lean Timing build, golden regenerated
- open: release the lock during the gh process (needs Lean redesign of the single pending slot in Budget.lean); TS constants are stand-ins checked against Lean text; backoff reason not in the span
- read first: the research note, then apps/runner/src/run-phases.ts
