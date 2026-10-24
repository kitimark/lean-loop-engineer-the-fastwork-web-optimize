# Dry land timing.slow alerts of 2026-10-24: two of four had no co-runner; the dry land's own land-inputs vitest and lake rebuilds grew. Locked dry lands run one at a time, but 133 of 760 ran with no land-slot row (to the cutoff 1792808775650).

Status: MEASURED over `.fw-console/timings.jsonl`, `locks.jsonl`, `sup-samples.jsonl` and `land-logs/` (local, 2026-10-22
to 24). Pinned cutoff: the last `startMs` of the rows used, 1792808775650 (2026-10-24); rows added later do not count. The
mechanisms are INFERRED. Closed as a finding; no code lands from this branch.

## What grew (span durations, ms)

Calm = median of the local exit-0 `fw land` rows of each step, dry and local-tier runs together, whose own load floor (integer part of the 1-min average) is <= 3,
rows started 2026-10-22 04:43 UTC to just before c4f662a (1792801201230): land-inputs n 346, lake n 289, check-workflows
n 39, widths n 7, dry total lake n 248.

| dry sub-step | calm | bf9aa85 | 8f040f0 | c4f662a |
|---|---|---|---|---|
| land-inputs vitest | 21414 | 31938 | 29977 | 29903 |
| lake build + axiom check | 3314 | 19049 | 16400 | 9018 |
| check-workflows | 1949 | 2437 | 2399 | 2150 |
| land-overflow-widths vitest | 11588 | 12765 | 12694 | 12445 |
| dry total lake | 28341 | 66180 | 62005 | 53521 |

The vitest of `land-inputs` and the lake step grew; the widths vitest and the workflow check did not. Load floor of the
`dry total lake` rows: 6, 5, 5 (1-min averages 6.02, 5.24, 5.56), below the machine limit 8.

## Per sample: co-runners with cited rows, and what grew in the land's own work

Rows below come from a local scratch script (not committed) over the three files (ts relative to the span start, seconds).

| | bf9aa85 | 8f040f0 | c4f662a |
|---|---|---|---|
| span started (ms) | 1792784674400 | 1792797284538 | 1792801201230 |
| spans over 1.5 s overlapping, not this land | `fw polish commit` from -11.1 to +23.0 s (34.1 s span), `ci wait`, slot waits | `ci wait`, `slot wait test` 356 s (e41d829) and 211 s (97c0825) | `ci wait`, slot waits |
| other slot holds in the window (locks.jsonl) | none; a land released the slot at -2 s | none; a check (142 s) released it at -1 s | none; a check (146 s) released it at -1 s |
| lake-slot acquires in the window | only the land's own at +33 and +52 | own at +31 and +48 | own at +31 and +40 |
| sup-samples kinds (sup-samples.jsonl) | leanBuild 2 at -27, -7, +12 s, then 0; simulator 0; node 24-29 | simulator 290-291 and leanServe 5 at -29..+70 s; leanBuild 2 at -29, -9 | leanBuild 2 at -26, -6 (own lake from +31); simulator 0; node 19-22 |
| load before / during / after (sup) | 3.1 / 3.6, 4.7 / 5.9 | 6.1 / 6.0, 5.2 / 5.9 | 2.8, 2.7 / 3.5, 5.4 / 5.6 |
| co-runner found | a `leanBuild` pair for the first 12 s, no lock row; the overlapping `fw polish commit` f6dafbd (-11.1 to +23.0 s) carries lake.built 32 (INFERRED source) | yes: a Simulator process group (290 processes) and 5 `lake serve`, running before and through the land | none; the load rose 2.7 to 5.6 during the land |

What grew in the land's own work (land-inputs 56 tests passed in all three logs; `land-logs/*.log`):

- The test file `apps/runner/test/land-inputs.test.ts` is the same at the three commits and at calm commits (21 it/test
  blocks, 56 tests run; 291 lines); tracked files grew 6 to 7 percent (3907-3925 to 4154-4195), runner test files 110-111
  to 116, Lean files in `lean/` 557-559 to 578. A 45 percent longer vitest does not follow from 6 percent more files.
- Lake step, by the lake field of the same dry land's span `fw`/`land dry lake` (the mechanism, rebuilds, is INFERRED):
  bf9aa85 rebuilt 24 modules (span lake.built 24; its land log `land-logs/sim-touch-reliable-bf9aa85.log` was
  overwritten by a later run in land-wt/1 five minutes after the dry land ended, so it shows no Built line), 8f040f0
  rebuilt 6 by the span (7 Built lines in its log), c4f662a 0 (span and log agree), 2e54fbe 24, 0, 24 in its three dry
  lands under its own commit label (27.7, 2.4, 23.5 s; a fourth 2e54fbe-labelled span at +543.5 s has children of commit 36acd37, built 7).

  | lake step by modules built (dry rows that have a lake field) | n | median s |
  |---|---|---|
  | 0 built | 104 | 3.0 |
  | 1-7 | 49 | 10.6 |
  | 8 or more | 56 | 19.0 |

  The 0-built median stays 2.6-3.3 s in every quarter (3.1, 3.3, 3.1, 2.6).
- Cause: bf9aa85's lake step is rebuild work (explained); 8f040f0 is rebuild work plus a named co-runner; c4f662a's
  9.0 s at 0 built stays unexplained (an outlier against 3.0 s). Land worktrees are a pool `.claude/land-wt/<n>` where
  each land claims the first free one (`apps/runner/src/land.ts:345-359` claimLandWt, `:361` checkoutLandWt @2ab421c), and
  the lake time follows modules rebuilt, not trace reads.

## Load against duration (543 local `dry total lake` rows, exit 0, to the cutoff)

| load floor | n | median s |
|---|---|---|
| 1 | 12 | 24.2 |
| 2 | 88 | 26.1 |
| 3 | 151 | 31.3 |
| 4 | 141 | 33.3 |
| 5 | 68 | 38.4 |
| 6 | 30 | 40.7 |
| 7 | 17 | 41.3 |

Most dry lands sit at load 3 to 4 (292 of 543 samples); 36 samples are above load 8.

## Serialization

The slot serializes the dry lands that take it. `locks.jsonl` has one `land` acquire/release around each of the four
alerted runs; waits before them 0-410 s; the build-slot waits inside them 6-22 ms. But `apps/runner/src/slot.ts:556-561`
@2ab421c skips acquire whenever `FW_SLOT_HELD` is set, whatever kind is held. Over all 760 local `fw`/`slot run land pnpm
fw land dry` spans to the cutoff (the lead's first count, 808 with 186 unlocked, also matched the `... dry cached` replay spans, which take no slot), 133 have no `land` slot acquire within 3 s of their start
and 40 started while another dry land was still running. Example: 36acd37 at 1792805763753 (+585 s from 2e54fbe's
start) ran over the land that held the slot from +543.5 to +613.5 s, with no lock row of its own. None of the four
alerted runs overlapped another dry land span. The 2e54fbe rerun at +96.5 s (lake 2.4 s, land-inputs 38.0 s) overlapped
d2c1f1c, so it is no calm control.

The fourth alert, 2e54fbe at 1792805178693: 77474 ms against a baseline of 42513, key `fw`/`slot run land pnpm fw land
dry`, load floor 6 (6.85). Its locks show only its own land hold (wait 0) and lake acquires at +34.4 and +62.3 s (waits
8 and 22 ms). No work span from another process overlaps it (only d2c1f1c's `slot wait land`, +37.1 to +78.4 s). sup-samples show a load of 5.2-5.8 before the start, carried in
the 1-min average from the dry land and the slot run test that ended 60 s and 44 s before it, and no named co-runner.
Its lake step built 24 modules (27.7 s).

## Decision

Decision: none in Lean in this task. The contended-vs-serialize question goes to slot-held-identity and
timing-contended-identity, own growth to land-inputs-growth and land-wt-lake-rebuilds.
