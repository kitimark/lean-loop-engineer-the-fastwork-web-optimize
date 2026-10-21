# fw disk-gc: six cleanup classes, each decided by Lean

`pnpm -s fw disk-gc` lists what six cleanup classes may delete; `--delete` removes exactly that list. Each class is
decided on its own (a candidate of one class never changes the verdict on another).
- Spec and proofs: `lean/Fw/Ops/DiskGc.lean` (fwcore ops `ops.diskGc`, `ops.diskGcPath`).
- Glue: `apps/runner/src/disk-gc.ts`. It gathers facts, asks fwcore, and prints or deletes. It decides nothing.
- Golden vectors: `packages/contracts/golden/ops/diskgc.jsonl` (`lean/scripts/DiskGcGolden.lean`, checked by
  `lean/scripts/check.sh`), replayed through the built fwcore by `apps/runner/test/disk-gc.test.ts`. The same test
  runs `--list` and `--delete` on a temp tree.

## Classes

| # | Name | Deletes | Rule (besides the guard below) |
|---|---|---|---|
| 1 | `lake` | files in Lake's `artifacts` cache | `Fw.Ops.LakeGc.ok` under the same root ([lake-gc.md](lake-gc.md)) |
| 2 | `landed` | `.claude/worktrees/<w>` via `git worktree remove` (branch kept) | branch has its own commit and main contains it; no uncommitted or untracked change |
| 3 | `idle` | `node_modules`, `lean/.lake`, `apps/<x>/node_modules`, `packages/<x>/node_modules` of an unlanded worktree | its HEAD commit and changed files are older than `--idle-h` (24 h) |
| 4 | `scratch` | `/private/tmp/claude-<uid>/<project>/<session>/scratchpad/<dir>` | a directory, no file newer than `--scratch-h` (8 h), no `scratchpad/<dir>` on main (`git grep`), name not `fable…` |
| 5 | `sim` | Simulator devices via `xcrun simctl delete <udid>` | named `fw-…`, `Shutdown`, its name not on main in `.github`, `packages`, `apps`, `scripts`; sim lock `<main>/.local/locks/sim` absent |
| 6 | `console` | `.fw-console/tmp/<n>`, `.fw-console/land-logs/<n>` | no file newer than `--keep-days` (7) |

The guard applies to every class (theorems in `DiskGc.lean`):
- `deletes_subset_allowlist`: the path lies under the class root in one of the shapes above. No segment is `.`,
  `..`, empty or `.local`.
- `never_tracked`: no tracked file.
- `owned_only`: owned by the running user.
- `never_live`: no process has a file open or its cwd inside (`lsof`), no live worktree lock (pid and start time
  match `ps`), no queued land of its branch.
- `independent`, `class_alone`: `--class c` selects exactly class c's part of the full list.

A fact that could not be read (`lsof`, `ps`, the land queue, `git grep`, the sim lock) keeps every candidate it
guards.

## Use

| Command | Prints | Exit |
|---|---|---|
| `fw disk-gc` | count and GiB per class, free space | 0 |
| `fw disk-gc --list` | `<num> <class> <bytes> <path>` per item | 0 |
| `fw disk-gc --json` | the Lean reply | 0 |
| `fw disk-gc --delete` | a line per path it kept, deleted and failed counts, free space before and after | 1 if a deletion failed |
| `--class 1,landed` | only these classes (number or name; repeatable) | |
| `--idle-h N`, `--scratch-h N`, `--keep-days N` | the class 3, 4, 6 ages | |

Before each deletion the glue checks the path again: `realpath` equals the path (no symlink), the owner is still
the user, and `ops.diskGcPath` accepts it. `git worktree remove` is never forced. It refuses a dirty worktree; a lock
whose holder is gone is removed first. Every `--delete` appends one
`{"type":"diskgc.run", at, mode, classes, deleted, failed, freeBefore, freeAfter}` line to
`<main>/.fw-console/disk-gc.jsonl`.

## Triggers

- After a land that ends `done` (`fw land`, `fw land --queue`): classes 1, 2, 6 in the main checkout. `DISKGC`
  lines go to stderr; the span is `fw land / disk-gc (post-land)`.
- `fw watch --interval` and `--stream`: when `sys.diskLow` opens, all six classes; one `DISKGC …` line.
- `FW_DISK_GC=0` turns both triggers off. A daily run from the fw-sup timer is a follow-up (task sup-wire).

## Limits

- Byte counts come from `du` and block counts, and they overstate on APFS (clones, hardlinks into the Lake cache
  and the pnpm store). `df` before and after shows what was really freed.
- Class 5 decides by name and state, not by usage history.
- Class 3 activity is the HEAD commit time and the mtimes of changed files. A worktree whose only activity is
  builds counts as idle once 24 h pass; a running agent's worktree lock (pid and start time of its session process) keeps it; `lsof` keeps it only while a command runs inside it. An unlocked worktree whose agent is between commands is not protected by lsof.

## Real machine, 2026-10-21 (`--list`, no delete)

MEASURED: 12 s for a full run. 114 GiB free.

| Class | Items | GiB |
|---|---|---|
| 1 lake | 47 | 1.01 |
| 2 landed | 0 | 0 |
| 3 idle | 12 | 1.02 |
| 4 scratch | 9 | 0.12 |
| 5 sim | 0 | 0 |
| 6 console | 0 | 0 |

6608 candidates were kept. Before this run the lead had already deleted the lake list, 220 scratch directories and
3 `fw-*` devices by hand.
