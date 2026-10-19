---
id: 2026-10-20-cache-relations
kind: note
title: "Cache relations: which checkout and which process holds each cache, and when it may go"
status: draft
created: 2026-10-20
topics: [lake, cache, disk, lake-gc, worktrees, ci]
---

**Answer.** Yes for the Lake artifact cache. An entry can be linked to the checkouts that name it (their `.trace`
`outputs`) and to the live Lake processes that may still write or link it (process start vs the entry's ctime, and
Lake's outputs map). `fw lake-gc` now decides by these two relations and needs no 2-hour wait. It lists 265 files
(2.99 GB) when no Lake build runs, against 49 files (0.57 GB) for the age rule (MEASURED, below). While any
`lake build` runs it lists nothing: every unlinked entry is named in Lake's outputs map, so a running build may
restore any of them. The age floor remains only as a named fallback (`Fw.Ops.LakeGc.Fallback`).

## How Lake v4.35.0 writes and links the cache (CONFIRMED, lean4@eb6cafb, src/lake/)

- The cache directory is `<toolchain>/lake/cache`, shared by every project on the toolchain. `artifacts/` is flat:
  `<hash>.<ext>`, or a bare hash for an executable (Lake/Config/Artifact.lean:16,43-47).
- `outputs/<scope>/<input hash>.json` maps a build input to its artifact names in field `data`
  (Lake/Config/Cache.lean:426-454). Two scopes exist here: `fwcore` and one other project, `tiny`.
- Save (Lake/Build/Common.lean:454-500):
  - A binary artifact is hard-linked from the local file into the cache (:489); if that fails, Lake writes a copy (:493).
  - A text artifact (`.c`, `.ilean`) is written as a separate copy (:472), so its link count is 1.
  - `setAccessRights` runs on the cache file at every save (:473, :494). This updates the entry's ctime even when
    the file already existed.
- Restore (Common.lean:648-669) hard-links cache to local (:652), with a copy as fallback. A link also updates the
  entry's ctime (POSIX `link`). `restoreAllArtifacts = true` in lean/lakefile.toml, so every artifact a build uses is
  linked into `.lake/build`.
- Lookup (Common.lean:516-575):
  - Lake first resolves the names in the checkout's saved trace (`getArtifactsUsingTrace?`), then the outputs map
    (`getArtifactsUsingCache?`).
  - A missing artifact makes the lookup return `none` (:524-534, :557-558), and the module is rebuilt and saved again.
  - Deleting an entry therefore costs rebuild time and never breaks correctness. The one exception is a race:
    `resolveArtifact` checks the file (:585), and if the entry is unlinked before `restoreArtifact` links it (:652),
    the hard link and then the copy both fail, and that build job errors.
- Processes:
  - `lake serve` (Lake/CLI/Main.lean:1403; Serve.lean:90-104) starts `lean --server`, which runs
    `lake setup-file` (Main.lean:1391) per file. `setup-file` builds, so it writes.
  - `lake env` (Main.lean:1404) loads the workspace and runs a command without building.
  - Writers are therefore: every `lake` process except the exact forms `lake serve` and `lake env`.

## The two relations (identity, not age)

- **referenced(e)**: some checkout's `<project>/.lake/**/*.trace` names e or e's stem in its `outputs` field. The
  checkout list comes from `git worktree list` (MEASURED: 19 here, including the two land worktrees and one scratchpad
  worktree), and the project directories from tracked `lakefile.*` files.
- **liveOwned(e)**: some live writer p has `p.start ≤ e.ctime` (it may have saved or linked e), or e is in the outputs
  map (p may restore e). The process table comes from `ps` and `lsof` (cwd, reported only).

Lean (lean/Fw/Ops/LakeGc.lean) lists e iff e is a regular file with an allowlisted name and link count < 2, is not
referenced, and is not live-owned. If a fact is missing, it falls back to the age floor and names the reason:
`noCheckoutList`, `noProcessTable`, or `noOutputsMap` (a writer is live and the map was not read).

## Dry run, 2026-10-20 (MEASURED, no deletion)

| case | listed | GB |
|---|---|---|
| age rule alone (2 h floor) | 49 | 0.57 |
| identity, no writer running | 265 | 2.99 |
| identity, writer running (map read) | 0 | 0 |
| identity, writer running, ctime branch only | 265 | 2.99 |

- Cache: 2727 entries, 7.81 GB; 3.59 GB of that is hard-linked into some `.lake` (link count ≥ 2).
- Unlinked: 402 entries. 137 of them are referenced by a checkout and kept; 265 are listed.
- Of the 49 entries the age rule lists, 24 are referenced; the new rule keeps those (theorem `superset_when_idle`
  covers the other 25).
- Listed by kind: olean 87, ilean 75, c 44, o 34, exe 25.
- All 402 unlinked entries are in the outputs map (9810 names), so the map branch blocks everything while a
  build runs.
- Time per run: about 16 s (file facts 0.1 s, checkout traces 2.6 s, `ps`/`lsof` 1.5 s, outputs map 3.9 s,
  read only when a writer is live).

## Inventory (MEASURED with `du`, 2026-10-20; APFS clones and hard links are counted once per tree, so sums overstate)

| cache | size | owner | relation by identity | safe-delete rule |
|---|---|---|---|---|
| Lake artifact cache | 7.81 GB | every Lake build on the toolchain | referenced + liveOwned (above) | `fw lake-gc --delete`, user-approved |
| Lake outputs map | 78 MB, 20000 files | Lake save | names artifacts; an entry with a missing artifact is a miss | follow-up: drop map files whose artifacts are all gone |
| worktree `lean/.lake` (13) | 0.48-1.0 GB each | the agent of that worktree | `git worktree list`; 2 are `locked claude agent … (pid, start)` | with the worktree, when its agent has ended and its branch is landed (follow-up) |
| `.claude/land-wt` (2) | 2.3 GB | `fw land` | git worktrees, detached | kept; reused by the land queue |
| worktree `node_modules` (12) | ~0.32 GB each | pnpm install | hard links into the pnpm store | with the worktree |
| pnpm store | 7.2 GB | pnpm | link count of each store file | `pnpm store prune` (follow-up, INFERRED safe when no install runs) |
| Playwright browsers | 1.2 GB | Playwright install | browser revision pinned by the installed Playwright | revisions no installed Playwright pins (2 webkit, 2 ffmpeg present) |
| session scratchpad | 54 GB, 2715 entries | agents (`scratchpad/<name>/`) | none recorded; `rev/<run id>` holds downloaded CI artifacts | follow-up: owner file per dir; CI downloads are re-fetchable while GitHub keeps them |
| `.fw-console` | 214 MB | console | append logs and spool | rotation follow-up |
| `apps/site/dist` (aot 23 MB) | 24 MB | site build | rebuilt from sources | any time no build runs |
| `.cache/upstream` | 447 MB | refs-fetch | pinned in refs/upstream/sources.lock.yaml | entries no pin names |
| research kickoff `.lake` (2) | 315 MB | kickoff sketches | same toolchain; not git worktrees | with the sketch |
| GitHub Actions caches | 16 entries, 12.89 GB | CI | key `lake-<arch>-<toolchain+manifest>-<sources>` per ref (.github/actions/setup-lean/action.yml:57) | GitHub evicts the oldest entries above 10 GB per repo and after 7 days unused (GitHub docs); 10 `lake-ARM64` entries of 1.2-1.3 GB (compressed) on 8 refs |

## Accepted limits

- A build that starts during the gather window (seconds) is not seen.
- Checkouts outside `git worktree list` (scratch clones, kickoff sketches, other projects) do not count as
  references. Their binaries are protected by link count; their text artifacts are not. Deleting those costs a
  recache, not correctness.
- Traces and map files that do not parse (mid-write) are skipped; the ctime branch covers entries being written.

## Follow-ups (not code in this task)

- Narrow the map branch to the writer's own package and input hashes, so one running build does not block the
  whole list.
- Run the identity rule in CI before the cache save step, so `lake-ARM64` entries stop growing.
- Add owner relations for scratchpad directories and ended worktrees.
