branch: worktree-wf_cf598a19-7f5-1 (CI branch ci/push-cycle-16)
worktree: .claude/worktrees/wf_cf598a19-7f5-1 (under the repo root)
state: both pushes done and read; note, ledger row and results written; merge of main, check.sh, dry land and review ready follow (see open)
runs: push 1 = 40361916735 (bf4a3244a), push 2 = 40412970956 (dcc008d97); both finished with failed sim jobs (push 1: sim 2, 5; push 2: sim 1, 3, 4) but all 12 jobs have result files
verdict (Lean sepVerdict, cycles 3 to 5, > 50 ms): rewrite undecided (pooled 7 full 6 dwell, stretch 3289 beyond bound 2988, noRoom); user undecided (pooled 7 full 8 dwell, inseparable). Per push: rewrite fewFull / fewDwell, user inseparable / fewFull. H4 stays open.
verified: Lean file elaborates, golden regenerated and --check green, TS twin test push-cycle.test.mjs 20 of 20, check.sh green earlier (fw slot), measure-webkit tests green
open: merge main (92 commits behind at last fetch), lake build, check.sh again, plan lint, dry land, review ready; follow-up task: stall-robust (median) period so the stretch does not overshoot the bound
conventions: pool runs with node results/push-cycle-16/pool.mjs p1=<dir> p2=<dir>; lost passes come from lostOf in push-cycle-report.mjs; the cycle count is sepFullCycles (Lean), never typed in the workflow
Read first: research/notes/2026/10-2x-push-cycle-16.md, then lean/Fw/Measure/PushCycle.lean from fullCyclesFor, then results/push-cycle-16/pooled.md
