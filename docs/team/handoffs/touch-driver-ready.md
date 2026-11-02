# touch-driver-ready handoff

- Branch: worktree-wf_d92539a0-78e-1 (CI branch ci/touch-driver-ready). Worktree: .claude/worktrees/wf_d92539a0-78e-1.
- Last commit pushed to CI: 4132e3661 (code 3da8f5d08, Lean 20a529325).
- CI runs: 41391781282 smoothness (12 touch-lock Simulator jobs), in progress at the time of writing. Before: 41369102226 (4 of 12 no ready file at 240 s), 41380162402 (6 of 12 at 480 s).

## State
- Lean: lean/Fw/Measure/TouchReady.lean (launch verdict, replay, stop step, tally; theorem per branch), golden packages/contracts/golden/measure/touch-ready.jsonl, check.sh job, trigger row.
- Swift: UITests/PushServer.swift and FinishServer.swift write `alive` when the test body starts (before the Safari checks).
- JS: src/touch-ready.mjs (verdict, replay, stopStep, tallyJobs, launchUntilReady, jobOf, firstStart); src/touch-push.mjs startServer (up to 3 launches, 150 s each, kill, named fault, ps sample, log tail) and stopServer (kill after 20 s, `driver-stop-killed`); throttle/driver.mjs runGroup `ctl` and serve `kill`; touchlock-run.mjs beginServer/endServer and `touch.launches` in touch-lock.json; sim-cadence push.launches.
- Tests: test/touch-ready.test.mjs replays the golden through the pure functions and through the real loop on a virtual clock; touchlock tests updated. `pnpm --filter @fw/measure-webkit test` passes (1135 tests).
- Tally helper: `node packages/measure-webkit/src/touchlock-cli.mjs launches <label>=<touch-lock.json> ...`.

## Open
- Read the 12 jobs of 41391781282 (artifacts, `touch.launches` in touch-lock.json), tally, write research/notes/2026/11-0x-touch-driver-ready.md and the pointer in 10-2x-sim-touch-reliable.md.
- Dry land and `fw review ready` not run yet. apps/runner tests cannot run in this worktree without a pnpm install of that package (the install done is offline frozen-lockfile).
- Cause is INFERRED (bimodal slow or hung xcodebuild launch under host starvation, plus the old stop without kill). A killed launch may leave its runner on the Simulator; not checked.
