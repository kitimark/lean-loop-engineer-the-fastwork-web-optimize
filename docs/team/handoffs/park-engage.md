branch: worktree-wf_1fa3ccb3-4b3-1 (CI branch ci/park-engage)
worktree: .claude/worktrees/wf_1fa3ccb3-4b3-1 (under the repo root)
last commit: see git log (fix 00293b3e4; CI tip 0039fbb95)
CI runs: 41179356320 complete (unfixed park: park arm not parked, view-driven 13, 3 of 3); 41181664848 complete (fix: both arms parked, view-driven 0, 3 of 3); 41185704042 complete (merged harness, same result)
verified: cause (a) observer never reports a jump; startParkOn ran. Lean ScrollPark scrollEvent/jump_engages/walk_engages/io_engages (check.sh green); park.test.ts golden + jump/walk tests; footprint regenerated; measure-webkit tests
read first: research/notes/2026/10-31-park-engage.md, results/park-engage/r1/park.txt, r2/park.txt
open: dry land verdict and review gate are in the report; sim-end-cut-2 measures the rate effect; the harness change (arms param, park act, park probe in census) may conflict with sim-end-cut and sweep-pause-all in sim-end-floor*.mjs and webkit-sim.yml: keep both sides
conventions: park arms via `sim-end-floor-cli.mjs run --arms park`, tokens [end-floor] [end-park]; threaded-park stays class L
