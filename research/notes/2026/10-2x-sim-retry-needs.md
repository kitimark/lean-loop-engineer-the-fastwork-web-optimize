# sim-retry-needs: the retry and tab needs chosen in Lean over the green jobs

Date: 2026-10-26. Task `sim-retry-needs` (follow-up of `wk-sim-hang`, note `10-2x-wk-sim-hang.md`). Data: `results/sim-retry-needs/` (`pieces.json`, `replay.json`, `scripts/`). Source of every number: the logs of the 98 green jobs of the wk-sim-hang sample (`results/wk-sim-hang/jobs.json`), downloaded with `gh run view --job <id> --log`. No CI run.

## Answer

- The needs (scroll, pass, tab) are a choice, decided in Lean over the gate decisions of the 98 green jobs: the decision (`Premise`, `refusedCount`, `pick`) and its general theorems are in `lean/Fw/Measure/SimHost.lean`, the data (`jobs`, written from `pieces.json` by `lean_data.py`) and the theorems on it in `lean/Fw/Measure/SimHostGolden.lean`.
- Among all needs that meet `Premise` (`runPass_stop_le`'s premise at the seen maxima plus tab cover, `tabWaitS ≤ tab`, which backs `tab_started_le` and is not a hypothesis of `runPass_stop_le`), the fewest green jobs are refused by `best` = (876, 1563, 480): 14 of 98. PROVED: `best_premise`, `best_fewest` (no premise-meeting needs refuse fewer, over all of ℕ³, so over any grid too: `grid_fewest`), `premise_best_le` (every premise-meeting needs are at least `best` in each component, so a tie goes to `best`), `best_refused`. Without the tab-cover conjunct the optimum is (876, 1563, 0), refusing 9 of 98 (`grid_frontier`), still more than 1. PROVED: `untabbed_fewest` (it is the least such needs over all of ℕ³).
- That is more than the shipped needs refuse, so the shipped needs stay deployed: scroll 589 s, pass 436 s (`SimHost.scrollNeedS`, `passNeedS`), tab need 0 (no tab gate). PROVED: `pick_fallback`, `deployed_is_pick` (the decision `pick best shipped jobs` returns the deployed needs).
- For the deployed needs the premise is unmet (`deployed_premise_unmet`, `SimHost.deployed_needs_missed`, `deployed_scroll_below_try`: 589 < the longest scroll try with its pass rest, 876). Model limit: a retry can still reach the step bound and be killed there.
- The tab gate is not deployed: at 480 s it would refuse 9 green jobs (navigations later than 1560 s into the step), 10 of 98 in all with the shipped needs. The deployed gates refuse 1 of 98 (`shipped_refused`). A tab wait capped to the time left is a follow-up.

## Premise and the theorem's condition

`Premise c`: `Seen.tryS ≤ c.scroll` (inner level: every scroll try, and for the try that ends the step the rest of its pass, fits the scroll need), `Seen.headS + c.scroll ≤ c.pass` (outer level: reconnect, tab wait and load of a pass head, then a scroll need, fit the pass need; the tab wait is the `tabS` term of the head), and `tabWaitS ≤ c.tab` (tab cover: the tab need covers the CI tab wait, 60 s × 8 = 480 s, so an admitted wait ends within the bound: `tab_started_le`). Tab cover is not a hypothesis of `runPass_stop_le`; with the deployed tab need 0 it is unmet, and the tab term and `tab_started_le` stay model results for a later wait cap.

`best_stop_le` is `runPass_stop_le` at `best`. Its condition: every scroll try lasts at most 876 s and every pass head at most 687 s, the maxima seen in the 98 green jobs. A retry whose real duration exceeds its need can still reach the step bound. The bound holds per pass, not per step.

## Frontier (Lean `grid`, `grid_frontier` in `SimHostGolden.lean`; TS replay agrees)

| Scroll need (s) | Pass need (s) | Tab need (s) | Refused green jobs (of 98) | Scroll | Pass | Tab | runPass_stop_le premise | tab cover |
|---|---|---|---|---|---|---|---|---|
| 589 | 436 | 0 | 1 (deployed) | 1 | 0 | 0 | no | no |
| 589 | 436 | 480 | 10 | 1 | 0 | 9 | no | yes |
| 589 | 1563 | 0 | 8 | 1 | 7 | 0 | no | no |
| 589 | 1563 | 480 | 13 | 1 | 7 | 5 | no | yes |
| 876 | 436 | 0 | 3 | 3 | 0 | 0 | no | no |
| 876 | 436 | 480 | 11 | 3 | 0 | 8 | no | yes |
| 876 | 1563 | 0 | 9 | 2 | 7 | 0 | yes | no |
| 876 | 1563 | 480 | 14 (`best`) | 2 | 7 | 5 | yes | yes |

The split by gate counts the first refused decision of a job (`replay.mjs`); the totals are Lean's `refusedCount`. Refusals only grow with each need (`refusedCount_mono`), so `best`, the least premise-meeting needs, is the optimum and no grid point is needed for the proof.

## Model and seen pieces (Lean `lean/Fw/Measure/SimHost.lean`)

A pass attempt is reconnect, tab wait, load and census (the head), then the scroll step (tries, each with its reconnect), then for the try that ends the step the rest of the pass (seek with its four navigations, load stamp).

| Piece (green jobs, from the step start) | Seen max (s) | Job (run) | n |
|---|---|---|---|
| head: attempt start (or the failure before it) to the scroll step, or to the attempt's failure | 687 | 121416196352 (40271367353) | 204 attempts, 6 failed in the head |
| scroll try (reconnect included for a retry), and for the try that ends the step, on to the pass end | 876 (51 + seek 825) | 121314777043 (40236465002) | 198 ended steps, 12 failed tries |
| wk-sim-hang scroll retry (failure to retried step end), the deployed scroll need | 589 | 121153604305 | 13 |
| wk-sim-hang pass retry (failure to repeated pass end), the deployed pass need | 436 | 121416196352 | 3 |

- `runPass` carries the tab gate as a model term (not deployed): a navigating attempt whose tab wait does not fit stops failed at the end of its reconnect (`runPass_tab_refused`).
- With a 480 s tab need the pass need is below it (`ci_tab_need`: 436 < 480), so `tab_refused_no_pass_retry` does not apply: after a tab refusal between 1560 s and 1604 s a pass retry could be admitted that the model stops. Model limit for a later wait cap.
- In one 35 min session a scroll retry is admitted until 1451 s into the step and a pass retry until 1604 s (`last_admitted`); after the longest start and warm-up seen (1021 s) both fit (`retry_after_warm`).

## TS

- `sim-host.mjs` reads every constant (`endMarginS`, `loadCeilCenti`, `scrollNeedS`, `passNeedS`, `navWaitMs`) from `packages/contracts/golden/measure/sim-host.jsonl`; no need is typed in TS. `tabNeedS`, `tabFits` replay the golden's `tab` vectors (`test/sim-host.test.mjs`); no code calls them.
- `wip.mjs` `navigateTab` has no tab gate (deployed tab need 0): a tab wait is started at any point of the step.
- `replay.mjs` is an analysis script.

## Replay (`results/sim-retry-needs/scripts/`)

`fetch.py` downloads the logs, `pieces.py` extracts per job the pass attempts and every gate decision (scroll retry, pass retry, tab wait) with its time from the step start, `lean_data.py` writes the `jobs` block of `SimHostGolden.lean` from `pieces.json` (`--check` compares), `replay.mjs` runs the package's `afterFailure` and `tabFits` on the decisions. Decisions: 12 scroll retries, 8 pass retries (18 jobs), 889 tab waits. Every job ran one session (bound 2040 s).

| Arm (`replay.json`) | Refused | Scroll | Pass | Tab |
|---|---|---|---|---|
| `deployed`: shipped (589, 436), tab gate (not deployed) | 10 | 1 | 0 | 9 |
| `deployedNoTab`: shipped, no tab gate (deployed) | 1 | 1 | 0 | 0 |
| best (876, 1563, tab gate) | 14 | 2 | 7 | 5 |
| best, no tab gate | 9 | 2 | 7 | 0 |
| best, clock from the "serving" line | 13 | 1 | 7 | 5 |

Refused by the shipped needs with a tab gate, arm `deployed` (job, run, gate, seconds into the step); the deployed gates refuse only the scroll one: 120992312974 (40134016822, tab, 1618), 121051706071 (40153925235, tab, 1696), 121058900267 (40153925235, tab, 1680), 121060093155 (40156393010, scroll, 1467), 121153583929 (40171953359, tab, 1847), 121153590507 (40171955521, tab, 1575), 121153604305 (40171941566, tab, 1648), 121279958654 (40196209240, tab, 1582), 121279959618 (40196209240, tab, 1561), 121416196352 (40271367353, tab, 1566).

## Open

- Lead decision: the tab gate is dropped (it would refuse 9 green jobs). A tab wait capped to the time left is a follow-up.
- The wk-sim-hang note's Lean paragraph is outside this task's writes (follow-up).
- `perSessionMin` unchanged.
