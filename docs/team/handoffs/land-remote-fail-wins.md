# land-remote-fail-wins handoff

State: branch worktree-wf_63e38864-594-1, round 2 (the commit is in the report; round 1 was 54aef56b). A lane run that completed with conclusion failure and binds the wanted sha and
digest is `fail` and refuses (`remote-lane-failed`), whatever `fw ci wait` exited with.

Cause (CONFIRMED from source): `stateOfWaitExit` mapped only exit 1 to fail, and the adapter read the run (`gh run view`) only for
exits 0 and 1 with a run id found by `run (\d+) ` in the waiter output. Exit 2/3/4 (a refused or failed gh call for the jobs,
a guard-skipped verdict) gave `unavailable`/`cancelled`, no view, and the verdict fell back to the local tier.

Incident exit (INFERRED): run 39338755874 gave waiter exit 4 (not-run): the local timings of the run show the guard job logging both
`decision: run` and `decision: skip`, and the land job exiting 1 at `stale: a newer push is the branch tip`. Regression case: test
"incident run 39338755874".

Round 2: the run list has `--workflow land` and a view counts only when `workflowName` is the lane; cached waiter facts (runs-status
file, `meta/<id>.jobs.json`, `cachedLaneView`) are read before any extra gh call; extra calls get the slice deadline and abort signal
(`Gh` takes `{deadline, signal}`); budget refused with no cache -> waiter outcome stands, logged. Lean: `hb` dropped from
`verdict_completed_failure_refuses` / `verdict_no_local_after_failure` (proved inside by `simp [Want.binds, laneRun]`).

Done:
- Lean `Fw.Console.LandRemote`: `waitState`, `completedFailure`, `laneState`, `laneRun`; theorems `laneState_completed_failure`,
  `laneState_waiter`, `verdict_completed_failure_refuses`, `verdict_no_local_after_failure`; golden cases `stateCases` (waiter exit
  0..5 next to a completed failure, plus pass/running/unavailable). New op `console.landLaneState` (Wire/Console.lean).
- TS (`apps/runner/src/land-remote.ts`): `stateOfWaitExit` is gone; `laneStateOf` calls fwcore; `githubAdapter` needs `call` and reads
  the run record after any exit except a plain `timed out after` (run id from the output, else `gh run list --branch --commit`).
- `land.ts`: every remote line also goes to the land log file and stderr (`logLine`).
- Tests: `land-remote.test.ts`, last describe (exits 0..4, id in output or by listing, `runTiered` never runs the remote tier here).

Open: CircleCI adapter stays a stub; a completed `timed_out` conclusion is not treated as failure (the waiter outcome stands);
`logLine` in land.ts has no direct test (glue). Read first: `lean/Fw/Console/LandRemote.lean` (`laneState`), `land-remote.ts` (`poll`).
