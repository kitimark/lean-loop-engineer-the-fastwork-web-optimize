# fwcore console.query speed (2026-10-20)

Symptom: `console.query` took 0.66 / 4.2 / 51.7 s on 1x / 2x / 4x copies of the real log (super-quadratic), so the console
needed `FW_CORE_CALL_MS=60000` once the log reached about 4 days of events.

## Cause (MEASURED, CONFIRMED in source)
`fastBoard` was already linear. The cost sat in `Fw.Plan.view`. A compiled timing of its parts at 4x (2,188 rows,
`lean/scripts/QueryProfile.lean`):

| part | before | after |
|---|---|---|
| `criticalPath`: `tab` runs up to `|ts|` rounds, each scanning the rows for the dependents of every task and the table for every lookup (cubic) | about 30 s | 1 ms |
| `bound`: `bindRow` calls `keysOf`, `openedK`, `endedK`, `lastAt`, `markOf`, each a scan of the label, spawn, stop or mark list, per row | about 2.3 s | 12 ms |
| `groups`: `place` splits the glob strings again for every pair in `conflict` | 1.5 s | 0.18 s |
| `taskView`, `tstate`, `blockers`, milestones, `fastBoard` | 30 ms or less each | unchanged |

(Interpreted timings at 1x and 2x showed `criticalPath` growing 8.7x, `groups` 3.4x, `taskView` 4x per doubling.)

## Fix (`lean/Fw/Plan/FastView.lean`, `lean/Fw/Plan/FastBound.lean`; `Fw.Serve` runs `fastView`)
- `fastCriticalPath`: a dependents index (`depIdx`) and a table index (`mkMap`), stopping at a round that changes
  nothing. A repeated table repeats forever, so the equality needs no acyclicity.
- `boundF`: five questions (`Prims`: keys of a name, seen, live, last seen, last mark) answered from hash indexes built
  once per query (`Idx.build`); `bindRowP` is `bindRow` over any `Prims`, and over the scan it is `bindRow` by unfolding.
- `groupsF`: the same greedy placement over items whose write globs are split once.
- Pitfall (MEASURED): indexes in `let`s inside the lambdas of one structure were inlined into the closures by the
  compiler and rebuilt per call (104 s). `Idx` is a data structure passed to `@[noinline]` functions.

## Proofs (no sorry; one theorem per replaced definition)
| replaced | theorem |
|---|---|
| `criticalPath` | `fastCriticalPath_eq`, from `depIdx_get`, `mkMap_get`, `stepF_eq`, `tab_fix`, `fastTabAux_eq` |
| `bound` | `boundF_eq`, from `Prims.fast_eq`: `labIdx_get`, `seenSet_get`, `lastIdx_get`, `stopSet_get`, `stopIdx_get`, `endedF_eq` (`any_stop`, `all_sights`), `markIdx_get` |
| `groups` | `groupsF_eq`, from `conflictS_of`, `fitsS_of`, `placeS_of`, `foldl_placeS` |
| `view` | `fastView_eq`; the `Fw.Serve` theorems `query_keeps`, `query_eq_of_st`, `query_after_run` keep their statements |

## Measurement (local debug run of our own binaries, no CI lane; `lean/scripts/query-golden.sh`)
| log | events | query old | query new | replay old / new | reply |
|---|---|---|---|---|---|
| real | 14,557 | 630 ms | 22 ms | 139 / 141 ms | byte-identical |
| 2x (ids renamed) | 29,114 | 4,037 ms | 67 ms | 380 / 376 ms | byte-identical |
| 4x (ids renamed) | 58,228 | 33,300 ms | 229 ms | 1,318 / 1,297 ms | byte-identical |

Target (4x under 1 s): met, 229 ms. Synthetic log (`synth-log.mjs 600`, 4 copies, 11k events): old 152 s, new 0.16 s,
identical. Copies come from `lean/scripts/scale-log.mjs` (suffix `~k` on ids, seq and ts shifted); nothing from the real
log is committed.

## Limits and follow-ups
- Still quadratic but small at 4x: `groupsF` (ready rows x groups, 0.18 s), `cleared` inside `tstate`/`blockers` (20 ms),
  and the label and spawn scans in `taskView` for rows with an agent. Replace if the log grows 10x.
- Replay of a synthetic deep dependency chain (600 tasks, each depending on the previous) takes 1.7 s per 2.8k events
  (`checkFast` follows the whole ancestor chain for each define). The real log does not have that shape.
- Timings are local debug runs.
