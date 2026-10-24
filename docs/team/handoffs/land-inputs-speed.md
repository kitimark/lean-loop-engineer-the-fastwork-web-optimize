# land-inputs-speed handoff

Branch worktree-wf_dd64e732-4a2-1, worktree .claude/worktrees/wf_dd64e732-4a2-1. Last commit: see `git log -1`. CI runs: none (local harness task).

## State
- Cause (CONFIRMED, note `research/notes/2026/10-2x-land-inputs-speed.md`): after land-inputs-growth the land-inputs vitest is flat at 8 s; the 98 later dry lands split by modules built: lake step 3.1 / 13.0 / 23.5 s, total 18.0 / 27.7 / 44.4 s; 35 of 37 over-30 s lands built a module.
- Change: Lean `Fw.Ops.LandCache` (key = lean/ tree id + packages/contracts/golden tree id; theorems incl. `skip_sound`, one per record source), golden `packages/contracts/golden/ops/land-cache.jsonl`, TS stand-in `lakeHit`/`runLake`/`lakeRecords` in `apps/runner/src/land.ts` (dry path only), replayed in `apps/runner/test/land-inputs.test.ts`. `FW_LAND_LAKE_CACHE=off` disables.
- Before/after, same head and main: 26.1 s (lake 15.3 s, 6 built) -> 10.0 s (lake skipped), in the note.
- Verified: check.sh green at the merge commit; land-inputs test 73 green.

## Open
- Outside the task's writes: `lean/Fw.lean` (one import line, `Fw.Ops.LandCacheGolden`, needed by check-imports).
- No check.sh row for the golden (a `#guard` with include_str checks it at lake build); lead may add a gen --check job and its trigger row.
- Hit rate on later dry lands is read after landing from the `dry: lake build and axiom check skipped` log lines.

## Conventions
- A skipped lake step ends as span `dry total`, not `dry total lake`.
- The premise (lake build reads outside lean/ only packages/contracts/golden) is a runner test; a new include_str elsewhere fails it.

## Read first
The note, then `lakeRecords` and the dry path in `apps/runner/src/land.ts`.
