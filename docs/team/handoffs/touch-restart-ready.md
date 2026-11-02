branch: worktree-wf_b555badb-494-1 (CI branch ci/touch-restart-ready)
worktree: .claude/worktrees/wf_b555badb-494-1 (under the repo checkout)
last commit: 0c6b07ac0 (ci commit; work in ca6d9ab58)
CI runs: smoothness 41460411752 running (dispatch 1 of 2, 12 touch-lock jobs, pushed 0c6b07ac0)
verified: Lean gate section builds, `sh lean/scripts/check.sh` green, measure-webkit tests 1146/1146 (incl. 8 new in touch-restart-ready.test.mjs)
open: run 1 counts (restarts begun/decided/ready, launch times, loggedAt, faults by name), compare to 1 of 5 (touch-restart-confirm) and 5 of 9 (main); research note; merge main, plan lint, dry land, review ready

What changed
- Lean `Fw/Measure/TouchReady.lean`: Gate section. `gateStep` (wait-exit, recheck, launch with overlap and unsure names), `restartMs`, `restartAllowMs` 700 s, `restart_pair_fits` against the WalkBudget deadline. One theorem per branch. Golden `packages/contracts/golden/measure/touch-ready.jsonl` regenerated from Lean (op gate).
- `touch-ready.mjs`: GATE, RESTART_ALLOW_MS, gateStep, `loggedAt` in launch records.
- `touch-push.mjs`: stopServer re-reads the log at the decision, no sync probes at the stop; `hostProbes` async; `probeStop`; `restartGate`; `startServer` `onLaunched` hook.
- `touchlock-run.mjs`: endServer returns the server; the stall branch runs restartGate (ctx.check + probeInspector) before the restart; probes start after the restart launch begins.
- TS stand-ins (not golden-checked): the polling and timing glue in restartGate/stopServer, async probes, `onLaunched` wiring.

Conventions: scratch in scratchpad/touch-restart-ready/<run>/ (one dir per download); shell guard rejects heredocs and computed commands, use Write for scripts.
Read first: lean/Fw/Measure/TouchReady.lean (Gate section), packages/measure-webkit/src/touch-push.mjs (restartGate), research note when written.
