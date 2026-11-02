# touch-driver-ready handoff

- Branch: worktree-wf_d92539a0-78e-1 (CI branch ci/touch-driver-ready). Both dispatches used.
- CI runs: before 41369102226 (4 of 12 no ready file at 240 s), 41380162402 (6 of 12 at 480 s). After 41391781282 (3 x 150 s: 11 of 11 first starts ready, 6 of 6 restarts failed), 41402584809 (restart 1 x 470 s: 9 of 10 first starts ready, 5 launch-1 stalls, 4 recovered by relaunch, restarts 2 of 2 decided failed; jobs 7 and 9 no artifact or log).
- Note: research/notes/2026/11-02-touch-driver-ready.md (read first); pointer in 10-2x-sim-touch-reliable.md.

## State
- Lean lean/Fw/Measure/TouchReady.lean (theorem per branch), golden packages/contracts/golden/measure/touch-ready.jsonl, check.sh job, trigger row.
- JS src/touch-ready.mjs, touch-push.mjs startServer/stopServer, touchlock-run.mjs beginServer/endServer, `touch.launches` in touch-lock.json. Tally: `node packages/measure-webkit/src/touchlock-cli.mjs launches <label>=<touch-lock.json> ...`.
- Swift UITests write `alive` at body start.

## Open
- Restart after a stalled window fails with 3 x 150 s and with 1 x 470 s (cap refuted); the stop kill (every stop is driver-stop-killed) is the untested cause. Needs a new task and run.
- Dry land refuses on scope: Trigger.lean, throttle/driver.mjs, throttle/push-cycle-pass.mjs, TouchReadyGolden.lean, check.sh, ci/triggers.jsonl are outside the row's writes (work-graph.json not edited).
