# Mac WebKit morph: the walk coverage noise, and the retry that settles it

Task `webkit-morph-walk-noise` (split from `webkit-morph-cell`). Branch `ci/webkit-morph-walk-noise`.

## Answer

- **Cause (CONFIRMED, run 40099056290, Mac morph, 5 reps per arm):** the morph is time driven, so an interior bucket
  (a tenth of the morph value) is passed in 5 to 15 ms. A Mac VM frame gap is p50 22 ms, p90 66 ms, p99 120 ms, so one
  walk has 5 to 18 moving frames and misses a bucket at random. A bucket that the faithful arm sampled, the candidate (or the
  control `hero.exit:faithful`) misses in all 5 reps; the reducer then gives `fail:coverage`, `rel = new`, at the same
  step on every width, and two widths make "no verdict: coverage". It is noise in the walk, not the flag.
- **Fix:** a per-width retry decided in Lean. After its 5 reps the candidate walks extra fresh pages while some interior
  bucket of the open or close push has a row in the faithful arm and none in the candidate, at most 8 extra (`extraCap`).
- **Lean:** the retry loop terminates within the cap, ends with no gap or at the cap, and a page whose hits do not change
  gives the same coverage on repeat. The decision reads recorded facts (which buckets have rows) only.
- **CI (MEASURED):** `engine.scroll:batched`, active at every width, passes the Mac morph cell (outcome `pass`: no node
  property new at two or more widths) in run 40127042262 (final rule) and in run 40122382227 (first rule). Run 40125557073
  (final rule) has no coverage unit new at any width but fails on a content group at 640 and 641 (below): a second noise,
  of the colour transition in flight at the end of the close push, not of the coverage walk. So no coverage group repeats at two widths in
  3 of 3 runs; the cell passes in 2 of 3 and the third is the content noise, a follow-up.

## Cause

| fact | value | status |
|---|---|---|
| per-walk hit chance, open buckets 2, 3, 4 | 0.23, 0.12, 0.25 | MEASURED (run 40099056290, 60 walks per phase) |
| per-walk hit chance, close bucket 8 | 0.18 | MEASURED |
| Mac frame gap p50 / p90 / p99 | 22 / 66 / 120 ms | MEASURED |
| candidate missing buckets vs reported new steps | equal: 390 open@5 and close@8, 641 open@3 and close@8 | MEASURED |
| cost of one pass on the Mac | about 17 s (5 reps about 85 s); the apple leg takes about 11 min | MEASURED |

Source: `run.mjs` `morphPath` (REPS fresh pages, rows pooled), `reduce.mjs` `bucket` (floor((m+500)/1000) clamped to 0..10)
and `bucketVerdict` (an empty interior bucket of the rewrite's pooled push rows is `fail:coverage`, whatever the original
did; `bucketVerdict_push_empty`) (CONFIRMED by reading). The faithful arm is judged the same way, so a candidate miss is
`new` only where the faithful arm had a row; the control `hero.exit:faithful` shows the same repeat, which is why a flag
active at every width cannot join `v2-proved` while the walk is noisy.

## The decision

Lean (`lean/Fw/Gate/Trajectory.lean`, section after `Reading`):

- `gapsIn`/`gaps`: buckets 1..9 where the faithful arm has a row and the candidate none. `more extra b c`: `extra < extraCap`
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
- Golden: 13 `casesSettle` lines (`retry`, `settle`, `settleConst`) in `packages/contracts/golden/gate/trajectory.jsonl`
  (382 lines, written by Lean); `trajectory.test.mjs` replays them against `plan.mjs` (422 pass).

Why a cap of 8 (INFERRED, Monte Carlo `mc2.mjs` from the hit table above, 20000 trials, the base-only rule):

| extra cap | P(cell does not repeat at 2 or more widths) | mean extra passes per width |
|---|---|---|
| 0 | 0.13 | 0 |
| 5 | 0.68 | 2.4 |
| 8 | 0.87 | 3.1 |
| 15 | 0.98 | 3.9 |

The apple job has a 15 min `timeout-minutes` that Lean decides (pool caps, `scripts/ci-paths.test.mjs` "pool caps"), and a
leg of two widths already takes about 11 min (MEASURED, run 40099056290). One pass is about 17 s, so the cap is 8: worst
case about 2.3 min per width, mean about 53 s. A cap of 15 would pass more often but its worst case runs past the job cap, and a
timeout loses the whole leg. A run that still repeats is a noisy walk, not a verdict: run it again.

## Run 1 (40122382227, MEASURED)

Push `a8c25507`, line `fw=engine.scroll:batched engines=playwright-webkit debug=nav-transition` (a `ci/*` push runs the
Mac leg only with `debug=` or `[frames:`; agents cannot dispatch). It ran the first rule (original AND faithful had a row,
cap 15, the apple job at 40 min). Mac morph, 5 reps, `trajectory-apple`:

| width | new units | what | extra passes of the candidate |
|---|---|---|---|
| 390 | 1 | content: `logo.color` close@0 | 0 |
| 640 | 5 | content: `nav.background-color` close-hold@0, `earn.opacity` and `earn.max-width` open@9, open@10 | 0 |
| 641 | 0 | | 2 |
| 1280 | 42 | coverage: open@3 (same 42 node properties) | 0 |

No node property is new at two or more widths (content or coverage), so `cellOutcome` is `pass` and the lane word is RED
only on single-width units. The retry fired at 641 (2 extra passes). It did not fire at 1280 because the original had no row in
open bucket 3 (the first rule required it) while the faithful arm had one, and the reducer fails the candidate there all the
same: that was the defect of the first rule. The final rule drops the original. This run also carries the page recorder
(`debug=nav-transition`, on base and cand, not on orig), so it is a witness for the cell, not a clean run.

## Runs 2 and 3 (final rule, MEASURED)

Same line, final code (faithful arm only, cap 8, apple job at 15 min). `trajectory-apple`, Mac morph:

| run | width: candidate extra passes | coverage new | content new | outcome |
|---|---|---|---|---|
| 40125557073 | 390: 0, 640: 0, 641: 0, 1280: 1 | 0 | `nav.background-color` 640 close-hold@0 and 641 close@0 (`fail:apart`) | fail (content group at 2 widths) |
| 40127042262 | 390: 0, 640: 0, 641: 8 (cap), 1280: 3 | 42 at 641 close@8 (the cap ran out) | `nav.background-color` 1280 close@0 | pass |

The content units are the colour transition of the nav still running at the end of the close push: rows at `m` 0 to 70 have
`since` 24 to 60 ms after the class change, and their colour depends on the frame (run 40125557073, 641, orig vs cand rows).
It shows in all three runs at close@0 or close-hold@0 (`logo.color`, `nav.background-color`) at one to two widths; it repeats
at two widths by chance. Not a coverage failure, not touched here (follow-up: a retry or a window for the end of the close).
Queueing: the macOS runners are shared; the second Mac leg of run 1 sat queued for a while, each run took several 540 s waits.

## Limits

- A page that never visits a bucket runs to the cap and the gap stays; the failure is kept
  (`settleWalk_deterministic_capped`).
- If the faithful arm's own row in a bucket has no window (nothing of the original brackets it), it fails too and the retry
  spends the cap for nothing; the cap bounds the cost.
- Only the candidate retries; orig and base are walked once.
- The content units at 390 and 640 in run 1 (`apart` at close@0, open@9/10) are a second noise, of transitions in flight, not
  of the walk; they did not repeat across widths. Not addressed here.
- Playwright WebKit on macOS stands in for Safari. The phone is not measured. Run 1 queued the second Mac leg, about 25 min
  from push to finish.
- TS stand-in: `run.mjs` `pushReading` and the `against` selection (glue, no unit test; checked by one local wiring run
  that added an extra rep, which is not a result). `plan.mjs` `settleReps` is the TS twin, checked against the golden.
- `debug=nav-transition` is the only way a `ci/*` push reaches the Mac leg; a clean run needs a lead dispatch:
  `pnpm -s fw run --trajectory --ref ci/webkit-morph-walk-noise --fw engine.scroll:batched --engines playwright-webkit`.
