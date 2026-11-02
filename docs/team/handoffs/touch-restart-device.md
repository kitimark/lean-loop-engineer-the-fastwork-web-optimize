branch: worktree-wf_750ad5a5-83d-1 (CI branch ci/touch-restart-device)
worktree: .claude/worktrees/wf_750ad5a5-83d-1
last commit: 4afd78df2 (CI request commit on top of c9055423e, the code)
CI runs: smoothness 41503168296 running (dispatch 1 = the push of 4afd78df2, 12 touch-lock simulator jobs, flag fw=morph.tween:end-pin). Dispatch 2 not used.
verified: Lean TouchReady builds (Reset section, 73 golden lines regenerated, --check green); measure-webkit tests 1158/1158; lint-wallclock ok
open: read run 41503168296 (restarts begun/decided/ready, reset durations, faults), note, closed decision, final checks (check.sh, ci-paths, runner land-inputs, plan lint, dry land, review ready)

Form chosen: after the restart gate, if the old xcodebuild exited, `simctl terminate` of the XCUITest runner (dev.fastwork-study.throttle-driver.xctrunner) and host app (dev.fastwork-study.throttle-host) at once, each within 15 s (Lean resetCallMs). Overlap (old xcodebuild alive) skips the reset: nothing is killed. Faults by name: driver-restart-reset-late, driver-restart-reset-failed; the launch follows either way.
Lean: lean/Fw/Measure/TouchReady.lean (resetAct, callEnd, GateAct.nameWith, restartMs now with resetCallMs = 695 s, restart_pair_exact). TS: touch-ready.mjs (replays), touch-push.mjs (terminateApp, restartReset), touchlock-run.mjs (launchesView, beginServer in-flight entry).
TS stand-ins (no golden): terminateApp's execFile and stderr match, the 15 s race in restartReset, launchesView, beginServer's in-flight entry.
Scratch: scratchpad/touch-restart-device/ (r2 = run 41475879793 download, scripts/sum.mjs summarises touch-lock.json).
Read first: research/notes/2026/11-02-touch-restart-ready.md, then the note 11-03-touch-restart-device.md (when written).
