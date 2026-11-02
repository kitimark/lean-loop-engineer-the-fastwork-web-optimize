# touch-driver-ready handoff

- Branch: worktree-wf_d92539a0-78e-1 (CI branch ci/touch-driver-ready), worktree .claude/worktrees/wf_d92539a0-78e-1, work at 2897ade5d (merge of main ea4bfc08d). Both dispatches used; no run pending.
- CI runs: before 41369102226 (4 of 12 no ready file at 240 s), 41380162402 (6 of 12 at 480 s). After 41391781282 (3 x 150 s: 11 of 11 first starts ready, 6 of 6 restarts not ready, with the stop kill), 41402584809 (restart 1 x 470 s: 9 of 10 first starts ready, 5 launch-1 stalls, 4 recovered by relaunch, restarts 2 of 2 decided not ready, with the stop kill; jobs 7 and 9 no artifact or log).
- Note: research/notes/2026/11-02-touch-driver-ready.md (read first); pointer in 10-2x-sim-touch-reliable.md.

## State
- Lean lean/Fw/Measure/TouchReady.lean (theorem per branch), golden packages/contracts/golden/measure/touch-ready.jsonl, check.sh job, trigger row.
- JS src/touch-ready.mjs, touch-push.mjs startServer/stopServer, touchlock-run.mjs beginServer/endServer, `touch.launches` in touch-lock.json. Tally: `node packages/measure-webkit/src/touchlock-cli.mjs launches <label>=<touch-lock.json> ...`.
- Swift UITests write `alive` at body start.

## Open
- Stop kill removed (finisher round): stopServer = main's stop path, named fault `driver-stop-late`. Restart readiness after it is INFERRED (main: 5 of 9); one 12-job CI run would confirm.
- Job 1 of 41402584809 ended INCOMPLETE (walk hard stop, inspector dead, simctl shutdown exit 4); outside this unit.
