# touch-restart-confirm handoff

- Branch: worktree-wf_0fc6ea50-ff3-1 (CI branch ci/touch-restart-confirm), worktree .claude/worktrees/wf_0fc6ea50-ff3-1, last pushed commit 085404679.
- CI runs (smoothness, 12 touch-lock sim jobs, pushes of ci/touch-restart-confirm): run 1 = 41422536168 (8a01c8a32), fw ci state: failed (jobs 2, 5, 7, 9, 10 failed; job 9 has a retry artifact). Run 2 = 41436626306 (085404679, same policy, body-returned marker and host health), state: running. Both pushes used; no third.
- Compare: touch-driver-ready 41391781282, 41402584809 (0 of 8 restarts ready with the stop kill); main's before runs 41369102226, 41380162402 (5 of 9).

## Verified (run 41422536168; scratchpad/touch-restart-confirm/tools/tally.mjs over the downloaded touch-lock.json files)
- First start ready 12 of 12 jobs (launch 1 in 7, launch 2 in 4, launch 3 in 1).
- Restarts: 4 begun (jobs 2, 3, 8, 9-retry); 3 decided, 0 ready (jobs 3, 8, 9: driver-launch-stuck at 470, 470, 528 s); job 2 undecided (inspector dead, simctl shutdown ETIMEDOUT). All four stalls were pageLost.
- Stops: 8 late, 1 clean (job 11, 17 s). Stop log tails: the test body is in "Wait for com.apple.springboard to idle" inside a press (PushServer.swift:58, :61 block; the stop file is read only at :51), then "Tear Down" appears in 6 of 8 tails; xcodebuild exits 70 s (jobs 3, 8), 161 s, 254 s after the stop file in the restart jobs.
- Lean TouchReady stopStep (late-body | late-teardown), golden, TS and package test green; check.sh green at 2539db5f3.

## Open
- Run 2 result: tally with the same script (keys bodyEndedMs, trace.health), pool restarts with run 1, then write research/notes/2026/11-0x-touch-restart-confirm.md, merge main, dry land, review ready.
