branch: worktree-wf_ff267e33-928-1 (CI branch ci/sim-touch-timeout, pushes used 2 of 3 once push 2 is out)
worktree: .claude/worktrees/wf_ff267e33-928-1
last commit: the head of this branch (the CI tip of each push is its head at that time)
CI runs: 40121254572 toolbar-throttle finish mode DONE success (jobs about 75 min, limit 110); 40121254514 lean success; push 2 (hero drags) next, its run id is added below when known
verified: finish run 40121254572: sim 1 4 of 6 passes ok (2 named failures), sim 2 6 of 6 ok (all arms, restart walked live once), sim 3 5 of 6 ok (1 named failure); 5 of 18 ok passes ran 307 to 353 s (old cap 300 s); 5 of 6 startup stalls were on the lift arm; earlier: Lean/golden/ci-paths/land-inputs/package tests green
open: hero-drag run (push 2) and its table; fill RESULTS_PLACEHOLDER and BEFORE_AFTER_PLACEHOLDER in research/notes/2026/10-2x-sim-touch-timeout.md; final checks (lean check, package test, dry land, review ready, plan lint)
read first: lean/Fw/Device/SimTouch.lean (machine + proofs), packages/measure-webkit/src/throttle/driver.mjs (twin, dragPass, probeLoop), cli.mjs (runArm, restart, warmUp)

State and conventions
- Machine: probing -> touching -> done; one restart (shutdown + new session + warm-up) per pass; attempt 2 only after restartOk; ends within 5 events.
- Stall rule on marks the XCUITest writes into TEST_RUNNER_FW_DIR (started, press-<i>): startup 300 s, gap 120 s, cap 300 + 45 s per press; polled every 5 s in dragPass.
- A second dragPass with the same tag becomes <tag>-t2 (own .xcresult and log); fixes exit 64 (existing -resultBundlePath).
- sim.mjs: blocking calls capped at 200 s (stall guard saw 604 s silences); listDevices retries.
- Workflow: touch step 45 -> 90 min, job 60 -> 110 min (Lean stepLimitS 5400).
- Per-pass artifacts: out/<vm>-driver-<tag>.log (mark timeline + scrubbed tail), machine[] in out/<vm>-throttle.json.
- Debug knob: FW_TOUCH_FIRST_CAP_S stops the first measured touch run after n s (local walk of the restart path only).
- TS stand-ins: cli.mjs runArm event feeding, restart/warm-up glue, sim checks of probeLoop; the machine, stall rule, caps and ready are Lean-golden-checked.
- Open finding: the XCUITest start-up has a heavy tail (45 to 249 s seen, 5 runs of 24 never started in 300 s); a persistent push server would remove it.
