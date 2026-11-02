# touch-driver-ready handoff

- Branch: worktree-wf_d92539a0-78e-1 (CI branch ci/touch-driver-ready). Worktree: .claude/worktrees/wf_d92539a0-78e-1.
- CI runs: 41391781282 smoothness at 4132e3661 (state failed: job 5 and 10 artifact uploads, job 12 hard stop; 11 of 12 jobs have touch-lock.json). Before: 41369102226 (4 of 12 no ready file at 240 s), 41380162402 (6 of 12 at 480 s). Second dispatch (the last) follows this commit.

## State
- Lean: lean/Fw/Measure/TouchReady.lean (verdict, replay, stop step, tally, `cfg` 3 x 150 s and `restartCfg` 1 x 470 s; theorem per branch), golden packages/contracts/golden/measure/touch-ready.jsonl (38 lines), check.sh job, trigger row.
- Swift: UITests/PushServer.swift and FinishServer.swift write `alive` when the test body starts.
- JS: src/touch-ready.mjs; src/touch-push.mjs startServer/stopServer; throttle/driver.mjs runGroup `ctl`, serve `kill`; touchlock-run.mjs beginServer/endServer (restart uses RESTART_CFG), `touch.launches` in touch-lock.json; sim-cadence push.launches. Tally: `node packages/measure-webkit/src/touchlock-cli.mjs launches <label>=<touch-lock.json> ...`.
- Run 1 result (MEASURED): 11 of 11 first starts ready on launch 1 (alive 39 to 126 s, ready 1 to 5 s after alive, so the delay is the xcodebuild launch, not Safari). 6 of 6 restarts after a stalled window failed: three launches cut at 150 s, all driver-launch-stuck. Old runs: restarts became ready after 74 to 220 s, so a 150 s cap cut them. Second run gives a restart one 470 s launch.
- Every job's final stop hit driver-stop-killed (xcodebuild does not exit within 20 s of the stop file).

## Open
- Read the second run, write research/notes/2026/11-0x-touch-driver-ready.md and the pointer in 10-2x-sim-touch-reliable.md.
- Dry land and `fw review ready` not run yet. First-start relaunch was never exercised (no first-start fault in run 1); a rate drop from 4 to 6 of 12 to 0 of 11 is not attributed to the change.
