# toolbar-sim-lane handoff (round 2)
Branch worktree-wf_bf9846c7-37b-1, worktree .claude/worktrees/wf_bf9846c7-37b-1; last commit see `git log -1`; CI branch ci/toolbar-sim-lane at 02d957418 (3 of 3 pushes used, no new push in round 2).
CI runs (toolbar-throttle.yml), 40236328441 cancelled (sim 1-5 ok, 6-10 cancelled by me), 40250249829 cancelled (sim 1-3 ok, 4-10 cancelled by me), 40257287239 failure (sim 4 lost VM, rest ok).
Round 2 (review split): the lane, the Lean reducers and the cadence/state verdicts land here; Layout/RecalcStyle cost measurement is task toolbar-cost-sample (>= 3 same-job windows per arm, new push budget), not done.
Verified: reducer re-run on the three downloaded runs: unthrottle undecided (cost windows default 0 / flag 2), touch-first, open-once, overscroll-lock, threaded no-win, enters a preset: no for all.
Open: fw review ready; follow-ups toolbar-cost-sample, ledger row, part.json promotion of unthrottle.

## State
- Lean lean/Fw/Measure/MorphEndCount.lean: Brick.undecided, minCostWindows (3), costWindows, costKnown, costCmp, flagVerdict (cost-unknown win is undecided), theorems flagVerdict_cost_known, flagVerdict_cost_unknown_not_win, flagVerdict_undecided, flagVerdict_unknown_keeps_loss, costKnown_* (empty/short base/cand, layout and recalc), unthrottle_no_cost_undecided, undecided_never_enters. Golden 126 lines (tb-verdict rows carry costKnown; 7 new cases). Regenerate: `cd lean; lake build Fw.Measure.MorphEndCount; lake env lean --run scripts/MorphEndCountGolden.lean > ../packages/contracts/golden/device/morph-end-count.jsonl`.
- TS twin packages/measure-webkit/src/throttle/toolbar.mjs (costKnown, flagVerdict), toolbar-report.mjs (verdict table without cost columns, "Not measured here" section), test/throttle-toolbar.test.mjs replays the golden.
- Note research/notes/2026/10-2x-toolbar-sim-lane.md.

## Conventions and limits
- Cost window: opens at gesture 2, closed once gesture 5 began; Lean windowCost counts only between page stamps of gestures 4 and 5.
- Look-change arms never enter a preset; part.json untouched. The state-trace floor does not detect touch-first's designed change.
- Lost VMs are named failures (run 40257287239 sim 4).
