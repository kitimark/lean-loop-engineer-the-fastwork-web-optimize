branch: worktree-wf_6ccadb14-8f5-1 (CI branches ci/morph-wheel-momentum = mac leg, ci/morph-wheel-momentum-sim = Simulator leg)
worktree: .claude/worktrees/wf_6ccadb14-8f5-1
last commit: see `git log -1` (CI pushes 704cb3741 mac, eca3c0e60 sim, both after the code commit and the main merge)
CI runs (smoothness.yml): mac 40018133445 success (jobs 1..3 success, 8 to 11 min each); sim 40018153769 failure (job 1 ok but starved; job 2 simctl ETIMEDOUT; job 3 pageLost after 3 windows). 2 dispatches used, no more allowed.
State: code, Lean, golden, tests, lean check, ci-paths, land-inputs green; mac run read (momentum: push 2.3 to 2.8 frames after the last scroll, 2 to 4 of 6 runs in flight, page already at the end at the push in 36 of 36); sim: 16 of 17 touch windows reached morph >= 0.9, no counts: INCONCLUSIVE for counts; note written (follow-up 2).

Verified so far
- Lean `WebKitLagPhase.lean` compiles (inFlight, flightFrames, splitPush, acceptMomentum, jobLabel, 25 theorems); golden regenerated with `lake env lean --run scripts/WebkitLagGolden.lean` (145 lines), never hand-edited.
- `test/lag-mac-morph.test.mjs` 12/12 (golden replay of flight, splitPush, momentum, jobLabel).

Design
- Drive `momentum` (macmorph.mjs): start maxY-300; trusted scroll wheels with a 2-frame gap until one wheel is left; then the last scroll wheel, 1 frame, the push wheel. The page script marks the push by `arm('down', 1)` (skip the last scroll wheel), events carry `m` (marked).
- Scroll in flight: wheel at frame s covers frames s..s+2 (Lean `flightHold`); run accepted when the push frame is in flight, >= 2 scroll wheels, page moved, morph reached 0.9 (Lean `acceptMomentum`; refusals noPush, fewWheels, settled).
- Per-job labels: `jobLabel`; `mac-cli run --job-index N` (or env FW_MATRIX_JOB) writes `jobIndex`; `report --jobs 1,2,3` names offline files; no index and one file reads "this job". The workflow passes no index (smoothness.yml is off limits): follow-up `FW_MATRIX_JOB: ${{ matrix.job }}` on the morph step.
- Simulator leg = the existing webkit-sim job (`[webkit-cadence] [earn-bound] [sim-only]`); touch windows record no Timeline (sim-touch-reliable), so it yields touch outcomes, morphMax and frame intervals, not counts.

Open: fw land --dry; review ready; lead: smoothness.yml FW_MATRIX_JOB follow-up.
Files outside the task writes: WebKitLagPhase.lean, golden webkit-lag.jsonl (regenerated), mac-cli.mjs, probe.mjs.
Read first: research/notes/2026/10-2x-morph-real-wheel.md, lean/Fw/Measure/WebKitLagPhase.lean (end of file), packages/measure-webkit/src/lag/macmorph.mjs, macreport.mjs.
