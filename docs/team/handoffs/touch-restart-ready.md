branch: worktree-wf_b555badb-494-1 (CI branch ci/touch-restart-ready)
worktree: .claude/worktrees/wf_b555badb-494-1 (under the repo checkout)
last commit: see `git log -1` (run 2 pushed from the commit named "ci touch-restart-ready: dispatch 2")
CI runs: smoothness 41460411752 failure (dispatch 1, form: gate without simctl, commit 0c6b07ac0); dispatch 2 id in the report
verified: Lean gate section builds, `sh lean/scripts/check.sh` green, measure-webkit tests all pass (9 new in touch-restart-ready.test.mjs), ci-paths 56/56, runner land-inputs 73/73, plan lint 0 errors
open: run 2 counts; research note; dry land; review ready

Run 1 (MEASURED, 12 jobs, 11 artifacts: job 3 has none): 3 restarts begun, 3 gates decided (all `launch`, old driver exited at 36/110/60 s, inspector answered), 0 ready. All 3 new launches logged (first byte +107/+279/+46 s) and never reached alive in 470 s; simctl did not answer at launch start (3 of 3) and at the cut (2 of 3, third 10018 ms); memFree 13-18% at the stop. First starts: 7 of 11 ready on launch 1; jobs 9 and 12 never ready (3 x 150 s).
Compare: touch-restart-confirm 1 of 5, main 5 of 9. Overlap and a concurrent reboot did not occur in run 1, yet restarts failed: points to the Simulator service (simctl) being wedged.
Run 2 form: gate also requires simctl to answer (25 s probe, 2 checks, 30 s gap; inside the 700 s restart allowance).

TS stand-ins (not golden-checked): polling and timing glue in restartGate/stopServer, async host probes, onLaunched wiring, the sim answer inside deviceOk.
Conventions: scratch in scratchpad/touch-restart-ready/<run>/ (one dir per download); shell guard rejects heredocs and computed commands, use Write for scripts. Analysis script an2.mjs (scratchpad tools-trr) prints per-job launches and gates.
Read first: lean/Fw/Measure/TouchReady.lean (Gate section), packages/measure-webkit/src/touch-push.mjs (restartGate), research note when written.
