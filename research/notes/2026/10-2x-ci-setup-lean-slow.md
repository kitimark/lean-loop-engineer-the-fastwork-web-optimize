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

Step durations come from the job step start/end times (`gh run view --json jobs`). A slower download means a longer step. The elan install (about 1 s) and the cache lookup (about 1 s) are
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

## Follow-up 2026-10-23 (task ci-lake-cache-fresh): prune, main entry age, quota

All numbers: MEASURED from the cited run ids, jobs and steps (`gh run view --json jobs`, `gh run view --job <id> --log`, `gh cache list --json`).
Two CI pushes on `ci/ci-lake-cache-fresh`. Module counts below are `Built <module>` lines without a `:` suffix in step `fwcore build` (not the earlier "78" figure).

### 1. Prune step: the naive prune breaks the cache (negative result)

Run 39984856000, job 120521447078, step "prune the Lake cache" (restored the 1538 MB main entry; exact key hit, so no save):

| point | total bytes (du) | files with 1 link | files with 2+ links |
|---|---|---|---|
| before prune | 6 837 639 341 | 4014 files, 5 471 189 171 B | 1698 files, 1 366 450 170 B |
| after `find -type f -links 1 -delete` | 1 366 450 170 | 0 | 1698 |

The 1538 MB compressed blob is 6.84 GB unpacked; 80% of it is not hard-linked into the build. Run 39985377389, job 120523206940 (new key
suffix so a save happens) repeated the same prune, deleted `.lake/build`, and ran `lake build` against the pruned cache: 837 built lines,
423 s (step TEMP rebuild, 16:18:29 to 16:25:32), versus 1 s for `lake build` on the unpruned cache in the same job (16:17:33 to 16:17:34).
So after the prune the cache no longer serves a build. Cause INFERRED: Lake keeps input-to-output mappings in `outputs/<scope>/<hash>.json`
and content in `artifacts/` (lean4@eb6cafb src/lake/Lake/Config/Cache.lean:398-431); the mapping files are not linked into `.lake/build`, so
`-links 1` deletes them. That run saved a 39 MB entry (id 9410841746, `gh cache list`), a cache that cannot serve a build.
Decision: neither the prune nor the temporary key change is in the branch (both reverted); the 2-run limit is spent.
Proposed, UNPROVEN, needs one more lean.yml run: prune only `artifacts/`: `find "$LAKE_CACHE_DIR/artifacts" -type f -links 1 -delete`,
keeping `outputs/`. Whether Lake treats an `outputs` entry whose artifact is gone as a miss (rebuild that module) or as an error is not read yet.

### 2. fwcore build time vs main entry age (land legs)

Main lake entries: 9404522111 created 14:18:09Z (1479 MB), 9409923189 created 16:06:42Z (1538 MB, from main run 39983425565 at 16:02, commit 3041b6a71).
Main run 39984683144 (16:11, commit 19dd16ed3) saved no entry: same lean sources, exact key hit (the key hashes the Lean sources only).

| land run (leg job, fwcore build step) | leg start | restored entry (Cache Size) | age at start | modules built | summed module time | step time, 5 legs |
|---|---|---|---|---|---|---|
| 39979064402 (120501412578) | 15:32:26Z | 9404522111 (1479166945 B) | 74 min | 57 | 169 s | 74 to 81 s |
| 39980374766 (120505928227) | 15:41:29Z | 9404522111 | 83 min | 75 | 230 s | 85 to 95 s |
| 39982378759 (120512852843) | 15:55:44Z | 9404522111 | 97 min | 76 | 226 s | 86 to 100 s |
| 39986375659 (120526664388) | 16:24:04Z | 9409923189 (1537687531 B) | 17 min | 7 | 8 s | 7 to 9 s |

Answer: yes, a main push per land suffices when it lands before the next land leg starts: the one leg after a fresh main entry built 7
modules in 7 to 9 s instead of 57 to 76 modules in 74 to 100 s. It does not remove the lag: main's lean run takes about 4.5 min
(16:02:32 push, entry created 16:06:42), and the three legs at 15:32 to 15:55 started before it, on the 14:18 entry. Also, a main push that
changes no Lean source saves nothing (run 39984683144), so the entry age that matters is the age of the last Lean-source change on main. Saving a
cache from `ci/land-*` under a key main can restore is not needed: with 4 samples (one fresh), the lag, not the missing push, remains.

### 3. Cache quota and eviction proposal

`gh cache list` at 16:29Z: 21 entries, 11.89 GB (over the 10 GB limit; GitHub evicts later). By ref and use (`lastAccessedAt` equal to `createdAt` means never restored):

| kind | ref | restored? | entries | size |
|---|---|---|---|---|
| lake | ci/* | never | 6 | 7.80 GB |
| gate-* (apt, playwright, hs-zip) | ci/land-* | never | 12 | 1.07 GB |
| lake | main | yes (last access 16:24:11Z) | 2 | 3.02 GB |

Rule proposed (a cache delete needs the user's OK; none was made): (a) delete every `lake-*` entry on a `ci/*` ref once its commit
is on main or the branch is older than 1 h, since no other ref can restore it (scope, INFERRED from docs; matches the table); (b) keep the newest 2
`lake-*` entries on main (the older one, 9404522111, is superseded: restore-keys pick the newest); (c) delete `gate-*` entries of a `ci/land-*` branch after its land. Effect on the 16:29Z list: 8.87 GB freed, leaving about 3 GB.
Command (to run by the user or with OK): `gh cache delete <id>` per entry from `gh cache list --json id,ref,key,createdAt,lastAccessedAt`.
