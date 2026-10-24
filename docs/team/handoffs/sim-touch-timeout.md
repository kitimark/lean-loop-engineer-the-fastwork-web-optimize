branch: worktree-wf_ff267e33-928-1 (CI branch ci/sim-touch-timeout, pushes used 3 of 3)
worktree: .claude/worktrees/wf_ff267e33-928-1
last commit: 11cf529ea (round 2 fixes, pushed as the third CI push)
CI runs: 40134212357 toolbar-throttle finish on the merged round-2 code (running); 40134212384 lean (running); earlier: 40121254572 finish (15 of 18), 40128742749 hero drags (18 of 18)
verified: round 2 findings 2 to 6 coded; Lean SimTouch builds, golden regenerated from Lean (59 lines) and replayed (10 tests pass); full package tests and check.sh pending
open: round 2 finish run result; lift-arm start-up stall is an accepted limit (task sim-lift-stall); persistent push server; review ready gate
read first: research/notes/2026/10-2x-sim-touch-timeout.md, lean/Fw/Device/SimTouch.lean, packages/measure-webkit/src/throttle/driver.mjs, cli.mjs (runArm)

State and conventions
- Machine: probing -> touching -> done; one restart (shutdown + new session + warm-up) per pass; attempt 2 only after restartOk; ends within 5 events.
- Stall rule on marks the XCUITest writes into TEST_RUNNER_FW_DIR (started, press-<i>): startup 300 s, gap 120 s, cap 300 + 45 s per press; polled every 5 s in dragPass.
- A second dragPass with the same tag becomes <tag>-t2 (own .xcresult and log); fixes exit 64 (existing -resultBundlePath).
- sim.mjs: blocking calls capped at 200 s; listDevices retries.
- Workflow: touch step 45 -> 90 min, job 60 -> 110 min (Lean stepLimitS 5400).
- Per-pass artifacts: out/<vm>-driver-<tag>.log (mark timeline + scrubbed tail), machine[] in out/<vm>-throttle.json.
- Debug knob: FW_TOUCH_FIRST_CAP_S stops the first measured touch run after n s.
- TS stand-ins: cli.mjs runArm event feeding, restart/warm-up glue, sim checks of probeLoop; the machine, stall rule, caps and ready are Lean-golden-checked.
- lean/scripts/SimTouchGolden.lean is a write outside the graph writes (the Lean golden entry point), listed in the report.
