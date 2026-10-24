# Dry land timing.slow alerts of 2026-10-24: contention outside the slot

Status: MEASURED over `.fw-console/timings.jsonl` and `.fw-console/locks.jsonl` (local, 2026-10-22 to 24); rule INFERRED at the cut.

## What grew (span durations, ms; calm = median of local exit-0 rows at load floor <= 3)

| dry sub-step | calm | bf9aa85 | 8f040f0 | c4f662a |
|---|---|---|---|---|
| land-inputs vitest | 21160 | 31938 | 29977 | 29903 |
| lake build + axiom check | 2829 | 19049 | 16400 | 9018 |
| check-workflows | 1885 | 2437 | 2399 | 2150 |
| land-overflow-widths vitest | 11990 (all rows) | 12765 | 12694 | 12445 |
| dry total lake | 25706 | 66180 | 62005 | 53521 |

- The two growing steps are the vitest run and the lake step; the widths vitest and the workflow check did not grow.
- Load floor of the `dry total lake` rows: 6, 5, 5 (1-min averages 6.02, 5.24, 5.56), below the contended limit 8.
- `locks.jsonl`: the only slot hold overlapping each sample is the land's own (66, 62, 54 s). Other slot work is
  waiters (`slot wait test` 66 / 124 / 22 s, `slot wait check` 15 s). So the extra load came from work outside the slot:
  builder vitest and lake runs, and a Simulator boot, not from slot holders. The slot serializes what asks it; it cannot
  serialize what does not.

## Load against duration (495 local `dry total lake`, exit 0)

| load floor | n | median s |
|---|---|---|
| 1 | 12 | 24.4 |
| 2 | 88 | 26.1 |
| 3 | 148 | 31.2 |
| 4 | 130 | 33.4 |
| 5 | 61 | 37.8 |
| 6 | 20 | 39.0 |
| 7 | 13 | 39.4 |

A dry land alone sits at load 3 to 4 (278 of 495 samples), so the machine limit 8 never fires for it.

## Decision (Lean, `Fw.Obs.Timing`)

- `landDryLoad = 4`; `Sample.dryLand` = tool `fw land`, step starting `dry`; `contended` has two branches, each its own
  theorem: `contended_of_load` (above `loadMax`), `contended_of_dryLand` (dry land above `dryLandMax`);
  `contended_cases`, `contended_between`, `not_contended_of_load_le` (now with the dry land hypothesis).
- `landDry_three_contended`: the three samples (66643 vs 43056 at load 6, 62485 vs 40604 at 5, 53534 vs 35047 at 5) are
  `contended`, and the same durations at load 4 are `slow`. Golden rows in `packages/contracts/golden/obs/timing.jsonl`.
- Chosen: a contended verdict (no slow alert, out of the windows). Slot serialization against builders was rejected: the
  slow work is not in the slot, and a slot kind for builder runs would block builders for the length of a land.

## Expected effect (checked on later dry lands, not here)

- 100 of the 495 dry samples (20 percent, load floor 5 to 8) leave the windows and cannot alert; the dry baseline moves
  from 35 to 43 s toward the 26 to 33 s of loads 2 to 4. A real regression at load <= 4 still alerts.
