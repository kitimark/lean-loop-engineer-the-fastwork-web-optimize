# ci-setup-lean-slow: why "Run ./.github/actions/setup-lean" takes 36-48 s on some land legs and 68-88 s on others

Date 2026-10-23. Status of every number: MEASURED from the step logs cited (`gh run view <run> --job <job> --log`, step
"Run ./.github/actions/setup-lean"). No CI push was made for this note (no setup-lean change is proposed that a run could prove; see Outcome).

## Cause (MEASURED)

The 1354 MB Lake cache blob is the same on every leg (same restore key hit, `Cache Size: ~1354 MB (1419617412 B)`).
The step time follows the download rate of that blob, not the cache key and not module building.

| run / job | setup-lean step | cache download | rate | extract | toolchain install |
|---|---|---|---|---|---|
| 39966639416 / land (suites-b) 120458262505 | 41 s | 14:05:46.7 to 14:05:55.3 = 8.6 s | 158.6 MB/s | 17.0 s | 13.7 s |
| 39955108083 / land (chromium) 120419043871 | 51 s | 12:41:10 to 12:41:28 = 18 s | 74.4 MB/s | 17.0 s | not read |
| 39955108083 / land (playwright-webkit) 120419043818 | 72 s | 12:41:11 to 12:41:46.8 = 36 s | 37.8 MB/s | 18.6 s | not read |
| 39966639416 / land (playwright-webkit) 120458262847 | 76 s | 14:05:49 to 14:06:31.8 = 43 s | 32.1 MB/s | 14.3 s | not read |
| 39965489939 / land (chromium) 120454308192 | 88 s | 13:57:47.6 to 13:58:39.9 = 52 s | 25.4 MB/s | 14.4 s | 17.2 s (download 10.4 s) |

Step durations come from the job step start/end times (`gh run view --json jobs`). In all five rows, a slower download means a longer step. The elan install (about 1 s) and the cache lookup (about 1 s) are
the same everywhere. The spread (25 to 159 MB/s) is cache download throughput (MEASURED); that it comes from the runner-to-storage network or backend load, not from anything setup-lean sets, is INFERRED.

## Not the cause

- Cache key / hit: all legs print `Cache hit for restore-key: lake-ARM64-ef17aadf...-00301c2b...` (a restore-key
  hit, never an exact hit, because a land leg's source hash is new).
- Module growth: the blob did not change between the fast and the slow legs (1419617412 B in 39955108083, 39965489939 and 39966639416).
- Building changed modules does not happen inside setup-lean at all. It happens in the next step, `fwcore build`
  (`lake build fwcore`): 78 modules built, about 260 s of summed module times, step 90 s (39965489939 chromium) and 81 modules,
  257 s, step 92 s (39966639416 suites-b). That cost is the same on fast and slow setup legs.
- Blob growth across runs: fast land 39946751704 restored 1360013538 B (hit to Cache Size 6-8 s, step 36-46 s); fast land 39979064402 restored 1479166945 B, larger than the slow runs, in 6.5-10 s (step 39-45 s). A bigger blob downloaded fast, so the 68-88 s runs are not explained by blob growth.

## Second finding: land legs restore a stale main entry (MEASURED, `gh cache list --json`; the rebuild-by-age link is INFERRED)

GitHub scopes a cache to the ref that saved it. A land leg runs on `ci/land-*`, so it can restore only `main` entries (and its own
branch). The `lean` job saves on every push (lean.yml `branches: ['ci/**', main]`), so most saves land on `ci/*` refs where no other
branch sees them. The `main` entries seen: id 9397445268 created 11:44:49Z (last used 14:14:31Z), id 9404522111 created 14:18:09Z. Runs
39955108083 (12:41), 39965489939 (13:57) and 39966639416 (14:05) all restored the 11:44 entry, up to 2.5 h older than main, so every leg
rebuilt 78-81 modules; that the count comes from the entry's age is INFERRED (the fast-setup run 39946751704 at 11:32 also spent 90-100 s in fwcore build, and entry 9397445268 is gone from gh cache list). The build step, not setup-lean, grows with that age.

## Third finding: cache storage is at the quota (MEASURED)

`gh cache list` at 2026-10-23 15:4x: 13 entries, 9.48 GB total, 6 `lake-ARM64-*` entries = 8.97 GB. Entry sizes grow with each save
(1419 MB at 11:44, 1479 MB at 14:18 on main, 1528 MB on ci/* saves) because the writer restores the previous entry through the
restore-key and saves old plus new artifacts. GitHub's limit is 10 GB per repository with least-recently-used eviction (docs: actions/cache
"Usage limits and eviction policy"; INFERRED to apply here), so the next saves can evict the main entry the land legs need.

## Outcome

No cache fix inside `.github/actions/setup-lean` applies: key and restore-key are correct, and the 41 s to 88 s spread is download
throughput for a fixed 1354 MB blob. The lever is the blob size, which needs a step after the build in the writer job.

## Follow-ups (all outside this task's writes; listed in the report `open`)

1. Prune the writer's cache before it is saved: add a step to lean.yml job `lean` after `lake build`, before the job ends, that deletes
   `.lake-cache` files not hard-linked into the build (`find "$LAKE_CACHE_DIR" -type f -links 1 -delete`). INFERRED to work because the
   setup-lean comment says Lake hard-links cached artifacts back; one lean.yml run must first print link counts and the size after the prune
   to prove it. Expected: the blob shrinks toward one build's artifacts, so download time shrinks in proportion (a 25 MB/s leg: 52 s per 1354 MB).
2. Save a `main` entry per land (the lean job on `main` pushes only), so the restored entry is not hours old and `fwcore build` rebuilds
   less. This touches workflow trigger inputs (lean.yml / land.yml); lead decision.
3. Lean verdict rule for `timing.slow` on setup-lean: compare the step with cache bytes divided by the logged rate before calling it slow.
