branch: worktree-wf_8eb246cf-85f-1 (CI branch ci/sim-end-cut-2)
worktree: .claude/worktrees/wf_8eb246cf-85f-1
last commit: see `git log -1`; CI tip e23ab818e (measured code at 4379b4360)
CI runs: webkit-sim 41204019629 success (3 jobs x 1 round, e23ab818e); lean 41204019683 success
result: every flag took in 3 of 3 jobs; all 12 arm-stage cells tier two (197-205 per 100); both = 202, 197, 203 at end, 200 at back; paused both = 100 x3, paused v2p = 200 x3
attribution: only the 2 in-view sweep loops run in both (INFERRED holder); candidate platform.sweep:layer-sweep (class L, spec only)
verified: Lean SimEndCut golden (108 lines, +6 real run 41204019629 rows), sim-end-cut.test.mjs 12/12
files: research/notes/2026/10-31-sim-end-cut-2.md, results/sim-end-cut-2/r1/{cut,table,rows}.txt, job{1,2,3}.json
open: check.sh, package tests, ci-paths test, land-inputs test, merge main, plan lint, dry land, review ready
TS stand-in: packages/measure-webkit/src/sim-end-cut.mjs (checked against the Lean golden); faded-pause has no isolating arm
