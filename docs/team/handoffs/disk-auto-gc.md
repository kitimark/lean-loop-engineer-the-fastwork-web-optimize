# Handoff: disk-auto-gc
State: branch `worktree-wf_ee14c2f3-4ac-1`, merged with main 9b74cd5. `fw land --dry` passes with
`--allow apps/runner/src/watch.ts --allow lean/scripts/DiskGcGolden.lean --allow lean/scripts/check.sh`.

Verified:
- `lean/Fw/Ops/DiskGc.lean` builds with no sorry. It has six classes, a closed allowlist (`pathOk`) and the theorems
  `deletes_subset_allowlist`, `never_tracked`, `owned_only`, `never_live` (`never_open`, `never_locked_live`,
  `never_queued`), `independent`, `class_alone`, one `rule_*` per class, `never_fable` and `selectFast_eq`.
  Wire ops: `ops.diskGc`, `ops.diskGcPath` in `Fw.Wire.DiskGc`, dispatched from `lean/Fw/Wire.lean`.
- `sh lean/scripts/check.sh` is green, including the new `diskgc golden check` job (28 cases). Runner tests: 2202
  pass. `scripts/ci-paths.test.mjs` and `scripts/lake-gc.test.mjs` pass.
- `apps/runner/test/disk-gc.test.ts` replays the golden and runs `--list` and `--delete` on a temp tree: worktree
  removal, symlink escape, open file, queued land, sim lock, class filter and the event line.
- Real machine `--list` (no delete), 12 s: lake 47 items/1.01 GiB, landed 0, idle 12/1.02 GiB, scratch 9/0.12 GiB,
  sim 0, console 0. 114 GiB free.

Conventions:
- The glue (`apps/runner/src/disk-gc.ts`) gathers facts only. Any fact it cannot read is sent as absent, and Lean
  then keeps the candidates that fact guards.
- Landed: the branch tip differs from its reflog creation commit and is an ancestor of main.
- Byte counts of classes 2, 3 and 5 are measured (`du`) only for the items Lean selects; a second call tallies them.
- Triggers: `fw land` with result done runs classes 1, 2, 6 (stderr). `fw watch` runs all classes when `sys.diskLow`
  opens. `FW_DISK_GC=0` turns both off.

Open:
- Daily fw-sup timer run (waits for sup-wire).
- No real `--delete` was run (the task forbids it).
- `apps/runner/test/e2e-land.sh` does not set `FW_DISK_GC=0`; its temp repo has no `lean/`, so class 1 is skipped there.

Read first: `docs/team/tools/disk-gc.md`, then `lean/Fw/Ops/DiskGc.lean` (rules from `ruleLake` on).
