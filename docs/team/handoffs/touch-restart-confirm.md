# touch-restart-confirm handoff

- Branch: worktree-wf_0fc6ea50-ff3-1 (CI branch ci/touch-restart-confirm), worktree .claude/worktrees/wf_0fc6ea50-ff3-1, last commit 8a01c8a32 (CI request on top of 2539db5f3).
- CI runs (smoothness, 12 touch-lock sim jobs): dispatch 1 = push run 41422536168, state: running (pushed, waiting). Dispatch 2: not used.
- Compare: touch-driver-ready 41391781282, 41402584809 (0 of 8 restarts ready with the stop kill); main's before runs 41369102226, 41380162402 (5 of 9).

## Verified
- Lean TouchReady: stopStep now splits a late stop by whether xcodebuild printed the end of the test case (driver-stop-late-body | driver-stop-late-teardown), theorems per branch, golden regenerated (41 lines); TS replays it; stopServer records `trace` per stop {waitedMs, testEndedMs, exitedMs, top, tail} in touch.launches (tag stop). measure-webkit package test green (1138).

## Open
- Read the run, tally restarts ready of decided, late stops by name, stop traces; write research/notes/2026/11-0x-touch-restart-confirm.md.
- Stop-path reading (PushServer.swift:51 loop, touch-push.mjs stopServer) goes into the note.
