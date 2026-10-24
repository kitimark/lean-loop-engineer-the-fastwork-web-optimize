# Dry land timing.slow alerts of 2026-10-24: a verdict at the load floor, not a found culprit

Status: MEASURED over `.fw-console/timings.jsonl`, `locks.jsonl`, `sup-samples.jsonl` and `land-logs/` (local, 2026-10-22 to
24); the cause of the extra work in two of three samples is UNEXPLAINED; the rule's cut is INFERRED.

## What grew (span durations, ms)

Calm = median of the local exit-0 rows of each step whose own load floor is <= 3, rows started 2026-10-22 04:43 to
2026-10-24 00:14 UTC (before c4f662a): land-inputs n 309, lake n 289, check-workflows n 37, widths n 6, dry total lake n 248.

| dry sub-step | calm | bf9aa85 | 8f040f0 | c4f662a |
|---|---|---|---|---|
| land-inputs vitest | 21447 | 31938 | 29977 | 29903 |
| lake build + axiom check | 3314 | 19049 | 16400 | 9018 |
| check-workflows | 1940 | 2437 | 2399 | 2150 |
| land-overflow-widths vitest | 11588 | 12765 | 12694 | 12445 |
| dry total lake | 28342 | 66180 | 62005 | 53521 |

The vitest of `land-inputs` and the lake step grew; the widths vitest and the workflow check did not. Load floor of the
`dry total lake` rows: 6, 5, 5 (1-min averages 6.02, 5.24, 5.56), below the machine limit 8.

## Per sample: co-runners with cited rows, and what grew in the land's own work

Rows below come from a local scratch script (not committed) over the three files (ts relative to the span start, seconds).

| | bf9aa85 | 8f040f0 | c4f662a |
|---|---|---|---|
| span started (ms) | 1792784674400 | 1792797284538 | 1792801201230 |
| spans over 1.5 s overlapping, not this land | `fw polish commit` (23 s), `ci wait`, slot waits | `ci wait`, `slot wait test` 124 s | `ci wait`, slot waits |
| other slot holds in the window (locks.jsonl) | none; a land released the slot at -2 s | none; a check (142 s) released it at -1 s | none; a check (146 s) released it at -1 s |
| lake-slot acquires in the window | only the land's own at +33 and +52 | own at +31 and +48 | own at +31 and +40 |
| sup-samples kinds (sup-samples.jsonl) | leanBuild 2 at -27, -7, +12 s, then 0; simulator 0; node 24-29 | simulator 290-291 and leanServe 5 at -29..+70 s; leanBuild 2 at -29, -9 | leanBuild 2 at -26, -6 (own lake from +31); simulator 0; node 19-22 |
| load before / during / after (sup) | 3.1 / 3.6, 4.7 / 5.9 | 6.1 / 6.0, 5.2 / 5.9 | 2.8, 2.7 / 3.5, 5.4 / 5.6 |
| co-runner found | a `leanBuild` pair for the first 12 s (no lock row, no span); cause unnamed | yes: a Simulator process group (290 processes) and 5 `lake serve`, running before and through the land | none; the load rose 2.7 to 5.6 during the land |
| contended verdict rests on | the load floor, with a short unslotted lake build at the start | the load floor, with a named co-runner | the load floor alone |

What grew in the land's own work (land-inputs 56 tests passed in all three logs; `land-logs/*.log`):

- The test file `apps/runner/test/land-inputs.test.ts` is the same at the three commits and at calm commits (21 tests, 291
  lines); tracked files grew 6 to 7 percent (3907-3925 to 4154-4195), runner test files 110-111 to 116, Lean files in
  `lean/` 557-559 to 578. A 45 percent longer vitest does not follow from 6 percent more files.
- Lean modules rebuilt: `8f040f0` rebuilt 7 (`Fw` alone 7.3 s), explaining part of its 16.4 s; `bf9aa85` and `c4f662a`
  show no `Built` line, so their 19.0 s and 9.0 s (axiom check over 87941 constants, lake probe) are not rebuild work.
  Lean files changed against the previous dry land do not predict the step: calm rows with 6 to 20 changed files took
  3.9 s (median), against 9 to 19 s here with 3 to 11 changed files.
- Cause: `8f040f0` partly explained (co-runner plus 7 rebuilt modules); `bf9aa85` and `c4f662a` UNEXPLAINED. A hypothesis
  not tested: the shared land worktree (`.claude/land-wt/1`) checks out a different branch each land, so file caches
  are cold; the logs and rows do not show it.

## Load against duration (495 local `dry total lake`, exit 0, first count)

| load floor | n | median s |
|---|---|---|
| 1 | 12 | 24.4 |
| 2 | 88 | 26.1 |
| 3 | 148 | 31.2 |
| 4 | 130 | 33.4 |
| 5 | 61 | 37.8 |
| 6 | 20 | 39.0 |
| 7 | 13 | 39.4 |

A dry land alone sits at load 3 to 4 (278 of 495 samples), so the machine limit 8 fires only for the 16 samples above load
8 and never for a dry land alone.

## Decision (Lean, `Fw.Obs.Timing`)

- `landDryLoad = 4`; `Sample.dryLand` = tool `fw land`, step starting `dry`; `contended` has two branches, each its own
  theorem: `contended_of_load` (above `loadMax`), `contended_of_dryLand` (dry land above `dryLandMax`);
  `contended_cases`, `contended_between`, `not_contended_of_load_le` (now with the dry land hypothesis). `dryLandMax` is a
  request field (`obs.timing`/`obs.slow` params), pinned by a golden row.
- `landDry_three_contended`: the three samples (66643 vs 43056 at load 6, 62485 vs 40604 at 5, 53534 vs 35047 at 5) are
  `contended`, and the same durations at load 4 are `slow`. A regression that leaves the load at or below 4 still alerts;
  one that raises the dry land's own load above 4 is judged contended (accepted limit). Golden rows in
  `packages/contracts/golden/obs/timing.jsonl`.
- Chosen: a contended verdict (no slow alert, out of the windows). Slot serialization against builders was rejected: no
  slot hold other than the land's own overlaps the samples, and a slot kind for builder runs would block builders for the
  length of a land.

## Expected effect: replay of fwcore, old rule against new

Replay (local scratch script, not committed): the `fw land` `dry total lake` rows of timings.jsonl through `parseSamples` (work
buckets kept), once through the main fwcore and once through this branch's fwcore (`obs.timing`). 545 rows now, 520 exit 0
(the first count was 495).

| rule | slow, 520 exit-0 rows | slow at load <= 4 | slow at load > 4 | contended |
|---|---|---|---|---|
| old (loadMax 8) | 44 | 28 | 16 | 15 |
| new (dryLandMax 4) | 41 | 41 | 0 | 117 |

- 16 slow verdicts at load 5 to 8 leave (12 become contended, 4 noBaseline); 13 new slow verdicts appear at load
  <= 4, because 105 rows turn contended and leave the windows and the baseline p50 drops, so the 1.5x threshold drops. Net 44 -> 41.
  The rule moves alerts to calm samples more than it removes them.
- Later dry lands show the real effect; it is measured after landing.
