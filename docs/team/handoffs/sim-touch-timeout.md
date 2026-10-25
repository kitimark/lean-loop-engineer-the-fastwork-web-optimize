branch: worktree-wf_ff267e33-928-1 (CI branch ci/sim-touch-timeout, pushes used 3 of 3, none left)
worktree: .claude/worktrees/wf_ff267e33-928-1
last commit: see git log (head of this branch)
CI runs: 40134212357 toolbar-throttle finish on the merged code: failed (sim 2 ended with 6 of 8 passes, sim 1 died exit 130 with 1 of 8, sim 3 cancelled at 110 min); 40134212384 lean; earlier 40121254572 finish (cli.mjs, 15 of 18), 40128742749 hero drags (cli.mjs, 18 of 18)
verified: Lean SimTouch + golden (59 lines) + 712 package tests + runner 3471 + ci-paths 56 + check.sh green after merging main (c2f3928e9); fw land dry VERDICT; local debug run walked the restart path through parts-cli
cause of 40134212357: after merging main the workflow runs parts-cli.mjs, whose own pass loop bypassed the machine; fixed by moving the loop to src/throttle/pass-run.mjs (used by cli.mjs and parts-cli.mjs); NOT run in CI
open: one more push (ci/sim-touch-timeout, [ci:toolbar-throttle] [throttle:finish] in the head message) to show the merged lane; lift-arm start-up stall (sim-lift-stall); persistent push server
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
- Writes outside the graph writes (listed in the report): lean/scripts/SimTouchGolden.lean, packages/measure-webkit/src/throttle/pass-run.mjs, parts-cli.mjs.
