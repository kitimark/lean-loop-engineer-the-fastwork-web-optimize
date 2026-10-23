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

Step durations come from the job step start/end times (`gh run view --json jobs`). The elan install (about 1 s) and the cache lookup (about 1 s) are
the same everywhere. The spread (25 to 159 MB/s) is cache download throughput (MEASURED); that it comes from the runner-to-storage network or backend load, not from anything setup-lean sets, is INFERRED.

## Not the cause

- Cache key / hit: all legs print `Cache hit for restore-key: lake-ARM64-ef17aadf...-00301c2b...` (a restore-key
  hit, never an exact hit, because a land leg's source hash is new).
- Module growth: the blob did not change between the fast and the slow legs (1419617412 B in 39955108083, 39965489939 and 39966639416).
- Building changed modules does not happen inside setup-lean at all. It happens in the next step, `fwcore build`
  (`lake build fwcore`): 78 modules built, about 260 s of summed module times, step 90 s (39965489939 chromium) and 81 modules,
  257 s, step 92 s (39966639416 suites-b).
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
`-links 1` deletes them. That run saved a 39 MB entry (id 9410841746) from a cache pruned twice (1 535 056 668 B after the rebuild, 168 501 312 B after a second prune, same step). The compressed blob after a single prune was not measured.
Decision: neither the prune nor the temporary key change is in the branch (both reverted); the 2-run limit is spent.
Proposed, UNPROVEN, needs one more lean.yml run: prune only `artifacts/`: `find "$LAKE_CACHE_DIR/artifacts" -type f -links 1 -delete`,
keeping `outputs/`. Whether Lake treats an `outputs` entry whose artifact is gone as a miss (rebuild that module) or as an error is not read yet.

### 2. fwcore build time vs main entry age (land legs)

Main lake entries: 9404522111 created 14:18:09Z (1479 MB), 9409923189 created 16:06:42Z (1538 MB, from main run 39983425565 at 16:02, commit 3041b6a71).
Main run 39984683144 (16:11, commit 19dd16ed3) saved no entry: same lean sources, exact key hit (the key hashes the Lean sources only).

| land run (leg job, fwcore build step) | leg start | restored entry (Cache Size) | age at start | Lean files changed since entry commit | modules built | summed module time | step time, 5 legs |
|---|---|---|---|---|---|---|---|
| 39979064402 (120501412578) | 15:32:26Z | 9404522111 (1479166945 B) | 74 min | 3 | 57 | 169 s | 74 to 81 s |
| 39980374766 (120505928227) | 15:41:29Z | 9404522111 | 83 min | 5 | 75 | 230 s | 85 to 95 s |
| 39982378759 (120512852843) | 15:55:44Z | 9404522111 | 97 min | 6 | 76 | 226 s | 86 to 100 s |
| 39986375659 (120526664388) | 16:24:04Z | 9409923189 (1537687531 B) | 17 min | 1 | 7 | 8 s | 7 to 9 s |

Answer: yes, a main push per land suffices when it lands before the next land leg starts: the one leg after a fresh main entry built 7
modules in 7 to 9 s instead of 57 to 76 modules in 74 to 100 s. It does not remove the lag: main's lean run takes about 4 min
(16:02:32 push, entry created 16:06:42), and the three legs at 15:32 to 15:55 started before it, on the 14:18 entry. Also, a main push that
changes no Lean source saves nothing (run 39984683144), so the entry age that matters is the age of the last Lean-source change on main. Saving a
cache from `ci/land-*` under a key main can restore is not needed: with 4 samples (one fresh), the lag, not the missing push, remains.
Modules built follow the Lean files changed since the entry commit (entry commits 56da21864 for 9404522111 and 3041b6a71 for 9409923189; `git diff --name-only` on the key's hashFiles set); age is only a proxy for that. The single fresh sample changed one file.

### 3. Cache quota and eviction proposal

`gh cache list` at 16:29Z: 21 entries, 11.89 GB (over the 10 GB limit; GitHub evicts later). By ref and use (`lastAccessedAt` equal to `createdAt` means never restored):

| kind | ref | restored? | entries | size |
|---|---|---|---|---|
| lake | ci/* | never | 6 | 7.80 GB |
| gate-* (apt, playwright, hs-zip) | ci/land-* | never | 12 | 1.07 GB |
| lake | main | yes (last access 16:24:11Z) | 2 | 3.02 GB |

Rule proposed (a cache delete needs the user's OK; none was made): (a) delete every `lake-*` entry on a `ci/*` ref once its commit
is on main or the branch is older than 1 h, since no other ref can restore it (GitHub Actions dependency-caching reference, "Restrictions for accessing a cache": a ref restores caches from its own ref and from the default branch only; evidence: the lake entries on ci/* refs 9410862728, 9410705393 and 9409980662 have lastAccessedAt equal to createdAt); (b) keep the newest 2
`lake-*` entries on main; (c) delete `gate-*` entries of a `ci/land-*` branch after its land. Effect on the 16:29Z list: 8.87 GB freed, leaving about 3 GB.
Command (to run by the user or with OK): `gh cache delete <id>` per entry from `gh cache list --json id,ref,key,createdAt,lastAccessedAt`.

## Follow-up 2026-10-24 (task ci-lake-prune-artifacts)

Status: item 1 CONFIRMED from Lake source and MEASURED in one run; item 2 MEASURED from land legs; item 3 is a rule derived from them (INFERRED where marked).

### 1. Missing artifact under an existing outputs mapping is a miss, not an error (CONFIRMED, lean4@eb6cafb)

- `getArtifactsUsingCache?` (src/lake/Lake/Build/Common.lean:521-534) reads `outputs/<scope>/<hash>.json` and resolves each artifact. Any error is caught
  (`catch e` at :526), logged only at verbose level (:533) and returns `none`: the module is rebuilt.
- The error itself is `resolveArtifact`, :579-614: `getMTime path` fails with `noFileOrDirectory` (:588), no cache service is configured, so it ends in
  `error s!"artifact not found in cache"` (:612). The trace route (`getArtifactsUsingTrace?`, :545-560) catches the same error (`dropLogFrom e`, :559).
- A module needs all its artifacts: `ModuleOutputDescrs.resolve` resolves olean, ilean, c and the optional ones (src/lake/Lake/Build/Module.lean:731-751), so one missing file is a miss for that module.
- The module that is used in a build has every artifact hard-linked into `.lake/build`: `lakefile.toml:15` sets `restoreAllArtifacts = true`, and
  `Module.restoreAllArtifacts` (Module.lean:821-831) links olean, ilean, ir, c, bc, ltar. So an artifact with one link belongs to no module of this build (INFERRED: this holds while the cache and `.lake/build` share a file system, which `setup-lean` ensures).
- Why the naive prune failed (run 39985377389): it also deleted `outputs/` (mapping files have one link), and without a mapping Lake finds nothing to look up.

### Run 40000273174 (lean.yml on ci/ci-lake-prune-artifacts, job 120574411361, commit 5dae271a7): artifacts-only prune (MEASURED)

| quantity | value | source |
|---|---|---|
| restored entry (restore-key hit) | 1 806 502 375 B (main entry 9415355768) | setup-lean step, "Cache Size" |
| cache dir before prune | 8 036 395 020 B | prune step, `total bytes` |
| artifacts links=1 (deleted) | 1453 files, 6 664 800 449 B | prune step |
| artifacts links>=2 (kept) | 1698 files, 1 371 198 757 B | prune step |
| outputs (kept) | 2779 files, 395 814 B | prune step |
| cache dir after prune | 1 371 594 571 B | prune step, `total bytes` |
| `rm -rf lean/.lake/build; lake build` | 847 jobs, 1 s, 1 built line (`fwcore:exe`, 663 ms) | TEMP rebuild step |
| saved blob (compressed) | 349 958 215 B (entry 9415450987), 80.6% below the restored 1 806 502 375 B | post step "Sent 349958215", `gh cache list` |

Against the naive prune (837 lines rebuilt, 423 s): 846 of 847 jobs were served from the pruned cache. The cache dir grew to 1 530 206 571 B during that rebuild (+158 MB; cause not read, probably the fwcore executable and relinked outputs; the blob size above was taken after it).
Limit: the rebuild ran on the same runner after the prune, so it proves the pruned cache serves a build, not that the saved blob unpacks to the same (hard links are kept by tar; INFERRED). The first cross-run proof is the next main `lean` run that restores a pruned entry: a restore with a rebuild of hundreds of modules would show here. The TEMP rebuild step and TEMP key suffix are reverted; the prune step stays in `lean.yml` (job `lean`, the one writer).

### 2. Land legs after per-land main pushes (MEASURED; main pushes by the lead from 2026-10-23 16:20Z)

Entry = the newest main lean entry created before the leg's restore (main lean runs that saved: 39987250348 b10251ccb 16:32:38Z, 39990786493 069aa37ce 16:58:07Z, 39992907653 11d8948c1 17:14:01Z, 39995021894 414e3fef7 17:28:49Z, 39997512873 840a81bdf 17:47:56Z; 39988665339 and 39984683144 saved nothing, 20 s). "Lean files changed" = `git diff --name-only <entry commit> <land branch head>` over the key's hashFiles set (includes the land's own changes). Legs = jobs that ran the `fwcore build` step; step time and Built lines from job check-sh.

| land run (check-sh job) | leg restore | entry commit | Lean files changed | Built lines | fwcore build step (check-sh) | legs ran, sum of steps |
|---|---|---|---|---|---|---|
| 39986375659 (120526664354) | 16:24:06Z | 3041b6a71 | 1 | 9 | 7 s | 5, 38 s |
| 39989742276 (120538239743) | 16:48:18Z | b10251ccb | 2 | 15 | 12 s | 1, 12 s |
| 39991986432 (120545915646) | 17:04:26Z | 069aa37ce | 1 | 11 | 10 s | 5, 48 s |
| 39994191829 (120553456004) | 17:20:29Z | 11d8948c1 | 2 | 16 | 11 s | 5, 55 s |
| 39995255573 (120557111502) | 17:28:13Z | 11d8948c1 (414e3fef7 finished 36 s later) | 4 | 56 | 58 s | 4, 236 s |
| 39996646025 (120561955708) | 17:38:27Z | 414e3fef7 | 3 | 57 | 68 s | 2, 129 s |
| 39997746052 (120565741053) | 17:46:25Z | 414e3fef7 (840a81bdf finished 91 s later) | 5 | 76 | 72 s | 2, 143 s |

Reading: Built lines follow the Lean files changed (1-2 files: 9-16 Built lines, 7-12 s; 3-5 files: 56-76 lines, 58-72 s), the same as the 2026-10-23 table. Two of seven legs (39995255573, 39997746052) restored an entry that was one push behind because a main lean run was in flight; the other five restored the entry of the previous push. For those two, the files the fresh entry would add: 2 (Polish.lean, Wire/Plan.lean) and 3 (Ci/Overflow.lean, Gate/PathPix.lean, Parts/FootprintData.lean); the rest of the changed files are the land's own and no main push can supply them (39996646025 with the same 3 files as its own change built 57 lines, 68 s on a fresh entry).
Answer to the 2026-10-23 open point: with the lead's push after every land a `ci/land-*` cache save is still not needed; the leg is slow only when the land itself changes 3 or more Lean files.

### 3. Rule: gate a land on main's lean run? (MEASURED inputs, rule INFERRED)

Main lean run durations (createdAt to updatedAt): 2:50, 2:45, 3:27, 2:45, 3:42, 4:50, 3:15 (runs 39987250348, 39990786493, 39992907653, 39995021894, 39997512873, 39998749994, 39999887346). Gap from a main push to the next land run creation: 1.7 min (39995021894 to 39995255573), 1.6 min (39997512873 to 39997746052), 6 to 20 min otherwise.

| land | wait for the in-flight main run | leg restore to main save | wall saved per leg (upper bound) | leg time saved |
|---|---|---|---|---|
| 39995255573 | 17:27:47Z (land created) to 17:28:49Z = 62 s | 36 s | 58 s step minus about 12 s for the own 2 files (39989742276, 39994191829 changed exactly 2): 46 s | at most 4 legs x 46 s = 184 s |
| 39997746052 | 17:45:53Z to 17:47:56Z = 123 s | 91 s | 72 s step minus about 12 s for the own 2 files: 60 s | at most 2 legs x 60 s = 120 s |

Rule: do not gate. The legs run in parallel, so the wall time a gate can save is one leg's fwcore build (at most 60 s here), while the wait costs 62 to 123 s when it applies (2 of 7 lands) and 0 otherwise; the leg seconds it saves (at most 304 s over 7 lands) are on free runners. The wall estimate of the own-change cost (12 s for 2 files) is INFERRED from the two lands with that exact count. A gate would pay only if one leg fwcore build exceeded the remaining main run time; the largest step seen is 72 s against 62 to 123 s of wait.

Correction 2026-10-24 (task lake-prune-verify): the first row of the table above gave 12 s as the wall saved; that is the 12 s of the own change, so the saved upper bound is 58 - 12 = 46 s (the rule holds: 46 < 62). `Fw.Ops.LakeCache.gateRows` and `no_gate_pays` now hold both rows with the gaps.

## Follow-up 2026-10-24 (task lake-prune-verify): the pruned main entry, restored

Status: item 1 MEASURED from existing runs (no run dispatched); item 2 decided; the behind-main case has no run (INFERRED only). Rules and measured inputs: `Fw.Ops.LakeCache` (`keeps`, `verdict`, `legs_ok`, `exe_pruned`), golden `packages/contracts/golden/ops/lake-cache.jsonl`.

### 1. First restores of a pruned main entry (MEASURED from job logs)

Main's first pruned save: lean run 40009814844 (7926425d5), blob 299 193 260 B (the entry before it was 1 886 179 142 B, run 40005295967). Later main saves: 312 257 527 B (run 40011143247, c1fdb5684), 306 150 625 B (run 40012913395). Entry = the newest main entry before the leg's restore; files = Lean files of the key's hash set that differ between the entry's commit and the leg's head; setup-lean = that step's seconds.

| run (job) | what | entry restored | files | Built lines of jobs | setup-lean | verdict |
|---|---|---|---|---|---|---|
| 40010696608 (120610140089) | ci/accent-drawin-width-nolayout, first leg | 7926425d5 | 2 | 48 of 849 | 19 s | ok |
| 40010826449 (120610621304) | same branch, next push | 7926425d5 | 2 | 48 of 849 | 24 s | ok |
| 40011143247 (120611676101) | main lean | 7926425d5 | 1 (LandTier) | 51 of 849 | 19 s | ok |
| 40011600530 (5 legs) | land legs | c1fdb5684 | 3 | 43-44 of 826 | 17-20 s | ok |
| 40011600647 (120613247310) | ci lean | c1fdb5684 | 3 | 44 of 849 | 18 s | ok |
| 40012913395 (120617723600) | main lean | c1fdb5684 | 3 | 44 of 849 | 18 s | ok |

Reading: all 10 legs hit the restore-key and none rebuilt hundreds of modules (largest 51 Built lines; the rule `Fw.Ops.LakeCache.revertLines`: 200 or more reverts the prune). The prune step stays. With the unpruned entry (section 2 above) 3 changed files gave 56-76 Built lines; here the same count gave 43-44, so the pruned entry costs no extra rebuild. setup-lean fell to 17-24 s (41-88 s before) because the blob is 299-312 MB, not 1.35-1.8 GB; the restore rate was 87-212 MB/s. The Built modules are the dependents of the changed files plus `:c.o` lines plus a few more modules the diff does not name (6 of 39 for the 3-file legs, e.g. Fw.Ci.Trigger; INFERRED from the import graph at the current tree, not at each head).
Branches behind main: no run in this window restored a pruned entry onto a branch whose Lean files lie behind the entry (the merge base of every branch with the entry's commit was the entry's commit). INFERRED: the old 8 GB entry held artifacts of older versions of each module, so a branch behind main by k Lean files now also rebuilds the dependents of those k files; the first behind branch will show it in this table. No run was dispatched (accepted limit unused).

### 2. The fwcore executable (decision: stay pruned)

The executable never has two links (`scripts/fwcore-build.sh` strips with `-o` and renames, which breaks the hard link), so the prune deletes it and each restoring job relinks it: `Built fwcore:exe` took 630-683 ms in the legs above. The stripped executable is 97 182 976 B (34 117 988 B zipped, artifact `fwcore-linux-arm64` of run 40012913395); keeping it would add about that to a 299-312 MB blob: 0.34 s at 100 MB/s, 1.4 s at the slowest rate seen (25 MB/s). The gain is at most the relink (0.68 s), below the 1 s the Lean rule asks (`exe_pruned`: a relink under `minGainMs` never keeps it), and stripping in place would change what the build record hashes. `scripts/fwcore-build.sh` and `lean.yml` stay unchanged.
