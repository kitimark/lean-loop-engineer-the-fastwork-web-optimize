branch: worktree-wf_ff267e33-928-1 (CI branch ci/sim-touch-timeout, pushes used 2 of 3, third not needed)
worktree: .claude/worktrees/wf_ff267e33-928-1
last commit: the head of this branch
CI runs: 40121254572 toolbar-throttle finish mode success (3 of 3 jobs ended, 15 of 18 passes ok, sim 2 all 6, about 75 min per job); 40128742749 toolbar-throttle hero drags success (18 of 18 passes, 18 to 28 min per job); 40121254514 lean success
verified: Lean SimTouch + golden replay, package tests 644, ci-paths 56, apps/runner 3463 (incl. land-inputs), lean check.sh green; restart path walked live 6 times in CI (3 recovered the pass)
open: 3 named finish failures (lift arm start-up stall, 6 of 30 finish touch runs never started in 300 s); persistent push server; final review ready gate; note is written (research/notes/2026/10-2x-sim-touch-timeout.md)
read first: research/notes/2026/10-2x-sim-touch-timeout.md, lean/Fw/Device/SimTouch.lean, packages/measure-webkit/src/throttle/driver.mjs (twin, dragPass, probeLoop), cli.mjs (runArm, restart, warmUp)

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
