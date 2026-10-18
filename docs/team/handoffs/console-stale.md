# console-stale handoff

State: round 4 on branch worktree-wf_78d166a4-1a6-1 (head: see `git log -1`; merged round-3 head bc83b8a and main).

Read first: docs/team/tools/console-stale.md, lean/Fw/Obs/Stale.lean.

Done (round 4)
- Lean: Svc gets `unknown : Option String`; code `svc.unknown` (rank 15, later codes shifted), `sUnknown`, `svcUnknown_iff`,
  `unknown_service_alerts`. Stale.lean: Stack = (apiBase, coreBase, diskBase) over the history model; theorems
  rebuild_without_restart_api_stale, rebuild_clears_disk, restartApi_after_rebuild_clears, restartApi_without_rebuild_stale,
  touched_append, judge_stale_append; `chooseBase`/`fromLog` (record vs reflog, unknown) with theorems and `#guard` table.
- TS: console-api records `coreCommit`/`coreUnknown` in api.json at every fwcore child spawn (core/lean.ts `onSpawn`, main.ts).
  TS stand-in for chooseBase: apps/console-api/src/core/build-base.ts (same table as the #guards). watch-svc.ts judges
  console-api on own inputs + fwcore inputs vs its child, and the disk binary; never drops one service for the other.
- scripts/fwcore-build.sh is the one writer of the build record (moved from docs/team/tools). BUILD_HINT and runner hints use it.

Open
- lean/scripts/check.sh still runs plain `lake build`: switching it to the script needs `scripts/fwcore-build.sh` in
  Fw/Console/LandSpeed.lean checkShReads (and its golden), outside this task's writes.
- Lands needing `--allow lean/Fw/Wire/Obs.lean`; scripts/fwcore-build.sh is a new path outside the declared writes.
- The running console-api must be restarted once to write `coreCommit`; until then `svc.unknown console-api` is raised (by design).
- TS stand-in chooseBase to be replaced by an fwcore op.
