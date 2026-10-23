branch: worktree-wf_94944339-2ae-1 (CI branch ci/hero-accent-draw-nolayout)
worktree: .claude/worktrees/wf_94944339-2ae-1
last commit: see git log (note + ledger commit 7b44ef6b3, then main merge, handoff)
CI runs: webkit-sim 39999057900 (push 08e6bcdf0, [swap-lane] [swap-fw:accent-nolayout]): complete; r1 r2 success, r3 failed at Simulator boot. 1 of 2 dispatches used.
verified: Lean StyleDiffAccent (all by decide), check.sh green (slot), site tests + tsc, runner tests, ci-paths 56.
result: rest windows with >=24 Layout rows 17/64 (arm) vs 20/32 and 18/32 (faithful a, b); swap windows unchanged (median 14); hero exit: cadence/Paint/Composite overlap, no Layout count in the lane.
open: pixel sameness not measured (path-pix pins the accent; class look-change, user review); Layout per hero-exit frame not delivered.
design: arm = clip-path inset() wipe of frame0, static path; draw-out frames layout-free (arm_drawOut_nolayout), draw-in keeps width transition (layout).
writes outside graph: .github/workflows/webkit-sim.yml (FW token), lean/Fw/Ci/Trigger.lean + golden/ci/triggers.jsonl, golden/preset/v2-proved.decisions.jsonl.
read first: research/notes/2026/10-2x-accent-draw-nolayout.md, lean/Fw/Engine/StyleDiffAccent.lean
