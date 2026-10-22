# Disk cleanup (lead runbook)

When `fw watch` raises `sys.diskLow` (free < 20 GB), work through this list in order. Measure free space with
`df -m /` before and after each step. `du` overcounts: worktrees, Lake builds and the pnpm store share blocks
through hardlinks and APFS clones, so removing a tree can free far less than its `du`.

## Where the space goes (MEASURED 2026-10-18, 460 GB disk)

| Path | Size | What | Regenerable |
|---|---|---|---|
| `~/.elan/toolchains/<toolchain>/lake/cache/artifacts` | 62 GB, 55 GB unreferenced | Lake artifact cache: every build of the 6 Lean executables (~100 MB each) is kept; nothing evicts | yes |
| `.claude/worktrees/*` | ~1.3 GB each by `du`; 15 removed freed only 2 GB | worktree checkouts; `lean/.lake/build` is hardlinked from the cache above | yes (branch refs stay) |
| `lean/.lake/build/bin` | 693 MB per checkout before `lean-bin-slim`, 358 MB after (decimal MB) | 3 executables since `lean-bin-slim`: fwcore (stripped, 78.7 MB; runs `fwtest`, `sweepsgen`, `partsgolden` as subcommands), mathview, breakgen | yes |
| `lean/.lake/mathview-cache` | 37 MB | left by a retired export cache; nothing reads it | yes |
| `~/Library/Developer` | 35 GB | CoreSimulator 19, DerivedData 11, DeviceSupport 6 | mostly |
| pnpm store, `~/.cache`, `~/Library/Caches` | 8 + 8 + 9 GB | package and tool caches | yes |

## Steps

0. **`fw disk-gc` first ([disk-gc.md](disk-gc.md)).** It covers steps 1 and 2, the idle `node_modules` and
   `lean/.lake` of unlanded worktrees, old scratch directories, unused `fw-*` Simulator devices and old
   `.fw-console/tmp` and `land-logs` entries, and our own `fw*`, `oracle*` and `instruments*.ktrace` entries in the user temp folder (class 7). Each class is decided and proved in `lean/Fw/Ops/DiskGc.lean`.
   `fw watch` already runs all classes when `sys.diskLow` opens, and every `done` land runs classes 1, 2 and 6. By hand:
   `pnpm -s fw disk-gc` (summary), `--list`, then `--delete [--class …]`. The steps below are for what it leaves.
1. **Lake artifact cache (largest win: 37.5 GB on 2026-10-18).** `pnpm -s fw lake-gc` lists the artifacts no
   checkout links or names in its traces and no live Lake build may still write or link
   ([lake-gc.md](lake-gc.md); the list is decided and proved in `lean/Fw/Ops/LakeGc.lean`). Run it when no
   `lake build` is running: a running build keeps every entry in Lake's outputs map. Delete exactly that list with:
   ```
   pnpm -s fw lake-gc --delete
   ```
   Safe: Lake treats a missing artifact as a cache miss and rebuilds
   (`Lake/Build/Common.lean:524-534`, `getArtifactsUsingCache?`, toolchain v4.35.0, CONFIRMED), except for a build
   that starts during the run (resolved at Common.lean:585, linked at :652): run it only when `fw lake-gc` shows
   `writers: none`, and rerun a build that failed meanwhile. The auto-mode
   classifier blocks this as irreversible: the user runs it or approves it. Never uninstall the pinned toolchain
   (`lean/lean-toolchain`).
2. **Finished worktrees.** For each worktree whose workflow is not running: `git worktree remove
   .claude/worktrees/<id>` (no `--force`; it refuses on uncommitted work, and the branch ref stays). Skip locked
   trees (`claude agent … pid`) and dirty ones; ask the lead.
3. **User-level caches (ask the user):** `xcrun simctl delete unavailable`; Xcode DerivedData; `pnpm store prune`.

## Prevention

Task `lean-bin-slim`: one stripped fwcore in place of four executables (a full rebuild stores 400 MB in the cache
instead of 707 MB) and `fw lake-gc` (step 1). Run `fw lake-gc --check` on every `sys.diskLow`; it exits 1 when the
cache is over its 20 GB budget. A `fw watch` alert on cache size (`sys.lakeCache`) is a followup. The cache grew
about 3 GB per hour with 10 agents building, and on 2026-10-18 it held 12.8 GB younger than 2 h with 27 worktrees.
