Branch: worktree-wf_1a3f883b-68d-1 (CI branch ci/morph-idle-followups). Worktree: .claude/worktrees/wf_1a3f883b-68d-1
Last commit: (see git log; checkpoint 1, before any code)
CI runs: none finished yet. Planned: two webkit-sim dispatches (base, flag) with lag=true cost=only target=rewrite vms=3.
Verified: nothing yet. Re-read of runs 39903977820 (base) and 39903974246 (flag) artifacts webkit-sim-r1: Composite per frame
equals the frame interval in every zone (the Simulator composites on the CPU), idle composite of one arm varies 16 ms to 49 ms
between its two passes, so the per-frame verdict is unresolved before any Lean work; the Lean reducer must say so with a rule.
Open: (1) Lean reducer + decision, (2) goldens, (3) writer threshold test + IdleHold golden, (4) Chromium re-baseline waits for counts-font-fidelity.
Read first: research/notes/2026/10-20-morph-idle-none.md, lean/Fw/Measure/WkCost.lean, packages/measure-webkit/src/lag/costreport.mjs.
