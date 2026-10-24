# Mac WebKit morph: the walk coverage noise, and the retry that settles it

Task `webkit-morph-walk-noise` (split from `webkit-morph-cell`). Branch `ci/webkit-morph-walk-noise`.

## Answer

- **Cause (CONFIRMED, run 40099056290, Mac morph, 5 reps per arm):** the morph is time driven, so an interior bucket
  (a tenth of the morph value) is passed in 5 to 15 ms. A Mac VM frame gap is p50 22 ms, p90 66 ms, p99 120 ms, so one
  walk has 5 to 18 moving frames and misses a bucket at random. A bucket that base hit in some rep, the candidate (or the
  control `hero.exit:faithful`) misses in all 5 reps; the reducer then gives `fail:coverage`, `rel = new`, at the same
  step on every width, and two widths make "no verdict: coverage". It is noise in the walk, not the flag.
- **Fix:** a per-width retry decided in Lean. After its 5 reps the candidate walks extra fresh pages while some interior
  bucket of the open or close push has rows in orig and base but none in the candidate, at most 15 extra (`extraCap`).
- **Lean:** the retry loop terminates within the cap, ends with no gap or at the cap, and a page whose hits do not change
  gives the same coverage on repeat. The decision reads recorded facts (which buckets have rows) only.
- **CI:** see "CI result" below.

## Cause

| fact | value | status |
|---|---|---|
| per-walk hit chance, open buckets 2, 3, 4 | 0.23, 0.12, 0.25 | MEASURED (run 40099056290, 60 walks per phase) |
| per-walk hit chance, close bucket 8 | 0.18 | MEASURED |
| Mac frame gap p50 / p90 / p99 | 22 / 66 / 120 ms | MEASURED |
| candidate missing buckets vs reported new steps | equal: 390 open@5 and close@8, 641 open@3 and close@8 | MEASURED |
| cost of one pass on the Mac | about 17 s (5 reps about 85 s); the apple leg takes about 11 min | MEASURED |

Source: `run.mjs` `morphPath` (REPS fresh pages, rows pooled), `reduce.mjs` `bucket` (floor((m+500)/1000) clamped to 0..10)
and the push coverage rule (CONFIRMED by reading). An empty interior bucket of the rewrite's pooled rows is
`fail:coverage` (`bucketVerdict_push_empty`). Orig and base miss buckets too, but the reducer only counts a candidate
miss as `new` when the faithful arm hit it, so a flag active at every width shows the control's repeat.

## The decision

Lean (`lean/Fw/Gate/Trajectory.lean`, section "settle"):

- `gapsIn`/`gaps`: buckets 1..9 with rows in orig and base and none in the candidate. `more extra o b c`: `extra < extraCap`
  and `gaps ≠ 0`. `settle`/`settleWalk`: fuel loop that pools one fresh walk per step.
- Terminates: `settle_le`, `settleWalk_le` (extra <= `extraCap`), `more_cap`.
- Stops with no gap or at the cap: `settle_stop`, `settleWalk_stop`, `settleWalk_no_gap` (no gap: no extra walk).
- Facts only: `more_congr`, `gaps_congr` (the decision depends on `sameHits`, not on row values).
- Never loses a hit: `settle_hit_mono`, `settleWalk_hit_mono`, `gaps_pool_le`.
- Deterministic page, same coverage on repeat: `settle_const`, `settleWalk_deterministic` (same hits and gaps), and
  `settleWalk_deterministic_capped` (a bucket the page never visits stays a gap and runs to the cap).
- Link to the verdict: `gap_is_coverage_fail`, `no_gap_sampled` (a gap is the `fail:coverage` of the reducer).
- Concrete branches by `decide`: `gaps_run_shape`, `more_run_shape`, `more_full`, `more_base_gap`, `gaps_ends`,
  `settle_fills`, `settle_capped`, `outcome_active_flag_settled` (an all-width flag, Mac morph: outcome pass, no groups).
- Golden: 14 `casesSettle` lines (`retry`, `settle`, `settleConst`) in `packages/contracts/golden/gate/trajectory.jsonl`
  (383 lines, written by Lean); `trajectory.test.mjs` replays them against `plan.mjs` (423 pass).

Why a cap of 15 (INFERRED, Monte Carlo `mc.mjs` from the hit table above, 20000 trials):

| extra cap | P(cell does not repeat at 2 or more widths) | mean extra passes per width |
|---|---|---|
| 0 | 0.33 | 0 |
| 5 | 0.86 | 1.7 |
| 10 | 0.98 | 2.3 |
| 15 | 0.994 | 2.6 |
| 20 | 0.999 | 2.7 |

Worst case +15 passes (about 4.25 min) per width, so the apple job `timeout-minutes` goes from 15 to 40
(`.github/workflows/trajectory-probe.yml`, outside the task writes, listed in the report).

## Limits

- A page that never visits a bucket runs to the cap and the gap stays; this is a real failure and is kept
  (`settleWalk_deterministic_capped`).
- The retry fills only the candidate versus base asymmetry; a coverage failure caused by orig windows out of reach is not retried.
- Only the candidate retries; orig and base are walked once, so a bucket orig or base missed is not a gap by design.
- Playwright WebKit on macOS stands in for Safari. The phone is not measured. macOS runners are shared, so a run may queue.
- TS stand-in: `run.mjs` `pushReading` and the `against` selection (glue, no unit test; checked by one local wiring run
  that added an extra rep, which is not a result). `plan.mjs` `settleReps` is the TS twin, checked against the golden.

## CI result

(filled in below)
