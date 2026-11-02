branch: worktree-wf_850db9c2-5f8-1 (CI branch ci/touch-window-retry)
worktree: .claude/worktrees/wf_850db9c2-5f8-1
last commit: 4fdde6020 (CI request commit on top of 615e28e28)
CI runs: 41534838350 (smoothness, push run of 4fdde6020 on ci/touch-window-retry, dispatch 1 of 2) running; lean job of the same push not read
verified: Lean WindowRetry.lean builds (verdict branch theorems, deadline bound, never-pass), golden window-retry.jsonl 25 lines, window-retry.test.mjs 10/10, measure-webkit test 1177/1177, lint-wallclock ok, ci-paths test 56/56
open: CI result, note research/notes/2026/11-03-touch-window-retry.md, check.sh, dry land, review ready
Pricing (scratch, local, not committed): scratchpad/touch-window-retry/ (artifacts of runs 41503168296 and 41436626306 copied from the touch-window-loss download; bin/price.mjs, bin/redo-price.mjs)
Rule: Lean Fw.Measure.WindowRetry (verdict, redoFits = now + blockMs (left+1) + reserve <= dl, outcomeOf, finalClass); TS packages/measure-webkit/src/window-retry.mjs, wired in touchlock-run.mjs (tryWindow, withRedo; first row is pushed before the redo and replaced by it only when recovered)
