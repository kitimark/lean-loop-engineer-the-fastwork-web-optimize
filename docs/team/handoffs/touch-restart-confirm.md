# touch-restart-confirm handoff

- Branch: worktree-wf_0fc6ea50-ff3-1 (CI branch ci/touch-restart-confirm), worktree .claude/worktrees/wf_0fc6ea50-ff3-1, last pushed commit 8a01c8a32; local HEAD has later commits.
- CI runs (smoothness, 12 touch-lock sim jobs): dispatch 1 = push run 41422536168, fw ci state: failed (jobs 2, 5, 7, 9, 10 failed; 9 has a retry artifact). Dispatch 2 not started yet.
- Compare: touch-driver-ready 41391781282, 41402584809 (0 of 8 restarts ready with the stop kill); main's before runs 41369102226, 41380162402 (5 of 9).

## Verified (run 41422536168, scratchpad/touch-restart-confirm/tools/tally.mjs over the downloaded touch-lock.json files)
- First start ready 12 of 12 jobs (launch 1 in 7, launch 2 in 4, launch 3 in 1).
- Restarts: 4 begun (jobs 2, 3, 8, 9-retry); 3 decided, 0 ready (jobs 3, 8, 9: driver-launch-stuck at 470 s, 470 s, 528 s); job 2 undecided (inspector dead, simctl shutdown ETIMEDOUT). All four stalls were pageLost.
- Late stops: 8 stops late (7 body or teardown named by the old rule), 1 clean (job 11, 17 s). Stop tails show the test body in "Wait for com.apple.springboard to idle" (a press) then "Tear Down" 5 to 1150 s later.
- Lean TouchReady stopStep, golden, TS and package test green; check.sh green at 2539db5f3.

## Open
- Dispatch 2: same policy plus body-returned marker (Tear Down line) and CoreSimulator health probe at a restart cut; then the note research/notes/2026/11-0x-touch-restart-confirm.md.
