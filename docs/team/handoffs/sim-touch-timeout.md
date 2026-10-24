branch: worktree-wf_ff267e33-928-1 (CI branch ci/sim-touch-timeout, pushes used 1 of 3)
worktree: .claude/worktrees/wf_ff267e33-928-1
last commit: 81cf50fce (pushed to ci/sim-touch-timeout)
CI runs: 40121254572 toolbar-throttle (finish mode, sim 1-3) running at 21 min; 40121254514 lean SUCCESS (golden check in CI green)
verified: Lean SimTouch builds and its golden check is wired (check.sh job, Trigger rows, triggers.jsonl); node tests sim-touch + throttle-* pass (60); ci-paths test 56 pass; one local debug run (drags, 1 cycle, original arm): marks started/press-n appear, pass done, no restart (cap 20 s not reached)
open: restart path not walked live (needs a failing touch run; CI shows it if a pass stalls); CI finish evidence; hero-drag run (push 2); before/after table; note research/notes/2026/10-2x-sim-touch-timeout.md; full package test, lean check, land-inputs test, dry land, review ready, plan lint
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
