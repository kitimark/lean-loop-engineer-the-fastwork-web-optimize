branch: worktree-wf_750ad5a5-83d-1 (CI branch ci/touch-restart-device)
worktree: .claude/worktrees/wf_750ad5a5-83d-1
last commit: see `git log -1` (code c9055423e, CI request 4afd78df2, then handoff and note; no merge of main needed, based on 7dc190958)
CI runs: smoothness 41503168296 complete, `fw ci state` failed (jobs 3, 10, 12 hard stop). Dispatch 1 of 2 used; dispatch 2 not needed.
result: 5 restarts begun, 5 decided, 2 ready (4 of 10, 1 of 5, 5 of 9 before); reset faults driver-restart-reset-late x3, reset-failed 0; 0 of 10 terminate calls ended anything (4 absent, 6 late); 1 stall (job 5) never launched. Closed as a Simulator-limit finding; no more restart forms.
verified: Lean TouchReady builds, 73 golden lines, check.sh green; measure-webkit tests 1158/1158; runner tests 3797; ci-paths 56/56; land-inputs 73/73; lint-wallclock ok
open: nothing in the task; the in-flight launch record was not exercised by CI (test only); across-job numbers are in the note (9 insufficient of 12 = lateJobs - minSamples, no spare)

Form chosen: after the restart gate, if the old xcodebuild exited, `simctl terminate` of the XCUITest runner (dev.fastwork-study.throttle-driver.xctrunner) and host app (dev.fastwork-study.throttle-host) at once, each within 15 s (Lean resetCallMs). Overlap skips the reset. Faults: driver-restart-reset-late, driver-restart-reset-failed; the launch follows either way.
Lean: lean/Fw/Measure/TouchReady.lean (resetAct, callEnd, GateAct.nameWith, restartMs with resetCallMs = 695 s, restart_pair_exact). TS: touch-ready.mjs (replays), touch-push.mjs (terminateApp, restartReset), touchlock-run.mjs (launchesView, beginServer in-flight entry).
TS stand-ins (no golden): terminateApp's execFile and stderr match, the 15 s race in restartReset, launchesView, beginServer's in-flight entry.
Scratch: scratchpad/touch-restart-device/ (r1 = run 41503168296 download; scripts tally.mjs, jobs.mjs, kept.mjs summarise touch-lock.json).
Read first: research/notes/2026/11-03-touch-restart-device.md, then 11-02-touch-restart-ready.md.
