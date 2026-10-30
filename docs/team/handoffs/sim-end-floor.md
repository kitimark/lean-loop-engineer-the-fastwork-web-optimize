branch: worktree-wf_3bb21ec2-98b-1 (CI branch ci/sim-end-floor)
worktree: .claude/worktrees/wf_3bb21ec2-98b-1 (under the repo root)
last commit: 97243fdce (CI push 1, tokens [ci:webkit-sim] [end-floor])
CI runs: webkit-sim 41135293682 (running, push 1 of at most 3); lean 41135293671 (running)
verified: lean/scripts/check.sh green; measure-webkit tests 1059 pass; sim-end-floor test 9 pass x5; ci-paths test 56 pass; land-inputs test 73 pass x5; lint-wallclock ok
open: first CI result (run 41135293682, artifact webkit-sim-r1); results/sim-end-floor/r1; note research/notes/2026/10-31-sim-end-floor.md; ledger row; merge main + plan lint; dry land; review ready

What it is: the iOS Simulator end-of-page idle recalc floor per arm (base, v2p, v2p minus hero.exit:threaded, v2p minus engine.scroll:unthrottle).
- Lean decision: lean/Fw/Device/SimEndFloor.lean (band 10 per 100 frames, window 360 FireAnimationFrame, min seen 288, min rounds 2); golden packages/contracts/golden/device/sim-end-floor.jsonl (regenerate: lake build Fw.Device.SimEndFloor first, then lean/scripts/SimEndFloorGolden.lean; stale oleans give a stale golden).
- TS stand-in: packages/measure-webkit/src/sim-end-floor.mjs checked against that golden by test/sim-end-floor.test.mjs. windowOf, endFloorJs and the run loop are unproved glue.
- Harness: src/sim-end-floor-run.mjs and src/sim-end-floor-cli.mjs (run, searches, report). CI: webkit-sim.yml commit token [end-floor] (TARGET rewrite, FW v2p, site build --configs none plus the 3 searches).

Conventions: RenderingFrame reads 0 on iOS 27.0 24A434, so the frame count is FireAnimationFrame (seen). The page resolves its config from location.search, so each arm load does history.replaceState with the arm search before the reload. One local debug run was made (not a result); no local number is reported.
Read first: this file, sim-end-floor.mjs header, the golden consts line, then results/sim-end-floor/r1/verdict.txt once fetched.
