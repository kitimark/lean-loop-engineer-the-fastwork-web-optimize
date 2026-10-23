branch: worktree-wf_b23d1ba6-96a-1 (CI branch ci/carousel-swap-followups)
worktree: .claude/worktrees/wf_b23d1ba6-96a-1
last commit: 6f09b8c45 (pushed to ci/carousel-swap-followups; head message has the lane token and [swap-lane])
CI runs:
- 39968418529 (and siblings) at 793f38e48: all skipped (head commit had no lane token); not a result
- 39968644601 webkit-sim at 6f09b8c45: running (one of the 2 allowed)
verified: Lean SwapWindow builds (fewSamples, bgOf, swapNeighbours + theorems), wkcost.jsonl regenerated and --check ok, measure-webkit tests 459 pass.
open: wait for the run, build the report (swap-report with the 3 job files), note, dry land.
Writes outside the task graph: packages/measure-webkit/src/lag/probe.mjs (swap lane before the cost passes, so a layersScroll failure keeps the swap samples).
Finding so far (MEASURED, committed report results/carousel-swap-webkit/people-carousel-crop.json, 12 crop captures): rest-window Layout is about 5 or 40-50 rows, with a period of exactly 3 swap periods (busy rest k, swap k+1, rest k+1; idle swap k+2, rest k+2, swap k+3); the faithful captures show the same rest windows. So the crop's every-third window Layout/Paint is a page background layout source, not the swap, masked in faithful by its own 13 Layout frames. The source part is not named yet: a diag capture (DIAG_JS) is in the run.
