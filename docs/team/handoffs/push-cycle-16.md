branch: worktree-wf_cf598a19-7f5-1 (CI branch ci/push-cycle-16)
worktree: .claude/worktrees/wf_cf598a19-7f5-1 (under the repo root)
state: done; both pushes read, note, ledger row and results written, main merged (clean), lake build, check.sh, measure-webkit tests (938), plan lint (0 errors), dry land (VERDICT dry push-cycle-16) and review ready (VERDICT review-ready push-cycle-16 review) all green
runs: push 1 = 40361916735 (bf4a3244a), push 2 = 40412970956 (dcc008d97); both finished with failed sim jobs (push 1: sim 2, 5; push 2: sim 3, 4 failed, sim 1 cancelled) but all 12 jobs have result files
verdict (Lean sepVerdict, cycles 3 to 5, > 50 ms): rewrite undecided (pooled 7 full 6 dwell, stretch 3289 beyond bound 2988, noRoom); user undecided (pooled 7 full 8 dwell, inseparable). Per push: rewrite fewFull / fewDwell, user inseparable / fewFull. H4 stays open.
verified: Lean file elaborates, golden regenerated and --check green, TS twin test push-cycle.test.mjs 20 of 20, check.sh green earlier (fw slot), measure-webkit tests green
open: land by the lead; scripts/test-checkmap.mjs fails on the preset import-closure check (Gen.lean closure, no PushCycle file named; not from this branch, unchecked on main); follow-up task: stall-robust (median) period so the stretch does not overshoot the bound
conventions: pool runs with node results/push-cycle-16/pool.mjs p1=<dir> p2=<dir>; lost passes come from lostOf in push-cycle-report.mjs; the cycle count is sepFullCycles (Lean), never typed in the workflow
Read first: research/notes/2026/10-2x-push-cycle-16.md, then lean/Fw/Measure/PushCycle.lean from fullCyclesFor, then results/push-cycle-16/pooled.md
