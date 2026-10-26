branch: worktree-wf_cf598a19-7f5-1 (CI branch ci/push-cycle-16)
worktree: .claude/worktrees/wf_cf598a19-7f5-1 (under the repo root)
last commit: bf4a3244a (push 1 of at most 2)
runs: 40361916735 (push 1, bf4a3244a, complete: failure because sim 2 and 5 failed; 6 result files): rewrite 2 full 4 dwell undecided:fewFull (stretch 3934, beyond the bound), user 5 full 5 dwell undecided:inseparable (stretch 2126). Push 2 follows (same measurement code, report code changed: lostOf names every lost pass).
verified: Lean file elaborates (lake env lean), golden regenerated and --check green, TS twin test push-cycle.test.mjs 20 of 20; check.sh green (fw slot), measure-webkit test 928 pass; dry land not yet run
open: push 2 result and pooled table, note 10-2x-push-cycle-16.md, ledger row, results, dry land, review ready

What was built
- lean/Fw/Measure/PushCycle.lean: fullCyclesFor r = clockIndex r 5 + 1; sepStretchBound = 2391 + 25 percent = 2988; sepFullCycles = fullCyclesFor bound = 16; theorems sep_fits (window fits for every r up to the bound), sep_fits_index, sep_margin, sep_noRoom_only (noRoom implies stretch beyond the bound).
- golden packages/contracts/golden/measure/push-cycle.jsonl regenerated (fullCycles op, new constants); twin in packages/measure-webkit/src/throttle/push-cycle.mjs; CLI --separate reads SEP_FULL_CYCLES (no --cycles 12 in the workflow).
- report: failedOnly/missingJobs make failed passes and jobs without a result file part of the lost list (--expect 1,2,3,4,5,6).
Read first: lean/Fw/Measure/PushCycle.lean from fullCyclesFor, then research/notes/2026/10-2x-push-cycle-separate.md.
