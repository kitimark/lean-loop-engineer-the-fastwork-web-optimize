# Disk cleanup (lead runbook)

When `fw watch` raises `sys.diskLow` (free < 20 GB), work through this list in order. Measure free space with
`df -m /` before and after each step. `du` overcounts: worktrees, Lake builds and the pnpm store share blocks
through hardlinks and APFS clones, so removing a tree can free far less than its `du`.

## Where the space goes (MEASURED 2026-10-18, 460 GB disk)

| Path | Size | What | Regenerable |
|---|---|---|---|
| `~/.elan/toolchains/<toolchain>/lake/cache/artifacts` | 62 GB, 55 GB unreferenced | Lake artifact cache: every build of the 6 Lean executables (~100 MB each) is kept; nothing evicts | yes |
| `.claude/worktrees/*` | ~1.3 GB each by `du`; 15 removed freed only 2 GB | worktree checkouts; `lean/.lake/build` is hardlinked from the cache above | yes (branch refs stay) |
| `lean/.lake/build/bin` | 662 MB per checkout | 6 executables (mathview, fwtest, fwcore, partsgolden, sweepsgen, breakgen) | yes |
| `lean/.lake/mathview-cache` | 37 MB | math-view export cache (JSON) | yes |
| `~/Library/Developer` | 35 GB | CoreSimulator 19, DerivedData 11, DeviceSupport 6 | mostly |
| pnpm store, `~/.cache`, `~/Library/Caches` | 8 + 8 + 9 GB | package and tool caches | yes |

## Steps

1. **Lake artifact cache (largest win: 37.5 GB on 2026-10-18).** Delete artifacts no checkout links to
   (link count 1) and older than 2 h, so files a running build just wrote stay:
   ```
   find ~/.elan/toolchains/<toolchain>/lake/cache/artifacts -type f -links 1 -mmin +120 -delete
   ```
   Safe: Lake treats a missing artifact as a cache miss and rebuilds
   (`Lake/Build/Common.lean:521-535`, `getArtifactsUsingCache?`, toolchain v4.35.0, CONFIRMED). The auto-mode
   classifier blocks this as irreversible: the user runs it or approves it. Never uninstall the pinned toolchain
   (`lean/lean-toolchain`).
2. **Finished worktrees.** For each worktree whose workflow is not running: `git worktree remove
   .claude/worktrees/<id>` (no `--force`; it refuses on uncommitted work, and the branch ref stays). Skip locked
   trees (`claude agent … pid`) and dirty ones; ask the lead.
3. **User-level caches (ask the user):** `xcrun simctl delete unavailable`; Xcode DerivedData; `pnpm store prune`.

## Prevention

Task `lean-bin-slim` (work graph): one stripped executable instead of six, `fw lake-gc` (lists step 1's files
and prints the command), and a watch alert on cache size. Until it lands, repeat step 1 on every `sys.diskLow`;
the cache grew about 3 GB per hour with 10 agents building.
