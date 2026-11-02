branch: worktree-wf_b555badb-494-1 (CI branch ci/touch-restart-ready)
worktree: .claude/worktrees/wf_b555badb-494-1
last commit: see `git log -1` on the branch (CI pushed from 41b2aee41; later commits: 25 s bound on a gate check, note, handoff)
CI runs: smoothness 41460411752 failed (dispatch 1, gate without simctl, 0c6b07ac0); smoothness 41475879793 failed (dispatch 2, gate with simctl, 41b2aee41).
verified: Lean Gate section builds and `sh lean/scripts/check.sh` green; measure-webkit tests pass (10 new in touch-restart-ready.test.mjs); ci-paths 56/56; runner land-inputs 73/73; plan lint 0 errors
open: dry land and `fw review ready` (see report); the 25 s bound on a gate check came after run 2 and is not CI-measured

Result (research/notes/2026/11-02-touch-restart-ready.md): gated restarts 0 of 3 (run 1) and 4 of 7 (run 2) ready, against 1 of 5 and 5 of 9 without the gate; no separation.
Gate was clean in all 3 run-1 restarts and they still stalled: overlap and reboot were not the cause there. First 150 s launch ready in 12 of 23 jobs, so restart readiness follows the Simulator state (INFERRED).
Run 2 gates ran 347 s and 228 s (guard check waits on a recovery): fixed with the 25 s race; one launch overshot its 470 s cut by 626 s on a starved host (job 11).

TS stand-ins (not golden-checked): timing and polling in restartGate/stopServer, async host probes, onLaunched hook, the sim answer in the device check, the 25 s race.
Conventions: scratch in scratchpad/touch-restart-ready/<run>/ (one dir per download); the shell guard rejects heredocs and computed commands, use Write for scripts.
Read first: the note above, lean/Fw/Measure/TouchReady.lean (Gate section), packages/measure-webkit/src/touch-push.mjs (restartGate).
