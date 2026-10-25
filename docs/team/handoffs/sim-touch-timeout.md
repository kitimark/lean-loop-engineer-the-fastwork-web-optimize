branch: worktree-wf_ff267e33-928-1 (CI branch ci/sim-touch-timeout, 4 pushes used, the 4th authorized by the lead; no new push)
worktree: .claude/worktrees/wf_ff267e33-928-1
last commit: see git log (head of this branch)
CI runs: 40145882715 toolbar-throttle finish on the merged code (pass-run.mjs): success, 3 jobs 74-83 min, 23 of 24 passes (sim 3 unthrottle-r1 lost to a start-up stall twice), no lift loss; 40134212357 failed (pre-fix, parts-cli bypassed the machine); 40121254572 finish (15 of 18); 40128742749 hero drags (18 of 18)
verified: after merging main (f0aafefc7) Lean check.sh green, 712 package tests, runner 3514, ci-paths 56; fw land dry VERDICT dry sim-touch-timeout; SimTouch Nat constants take a Unit default so the init-cost lint (main 1632 constants, limit near 1640) stays green; run 40145882715 read per job in the note
cause of 40134212357: parts-cli.mjs bypassed the machine; fixed in pass-run.mjs, shown by 40145882715
re-scoped claim (lead, final design round): 3 of 3 jobs end, 23 of 24 passes, 0 job losses, 1 pass lost to the start-up stall (failed:touchesFailed), at most 1 restart per pass; sim-lift-stall owns the stall, init-cost-depth owns the Unit-argument workaround
open: start-up stall on every arm (0 marks at 300 s, 6 of 29 touch runs; task sim-lift-stall: a launched mark in setUp before safari.activate); persistent push server
read first: research/notes/2026/10-2x-sim-touch-timeout.md, lean/Fw/Device/SimTouch.lean, packages/measure-webkit/src/throttle/pass-run.mjs, driver.mjs (twin, dragPass)

State and conventions
- Machine: probing -> touching -> done; one restart (shutdown + new session + warm-up) per pass; attempt 2 only after restartOk; ends within 5 events.
- Stall rule on marks the XCUITest writes into TEST_RUNNER_FW_DIR (started, press-<i>): startup 300 s, gap 120 s, cap 300 + 45 s per press; polled every 5 s in dragPass.
- A second dragPass with the same tag becomes <tag>-t2 (own .xcresult and log); fixes exit 64 (existing -resultBundlePath).
- sim.mjs: blocking calls capped at 200 s; listDevices retries.
- Workflow: touch step 45 -> 90 min, job 60 -> 110 min (Lean stepLimitS 5400).
- Per-pass artifacts: out/<vm>-driver-<tag>.log (mark timeline + scrubbed tail), machine[] in out/<vm>-throttle.json.
- Debug knob: FW_TOUCH_FIRST_CAP_S stops the first measured touch run after n s.
- TS stand-ins: pass-run.mjs event feeding (tested with fakes in sim-touch-runner.test.mjs), restart/warm-up glue, sim checks of probeLoop; the machine, stall rule, caps and ready are Lean-golden-checked.
- Graph writes (work graph r452) now include lean/scripts/SimTouchGolden.lean, pass-run.mjs, parts-cli.mjs.
