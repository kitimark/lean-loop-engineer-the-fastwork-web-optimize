# fw lake-gc: which Lake cache files no checkout and no live build uses

`pnpm -s fw lake-gc` (or `node scripts/lake-gc.mjs`, same flags) reports on Lake's artifact cache and lists the
files that are safe to delete. `--delete` removes exactly that list. Only the user runs it or approves it.
- Spec and proofs: `lean/Fw/Ops/LakeGc.lean` (fwcore op `ops.lakeGc`).
- Glue: `apps/runner/src/lake-gc.ts`.
- Golden vectors: `packages/contracts/golden/ops/lakegc.jsonl` (`lean/scripts/LakeGcGolden.lean`, checked by
  `lean/scripts/check.sh`), replayed through the built fwcore by `node --test scripts/lake-gc.test.mjs`.
- Research: `research/notes/2026/10-20-cache-relations.md`.

## Use

| Command | Prints | Exit |
|---|---|---|
| `fw lake-gc` | cache size, basis, live writers, listed files and GB next to the age rule's | 0 |
| `fw lake-gc --list` | the listed paths, one per line | 0 |
| `fw lake-gc --json` | the Lean reply | 0 |
| `fw lake-gc --delete` | deletes the listed paths; prints deleted, already gone, failed | 1 if an unlink failed |
| `fw lake-gc --check` | as above | 1 when the cache is over budget |
| `--age-floor <s>` | floor of the fallback (default 7200 s) | |
| `--root <dir>/artifacts` | use this cache instead of `lake env printenv LAKE_CACHE_DIR` + `/artifacts` (run in `lean/`) | |

`--delete` gathers the facts and asks Lean again in the same run, then unlinks only the paths in the reply. No
shell pipe is involved, so banner lines cannot reach `rm`. The auto-mode classifier treats the delete as
irreversible: the user runs it or approves it.

## What is listed (Lean)

A name is listed when every directory entry with that name meets all of these:
- it is a regular file (lstat, so symlinks are kept) with an allowlisted name;
- its link count is below 2 (no `.lake/build` hard-links it);
- no checkout's `.trace` `outputs` names it or its stem;
- no live Lake writer may own it. A writer is any `lake` process except `lake serve` and `lake env`. It may own an
  entry when it started at or before the entry's ctime, or when Lake's outputs map names the entry (the map is
  read only when a writer is live).

When a fact is missing, the age floor decides instead, and the reply names the reason as `fallback`:
- `noCheckoutList`: `git worktree list` failed.
- `noProcessTable`: `ps` failed.
- `noOutputsMap`: a writer is live and the map was not read.

Paths are printed only under a root that is absolute, normalized and ends in `/artifacts`.

Theorems:
- One per OR-branch of the rule: `never_lists_linked`, `never_lists_named_by_trace`, `never_lists_named_by_stem`,
  `never_lists_touched_by_writer`, `never_lists_linkable_by_writer`, `fallback_never_lists_young`.
- Fallbacks: `fallback_noCheckoutList`, `fallback_noProcessTable`, `fallback_noOutputsMap`, `identity_basis`.
- Against the old rule: `superset_when_idle` (with no writer, every unreferenced entry the age rule lists is listed).
- Writers: `writer_runs_lake`, `read_only_not_writer`.
- Other: `inside_root_only`, `list_monotone_in_age`, `list_complete`, `alert_iff`, and `fast_eq` (the HashSet
  index equals the list spec).

The alert is `cacheBytes > budget` (bytes of all entries; `budgetBytes` = 20 GB, rationale in its docstring).
`fw watch` does not raise it yet (followup `sys.lakeCache` in the work graph); use `fw lake-gc --check`.

## Why deleting a listed file is safe

- A checkout holds its build products as hard links. Removing the cache's name for a file leaves the data of every
  other link intact.
- Lake treats a missing artifact as a cache miss and rebuilds it (`Lake/Build/Common.lean:524-534,557-558`,
  toolchain v4.35.0, CONFIRMED). Accepted limit: such a rebuild costs build time.
- A live build may resolve an entry (`Common.lean:585`) and then link it (`:652`). Unlinking between those two
  steps fails that build job, which is why the writer rule exists.
- Accepted limits:
  - A build that starts during the seconds of gathering is not seen.
  - Clones outside `git worktree list` do not count as references; deleting their text artifacts costs a recache.

`fwcore` is stripped in each checkout by `scripts/fwcore-build.sh`, which writes a new file. The unstripped cache
entry ends with link count 1, and a checkout's trace still names it, so it is kept.
