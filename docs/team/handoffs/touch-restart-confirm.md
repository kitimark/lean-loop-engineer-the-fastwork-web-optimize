# touch-restart-confirm handoff

- Branch: worktree-wf_0fc6ea50-ff3-1 (CI branch ci/touch-restart-confirm), worktree .claude/worktrees/wf_0fc6ea50-ff3-1, last pushed commit 085404679. Both pushes used; no third.
- CI runs (smoothness, 12 touch-lock sim jobs): run 1 = 41422536168 (8a01c8a32), run 2 = 41436626306 (085404679, body-returned marker and host health). `fw ci state`: failed for both (some jobs failed or cancelled; uploaded touch-lock data is complete).
- Compare: touch-driver-ready 41391781282, 41402584809 (0 of 8 restarts ready with the stop kill); main's before runs 41369102226, 41380162402 (5 of 9).
- Note: research/notes/2026/11-02-touch-restart-confirm.md (read first).

## Verified
- First start ready: run 1 12 of 12, run 2 10 of 10 jobs with data.
- Restarts without the kill: 1 of 5 decided ready (run 1 0 of 3, run 2 1 of 2); 4 of 9 begun undecided. Not distinguishable from 5 of 9 (p about 0.24) or 0 of 8: restart readiness is NOT confirmed.
- Late stop cause: stop file read once per loop turn (PushServer.swift:51), presses at :58/:61 block in quiescence wait; then teardown/xcodebuild exit takes 70 to >250 s. Run 1 7 of 8 late stops were teardown after `Tear Down`.
- Lean TouchReady stopStep (late-body | late-teardown), golden (41 lines), TS replay, package tests green. Stop wait 20 s and restartCfg 470 s unchanged; no kill.
- `fileTail` (64 KB read in the stop loop) is unit-tested but not measured on CI (two stop waits ran 34.7 and 108.2 s).

## Open
- More decided restarts needed (walk length or several runs); memory probe over the walk; presses off the main thread is a Swift change, not done.
- Final checks: merge main, tests, check.sh, plan lint, dry land, review ready.
