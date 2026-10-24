# probe-apple cap: 18 min, re-derived from the retry-era legs

Task `probe-apple-cap` (follow-up of `webkit-morph-walk-noise`). Branch `ci/probe-apple-cap`.

## Answer

- **Chosen: re-derive the cap, do not budget the extra passes (decision, reason below).** The `probe-apple` cap is now
  **18 min** (was 15): the retry-era sample of 6 legs has a linear p90 of 13.2 min (MEASURED), and 1.3 x 13.2 rounds up to 18 (the
  rule of every cap row, `Fw.Ci.Pool.Caps.capMin`).
- **Worst case is under the cap (Lean, from measured numbers):** a leg of two widths that runs the full 8 extra passes at each
  width takes 718 s (base) + 16 x 19 s = 1022 s = 17.0 min; the cap allows 1080 s. Theorems `Caps.probe_worst_under_cap` and
  `Trajectory.leg_wall_under_cap` (any macOS leg of any picked widths, any extra passes up to `legs x extraCap`).
- **Retry role is in Lean** (`Trajectory.retries`, `settleFor`; golden line `retryRole`), `out.reps` is the pooled passes
  (`reps + extra`, Lean `pooledReps`, golden field `pooled`).
- **Clean Mac run (MEASURED):** run 40133346582 on `ci/probe-apple-cap` at 54a5c24, dispatched by the lead with
  `fw=engine.scroll:batched`, `engines=playwright-webkit`, no debug recorder (a `ci/*` push alone reaches the Mac leg only with
  `debug=` or `[frames:`, Lean `Fw.Ci.Trigger.appleRuns`). Conclusion success; both legs inside the 18 min (1080 s) cap, see below.

## The clean Mac run (MEASURED)

`gh run view 40133346582 --json jobs`, `startedAt` to `completedAt`:

| job | wall (s) | cap (s) | headroom (s) |
|---|---|---|---|
| probe apple 640_1280 | 726 | 1080 | 354 |
| probe apple 390_641 | 819 | 1080 | 261 |
| merge apple | 28 | | |

- Both walls are within the sampled range (681 to 833 s) and each is at most base + extra x 19 s: 726 s is 718 + 8 (no extra pass
  needed), 819 s is 718 + 101, about 5 extra passes (INFERRED; the extra count is not read here). Under the 15 min cap (900 s) both would
  also have passed, so this run shows the new cap is not too short, not that the old one was; the old cap's overrun risk is the
  Lean worst case (`probe_worst_under_cap`), not a measured timeout.
- n is now 8 legs; the lane stays thin until 10 successes (Lean `probeWalls` is not extended here: the sample is the pinned 6).

## The sample (MEASURED)

`gh run view <id> --json jobs`, `startedAt` to `completedAt` of the `probe apple` jobs, all successes. Extra passes are
from the notes of `webkit-morph-walk-noise` (run 40122382227: 641 had 2; 40125557073: 1280 had 1; 40127042262: 641 had 8, 1280 had 3).

| run | leg | wall (s) | extra passes | wall less extra x 19 s |
|---|---|---|---|---|
| 40122382227 | 390_641 | 749 | 2 | 711 |
| 40122382227 | 640_1280 | 686 | 0 | 686 |
| 40125557073 | 390_641 | 681 | 0 | 681 |
| 40125557073 | 640_1280 | 737 | 1 | 718 |
| 40127042262 | 390_641 | 833 | 8 | 681 |
| 40127042262 | 640_1280 | 734 | 3 | 677 |

- Sorted walls 681, 686, 734, 737, 749, 833 s; linear p90 at rank 0.9 x 5 = 4.5 is 749 + 0.5 x 84 = 791 s = 13.18 min, rounded
  up to 13.2 min (`probe_p90`). n = 6 < 10, so the lane stays thin.
- Pass time: the eight extra reps of the 8-extra leg (run 40127042262, job 120970820360, log) start 18.1 to 18.5 s apart;
  19 s is that, rounded up (`probePassSec`). The pairwise slope of leg wall on extra passes is 19 s (833 vs 681 s over 8).
- Base wall: the greatest "wall less extra x 19 s" is 718 s (`probeBaseSec`, `probe_base`); `probe_model_covers` proves every
  sampled leg is at most base + extra x 19 s. The leg of 737 s with one extra pass is the noisy one: legs vary by about 40 s
  with no extra pass at all, which the base covers.
- The pre-retry sample (9.1, 9.2, 10.9, 11.3 min, task `trajectory-probe-speed`) ran no retry and is replaced, not mixed in.

## Why a re-derived cap and not a per-leg budget

| | re-derive the cap | per-leg budget of extra passes |
|---|---|---|
| worst leg wall | 17.0 min (2 x 8 extra) | base + budget x 19 s, e.g. 14.5 min at 8 |
| retry power per width | unchanged, cap 8 (Monte Carlo of the parent note: 0.87 of cells do not repeat) | a shared budget starves the second width of a leg; a split budget (4 each) is weaker than the cap 5 row (0.68) |
| cost when nothing hangs | none: `timeout-minutes` is a ceiling, the run takes the time it takes | none |
| ripple | cap row, golden `pool-caps`, `pool-fallback` (one request line: 15 to 18 min), workflow, `ci-paths` test | settle gets a state across widths; TS twin and goldens grow |

INFERRED: a width that is not retried is exactly the noise the retry exists to remove (a missed bucket repeats at that
width), so a budget would trade a timeout that costs nothing for a verdict that is noisy again. The cost of a longer cap is
the wait before a hung macOS job is cancelled (3 more minutes of a shared slot), which is rare and is not the measured case.
The extra passes per leg are still bounded in Lean: at most `widths x extraCap` (`leg_extra_le`, `legs_mac_len`: a macOS leg has
at most two widths).

## What changed

- `lean/Fw/Ci/Pool/Caps.lean`: `probeWalls`, `probePassSec`, `probeBaseSec`, `legWorstSec`, `p90dmOfSec` (the p90 is computed, not
  typed); the row is `(6, 132)`, cap 18; theorems above. Golden `pool-caps.jsonl` (written by Lean).
- `lean/Fw/Gate/Trajectory.lean`: `ArmRole`, `retries` (only the candidate, only with a base run at the width), `settleFor`,
  `pooledReps`, `leg_extra_le`, `legs_mac_len`, `legWallSec`, `leg_wall_under_cap`, `legWall_worst`; golden lines `retryRole`,
  `legWall`, field `pooled` of `settle` (trajectory.jsonl, 384 lines, written by Lean). `settle`/`settleWalk` are unchanged:
  `settleWalk_le`, `settleWalk_stop`, `settleWalk_deterministic` still hold (the build proves them).
- `trajectory-probe.yml` `probe-apple` `timeout-minutes: 18`; `scripts/ci-paths.test.mjs` pool caps 18 and n 6.
- `plan.mjs` `retriesRole`, `pooledReps` (TS twins, replayed against the golden); `run.mjs` calls `retriesRole` and sets
  `out.reps = reps + extra` for the candidate.
- `trajectory.test.mjs`: replays `retryRole`, `legWall`, `pooled`; a fake-engine test of
  `morphPath` that checks `out.reps` is 6 after one extra pass and 5 without `against`.

## Limits

- The 6 legs are few and include the run with the first retry rule and the page recorder (40122382227); p90 of 6 is the
  interpolation between the 5th and 6th wall. The lane stays thin until 10 successes; re-derive then.
- The 19 s pass time and the 718 s base are measured on shared macOS runners; a runner 6 % slower on the whole leg (1022 vs 1080
  s) would still time out, but only in the rare case that both widths run all 8 extra passes.
- Playwright WebKit on macOS stands in for Safari. One clean run, not a pass-rate study.
- TS stand-ins: `run.mjs` role selection and the `out.reps` assignment are glue around the Lean-checked `retriesRole` and
  `pooledReps` (the fake-engine test covers `morphPath`, not `runLane`).
- Stale prose outside this task's writes (not edited, follow-up): `docs/team/tools/trajectory-probe.md` line 751 and `trajectory-frames.md` line 24 still
  say cap 15 min (follow-up).
