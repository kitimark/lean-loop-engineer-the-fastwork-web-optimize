# fw lake-gc: which Lake cache files no checkout uses

`pnpm -s fw lake-gc` (or `node scripts/lake-gc.mjs`, same flags) reports on Lake's artifact cache and lists the
files that are safe to delete. It never deletes: it prints the command, and the user runs or approves it. Spec and
proofs: `lean/Fw/Ops/LakeGc.lean` (fwcore op `ops.lakeGc`). Glue: `apps/runner/src/lake-gc.ts`. Golden vectors:
`packages/contracts/golden/ops/lakegc.jsonl` (`lean/scripts/LakeGcGolden.lean`, checked by `lean/scripts/check.sh`),
replayed through the built fwcore by `node --test scripts/lake-gc.test.mjs`.

## Use

| Command | Prints | Exit |
|---|---|---|
| `fw lake-gc` | cache entries and GB, budget, listed files and GB, the delete command | 0 |
| `fw lake-gc --list` | the listed paths, one per line | 0 |
| `fw lake-gc --json` | the Lean reply | 0 |
| `fw lake-gc --check` | as above | 1 when the cache is over budget |
| `--age-floor <s>` | list with a different floor (default 7200 s) | |
| `--root <dir>/artifacts` | use this cache instead of `lake env printenv LAKE_CACHE_DIR` + `/artifacts` (run in `lean/`) | |

To delete (user): `pnpm -s fw lake-gc --list | xargs rm -f --`. The names are allowlisted (letters, digits, `.`,
`_`, `-`), so `xargs` cannot split or quote them wrongly.

## What is listed (Lean)

A name is listed when every directory entry with that name is a regular file (lstat, so symlinks are kept), has an
allowlisted name, a hard-link count below 2 (no checkout's `.lake/build` links it), and was modified at least the
floor before now. Paths are printed only under a root that is absolute, normalized and ends in `/artifacts`.
Theorems: `never_lists_linked`, `never_lists_young`, `inside_root_only`, `list_monotone_in_age`, `list_complete`,
`alert_iff`.

The alert is `cacheBytes > budget` (bytes of all entries; `budgetBytes` = 20 GB, rationale in its docstring).
`fw watch` does not raise it yet (followup `sys.lakeCache` in the work graph); use `fw lake-gc --check`.

## Why deleting a listed file is safe

- A checkout holds its build products as hard links. Removing the cache's name for a file leaves the data of every
  other link intact, so a file that a build links after the listing is still not lost.
- Lake treats a missing artifact as a cache miss and rebuilds or re-downloads it (`Lake/Build/Common.lean:521-535`,
  toolchain v4.35.0, CONFIRMED). Accepted limit: such a rebuild costs build time.
- The 2-hour floor keeps files that a running build just wrote (a full rebuild of every executable took 82-97 s).

`fwcore` is stripped in each checkout by `scripts/fwcore-build.sh`, which writes a new file, so the unstripped cache
entry ends with link count 1 and is listed after the floor. Lake still treats the stripped binary as up to date.
