# land-wait-final handoff

State: branch worktree-wf_d2d71389-809-1; Lean + TS + tests + docs committed (see `git log -1`). `sh lean/scripts/check.sh` green; runner suite 2047 pass; ci-paths 54 pass.

Cause (both incidents, INFERRED: neither waiter output was recovered): `fw ci wait` child exited 1 without judging the run (crash; incident 2 land log ended 14:09:23Z, run success 14:09:07Z).
Old Lean `waitState 1 = fail`, and the run's own record (success / in progress) was only consulted for a completed *failure*.

Fix (Lean first): `Fw.Console.LandRemote.laneState code timedOut status conclusion saidFail jobs`
- completed failure or unknown conclusion -> fail (`laneState_completed_failure`, `_completed_unknown`)
- status not completed -> running whatever the exit (`laneState_in_progress`: in progress and wait error)
- completed success + per-job results -> `legsOk` decides, also after exit 1 (`_all_success`, `_one_failure`)
- no record: waiter; exit 1 is fail only with a `-> fail` line (`saidFail`); exit 1 without it, exit 2, exit 3 are wait errors = `running` (`_wait_error_running`, `verdict_wait_error_waits`); other exits unavailable (`_wait_error`)
- timeout: `verdict_timeout_not_fail`; the TS deadline marks `timeout`, verdict `remote-timeout-run-locally`.
Wire op `console.landLaneState` got `saidFail`? (default true) and `jobs`?; golden rows in `packages/contracts/golden/console/land-remote.jsonl` (regenerated).
TS: `apps/runner/src/land-remote.ts` (`laneStateOf`, `legResults`, `failureDetail`, `AwaitOutcome.details`, `StartCtx.checks`); refusal line now
`... (github:fail) [github: run <id>, failed legs: <leg> <conclusion> [checks ...]]`. CircleCI adapter passes `-> fail` for pipeline exit 1.
Tests: `apps/runner/test/land-remote-wait.test.ts` (fake provider, both incidents).

Round 2: wait errors keep waiting (Lean); cache hit without job conclusions + non-pass waiter reads full view (land-remote.ts githubAdapter.poll); CircleCI refusal detail (circleciAdapter.poll); tests added.
Open: `legsPass` in land-remote.ts is now unused by src (kept for land-legs.test.ts); `console.landLegsVeto` op is superseded by laneState and can go in a follow-up.
No live CI proof run was made (accepted limit). Read first: docs/team/tools/land.md (new bullet "A running or green lane is never refused as failed").
