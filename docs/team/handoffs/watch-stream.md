# watch-stream handoff

State: branch worktree-wf_13b194bb-996-1, merged with main 44c27ad2; this note is the last commit.

Verified (local, at the head):
- `sh lean/scripts/check.sh`: all lean/ gates green (mathview lint 0 failing). Axioms: propext, Quot.sound,
  Classical.choice only.
- apps/runner: tsc clean, vitest 32 files / 1013 tests pass. watch.test.ts replays the ops.watchDiff/ops.watchKeep
  goldens against the built fwcore (it skips when no fwcore is built).

What exists:
- lean/Fw/Ops/WatchDiff.lean: `step` (opened, closed, next) over the open key set. Its theorems: `run`,
  `opened_once` (per key the lines alternate OPEN/CLOSE), `every_open_reported`, `diff_per_key`, `proj_step`,
  `run_state_iff` and `run_last`. Keep identity: `keepPids` with `keep_same_process`, `keep_iff`,
  `reused_pid_not_kept`, and the Monitor allowlist `monitorShapes` (`monitor_shape_iff`). Wire ops: `ops.watchDiff`,
  `ops.watchKeep`. Goldens in packages/contracts/golden/ops/.
- apps/runner/src/watch.ts: `--stream` prints OPEN/CLOSE/STREAM END and keeps its open set in .fw-console/stream.json.
  `newAlerts` (--until-alert) now calls ops.watchDiff. `--keep` records the `ps lstart` start.
- apps/runner/src/watch-collect.ts: collectSystem takes a `keepOf` decider (ops.watchKeep) over lstart rows; there is
  no clock match any more.
- docs/team/tools/fw-watch.md: how the lead uses the stream and the waits.

Open items:
- docs/team/tools/watch.md (out of this task's scope) still describes `{pid, startedAt, note}` and the old --keep
  drop rule. Point it to fw-watch.md.
- keep.json entries in the old format are dropped, so long-runners must be declared again.
- Pid reuse between the two ps calls of one check (etime and lstart, milliseconds apart) is not covered.
- The Monitor allowlist is one exact argv string; a different interval is not exempt.

Read first: fw-watch.md, then the module doc of WatchDiff.lean.
