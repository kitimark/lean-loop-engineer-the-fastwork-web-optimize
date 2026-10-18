# console-stale handoff

State: round 3 on branch worktree-wf_56a18937-3ba-1 (head: see `git log -1`). check.sh green, runner+console-api tests green.

Read first: docs/team/tools/console-stale.md, lean/Fw/Obs/Stale.lean.

Done
- Lean: Fw.Obs.Stale. No timestamps (fw land builds the merge commit before its checks and moves main 23-89 s later,
  MEASURED). Svc = name + inputs `{path, changed : Bool}`; changed = the first-parent range `base..main` touches the path.
  Theorems: stale_iff, mem_changed, history model (`touched`, `judge_head_not_stale`, `touched_of_mem`), restart_clears,
  Stack.restart_without_build_stale (restarting console-api leaves a stale fwcore stale), Stack.rebuild_clears.
  Health: code `svc.stale`, `sStale`, svcStale_iff, staleAlert_fields, sStale_restart; Wire/Obs.lean decodes `svcs`.
- TS: apps/runner/src/watch-svc.ts. console-api base = `commit` in api.json (HEAD at start). fwcore is its own service:
  base = `lean/.lake/build/bin/fwcore.commit` written by `scripts/fwcore-build.sh`; without it the binary mtime picks
  the newest first-parent commit at or before it (stated PREMISE, can miss a change in the 23-89 s land window).
- Tests: apps/runner/test/watch-svc.test.ts (real git: commit-tree at T-1 min, start at T, ff at T+1 min => stale;
  restart clears; fwcore stays stale after a console-api restart; rebuild clears; mtime premise).

Open
- Build the main checkout's binary with `sh scripts/fwcore-build.sh` (plain `lake build` leaves no record, so the mtime
  premise applies). Running console-api must be restarted once to write a full `commit` (old api.json: no alert).
- fw land does not print "restart" hints (optional).
- lean/Fw/Wire/Obs.lean is outside the task's declared writes: land with `--allow lean/Fw/Wire/Obs.lean` or add it to
  docs/team/work-graph.json writes.
