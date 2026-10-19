# Handoff: lake-gc-refs

**State.** Branch `worktree-wf_9c94d061-3e9-1`. `fw lake-gc` decides by identity: checkout trace references plus
live Lake writers. The age floor is only a named Lean fallback. `fw lake-gc --delete` exists. No cache was deleted.

**Verified.**
- `lean/Fw/Ops/LakeGc.lean` builds with no sorry. Theorems: one per OR-branch, the fallbacks, `superset_when_idle`,
  and `fast_eq`.
- Goldens regenerated (16 cases). `node --test scripts/lake-gc.test.mjs` passes 4/4 (golden replay, identity,
  live writer and fallback, `--delete` on a scratch cache).
- apps/runner `pnpm test` passes (1138 tests), `scripts/ci-paths.test.mjs` passes, `sh lean/scripts/check.sh` is
  green.

**Dry run, 2026-10-20.** With no writer running: 265 files, 2.99 GB. Age rule: 49 files, 0.57 GB. With any
`lake build` running: 0 files, because all 402 unlinked entries are in Lake's outputs map.

**Open items.**
- The map branch blocks everything while one build runs. Follow-up: narrow it to the writer's package and input hashes.
- Run the rule in CI before the `lake-ARM64` cache save.
- Owner relations for scratchpad dirs (54 GB) and ended worktrees. Rules are in the note.
- The user's soft-allow rule for the old `--list | xargs rm` pipe can move to `fw lake-gc --delete`. Only the user
  edits settings.

**TS stand-ins (no Lean golden).**
- String-leaf extraction from `.trace` `outputs` and the outputs map `data`.
- `ps`/`lsof` parsing and the `git worktree list` plus `lakefile.*` project discovery.
- `deletePaths` (an unlink loop over the Lean list).

**Read first.** `research/notes/2026/10-20-cache-relations.md`, then `docs/team/tools/lake-gc.md`, then
`apps/runner/src/lake-gc.ts` (`gatherAll`, `lakeGcCli`).
