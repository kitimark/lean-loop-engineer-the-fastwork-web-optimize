# dry-land-waves: the one-wave dry land with a Lean dependency rule

Final design round after dry-land-slow (closed as a finding, `11-01-dry-land-slow.md`). The three dry phases run as one
wave; inside the wave, Lean `Fw.Ops.LandDry.deps` decides which check waits for which. Source of every MEASURED line:
`.fw-console/timings.jsonl` and `.fw-console/locks.jsonl` (local only); each line names its row key (commit, startMs) or
row numbers.

## What the rule is

- CONFIRMED (lean/Fw/Ops/LandDry.lean, `kindDep`, `edge`, `deps`): check kinds are install, lakeLint, fwcoreBuild,
  coreUser, other, classified by identity of the command line (`checkKind` in apps/runner/src/land.ts). Every check waits
  for the install; fwcoreBuild waits for lakeLint; coreUser waits for fwcoreBuild and, directly, for lakeLint (the build
  step can be absent while the lake lint runs). Two checks that both build the lake are ordered by index.
- CONFIRMED (Lean, `lake_serial`): any two different lake-building checks are ordered, so no two `lake build` share one
  `lean/.lake`. `core_after_builds`: every coreUser waits for every lakeLint and fwcoreBuild index, so none runs while a
  `lake build` can still relink `lean/.lake/build/bin/fwcore`. Also `install_first`, `kindDep_rank` (no cycle).
- Golden: packages/contracts/golden/ops/land-dry-deps.jsonl (12 kind lists, generated from Lean, guarded by `#guard` in
  Fw.Ops.LandDryGolden); `checkDeps` is checked against every row in apps/runner/test/land-parallel.test.ts. TS stand-in
  for a fwcore op, marked in land.ts.
- Scope: builds in other worktrees are not covered; each has its own `.lake`, and two Lake slots across worktrees are
  intended.

## Slots and locks (corrected citations)

- CONFIRMED (read this round): two Lake slots, not one. `LAKE_SLOT_POOLS='full 4'` (lean/Fw/Sched/LakeSlot.lean:276) holds
  two words, and `_ls_take` (scripts/lake-slot-lib.sh:38-49) loops `for _ls_p in $LAKE_SLOT_POOLS`, one lock file per word.
- CONFIRMED: Lake takes no build lock. Lake/Util/Lock.lean:17-20 at lean4 eb6cafb: "Lake does not currently use a lock file".
  So the slots do not serialize the lake lint and the fwcore build; the rule does.
- The failed run of the earlier branch: commit 09ab4c0, startMs 1793485018826, built 2, exit 1; locks rows 20291-20292
  (both slots taken within 82 ms (locks rows 20291-20292: ts 1793485019749 and 1793485019831)). Not ruled out as a race on one `lean/.lake`; the error text was overwritten by the passing
  rerun. The new rule removes the overlap, so a repeat would be a different cause.

## Measurement

Never-landed scratch branch `dlw-scratch-c` (base 7cd9dd837, five edits: comments in four runner/console-api files and a
`def` in lean/Fw/Obs/Health.lean), `FW_LAND_LAKE_CACHE=off`, `fw land --dry --task dry-land-waves --allow '**'`
(measurement only, the allow is not in the report). The set of checks is the `checks`/`set` dim of every timings row and
is identical in all six runs: reads-scan, lint:ciPaths, lint:axioms, fwcore-build, console-api:compose,
runner:overflow-widths, runner:ledger-notes, workflow-lint. That is the set of 001d247 (reads test, ci-paths, lake lint,
fwcore-build, check-workflows, ledger-merge test, compose test, overflow-widths).

Before = main code (94e020a8f, sequential phases). After = this branch. "cold" = the first run after a fresh edit of
lean/Fw/Obs/Health.lean (built 28). Seconds. Row key = (commit, startMs) of the `dry total lake` row; locks rows are the
two lake-slot acquires of the run (lake lint, then fwcore-build).

| run | key | total | lake lint | fwcore-build | reads | compose | overflow | load | built | locks rows | build starts after lint ends |
|---|---|---|---|---|---|---|---|---|---|---|---|
| before cold | 6e8d03d, 1793491033458 | 78.61 | 54.11 | 1.53 | 9.81 | 7.87 | 11.75 | 5.68 | 28 | 20384, 20385 | yes (+288 ms) |
| before warm 1 | 6e8d03d, 1793491125717 | 26.47 | 2.12 | 0.89 | 9.73 | 7.34 | 12.33 | 4.60 | 0 | 20388, 20389 | yes (+144 ms) |
| before warm 2 | 6e8d03d, 1793491154321 | 30.14 | 5.68 | 0.89 | 9.83 | 7.41 | 12.39 | 6.81 | 0 | 20392, 20393 | yes (+152 ms) |
| after cold | b8bd0ee, 1793491199825 | 65.19 | 51.15 | 0.85 | 11.16 | 7.69 | 11.61 | 5.89 | 28 | 20396, 20397 | yes (+1 ms) |
| after warm 1 | b8bd0ee, 1793491279004 | 16.16 | 2.76 | 0.57 | 10.74 | 6.42 | 11.62 | 5.97 | 0 | 20400, 20401 | yes (+0 ms) |
| after warm 2 | b8bd0ee, 1793491303390 | 16.15 | 2.82 | 0.62 | 10.75 | 6.38 | 11.63 | 11.58 | 0 | 20404, 20405 | yes (+0 ms) |

- MEASURED: the pass criterion held in all six runs (the fwcore-build span starts at or after the lake-lint span ends);
  no two lake builds overlap in locks.jsonl. All six exited 0.
- MEASURED: warm total 26.5 / 30.1 s before and 16.2 / 16.2 s after. The INFERRED 23 s was too high: the lake lint on a
  warm lake took 2.1-5.7 s here, not 7.6 s (the 001d247 lake lint was 7.6 s), and the build step 0.6 s. Critical path after:
  setup 0.8 + lake lint 2.8 + build 0.6 + max(reads 10.7, overflow 11.6) = 15.8 s plus 0.4 s after the wave.
- MEASURED scope: the rows above come from scratch commits 6e8d03d58 (before) and b8bd0ee (after). They used the dry set, which holds no
  check.sh, so the later classification of check.sh as fwcoreBuild (checkKind in land.ts) does not change those runs.
- MEASURED: cold totals 78.6 s before and 65.2 s after, both dominated by 28 rebuilt modules (lake lint 51-54 s); the cold
  run is reported, not fixed. The 29-42 s cold runs in the finding were smaller edits.
- MEASURED: the reads test now waits for the build (it is a coreUser): 9.8 s before, 10.7-11.2 s after (more concurrent work).
- Load differs per run (4.6-11.6); the one load-11.58 run (after warm 2) is not slower.
- Failed runs: none. Runs I discarded as measurements, kept here for honesty: five earlier runs of branch dlw-scratch-b
  (built 0 on a leaf edit: the pre-commit hook had already built the committed edit into the shared artifact cache, so no
  run showed built > 0 until the edit sat on an older base, which is why the final branch is based on 7cd9dd837).

## Accepted limits (from the task)

fwcore-build after the lake lint stays a near no-op; fwcore-build first is rejected (a later lake lint could relink the
binary under running users, INFERRED); lints that do not read lean/.lake stay `other`; peak concurrency rises; no
load-aware baseline; the ledger check stays after the wave; lints now run even when reads refuse and the VERDICT is
unchanged (`dryVerdict`, land-dry.test.ts); the log line is now "dry: lints not judged (reads refused first)".
