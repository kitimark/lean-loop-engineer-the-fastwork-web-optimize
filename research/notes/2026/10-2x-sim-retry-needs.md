# sim-retry-needs: retry needs that meet runPass_stop_le's premise, the tab wait gate, and the replay over green jobs

Date: 2026-10-26. Task `sim-retry-needs` (follow-up of `wk-sim-hang`, note `10-2x-wk-sim-hang.md`). Data: `results/sim-retry-needs/` (`pieces.json`, `replay.json`, `scripts/`). Source of every number: the logs of the 98 green jobs of the wk-sim-hang sample (`results/wk-sim-hang/jobs.json`), downloaded with `gh run view --job <id> --log`. No CI run.

## Answer

- The derived needs are 876 s for a scroll retry and 1563 s for a pass retry (Lean `SimHost.scrollNeedS`, `passNeedS`). They meet `runPass_stop_le`'s premise for every pass head within the longest seen (`needs_meet_premise`, `deployed_stop_le`). The shipped 589 s and 436 s met it for no pass attempt (`shipped_needs_missed`).
- Cost: replayed over the 98 green jobs, the derived gates would have refused 14 jobs (14%): 7 pass retries, 2 scroll retries and 5 tab waits. The shipped needs refuse 1 (job 121060093155, scroll retry at 1467 s). MEASURED (`results/sim-retry-needs/replay.json`, arm `derived` against arm `shipped`).
- In one 35 min session a scroll retry is admitted until 1164 s into the step and a pass retry until 477 s (`last_admitted`). After the longest start and warm-up seen (1021 s) a pass retry never fits (`retry_after_warm`), so on this host the pass retry is close to disabled. That is the price of a bound that holds for the shipped constants. A lower price needs shorter passes (the seek tail is up to 825 s) or a longer step, not a different need.
- The tab wait (`navigateTab`, 60 s times `FW_WK_TIMEOUT_SCALE` 8 = 480 s on CI) is now gated by `SimHost.tabFits`: a wait that would end past the step bound is not started. It has its own term in the model (`PassTry.nav`, `tabS`, the need `tab` of `runPass`). On CI it needs 480 s, so a navigation after 1560 s is refused; 5 green jobs navigated later than that (seek fixtures of pass 2).

## Model and needs (Lean `lean/Fw/Measure/SimHost.lean`)

A pass attempt is reconnect, tab wait, load and census (the head), then the scroll step (tries, each with its reconnect), then for the try that ends the step the rest of the pass (seek with its four navigations, load stamp). The rest of the pass counts towards the try that ends the step: a scroll retry is followed by the seek, so its need must cover the seek too. Before this task it did not.

| Piece (green jobs, from the step start) | Seen max (s) | Job (run) | n |
|---|---|---|---|
| head: attempt start (or the failure before it) to the scroll step, or to the attempt's failure | 687 | 121416196352 (40271367353) | 204 attempts, 6 failed in the head |
| scroll try (reconnect included for a retry), and for the try that ends the step, on to the pass end | 876 (51 + seek 825) | 121314777043 (40236465002) | 198 ended steps, 12 failed tries |
| wk-sim-hang scroll retry (failure to retried step end) | 589 | 121153604305 | 13 |
| wk-sim-hang pass retry (failure to repeated pass end) | 436 | 121416196352 | 3 |

- `scrollNeedS = Seen.tryS` (876), `passNeedS = Seen.headS + scrollNeedS` (1563). The reconnects are inside the measured pieces (the reconnect itself is not logged on its own); the hard reconnect bound of `SimBound` (480 + 320 + 90 s) is not used, since already the Seen-based pass need leaves 477 s.
- `runPass_stop_le` now carries the tab gate: premise `p.reconS + p.tabS + p.baseS + inner ≤ outer`; a navigating attempt whose tab wait does not fit stops failed at the end of its reconnect (`runPass_tab_refused`); `tab_refused_no_pass_retry` shows that, with the tab need within the pass need (`ci_tab_need`: 480 ≤ 1563), the code's pass retry after such a refusal is refused too, as the model's stop says.
- `seen_retries_within_needs`: the wk-sim-hang segments (589, 436) are within the new needs.
- The bound is per pass (one level), not per step: pass 2 after a retried pass 1 can still reach the step bound. The premise holds by construction only for pieces within the Seen maxima; a piece past them (a slower host) leaves the bound, as before.

## TS

- `sim-host.mjs` reads every constant (`endMarginS`, `loadCeilCenti`, `scrollNeedS`, `passNeedS`, `navWaitMs`) from `packages/contracts/golden/measure/sim-host.jsonl`; no need is typed in TS. `tabNeedS`, `tabFits` replay the golden's `tab` vectors (`test/sim-host.test.mjs`).
- `determinism.mjs` uses `SCROLL_NEED_S`, `PASS_NEED_S`; `wip.mjs` `navigateTab` waits `T(NAV_WAIT_MS)` and refuses a wait that does not fit the step clock (`stepGate`, so the seek's navigations are gated too). Without `FW_MEASURE_T0_MS` and `FW_WK_STEP_MIN` (local, phone) nothing is refused.
- TS stand-ins: none.

## Replay (`results/sim-retry-needs/scripts/`)

`fetch.py` downloads the logs, `pieces.py` extracts per job the pass attempts and every gate decision (scroll retry, pass retry, tab wait) with its time from the step start (the `##[group]Run` line of the measure step; `tick.mjs launch` sets `FW_MEASURE_T0_MS` a few seconds later), `replay.mjs` runs the package's `afterFailure` and `tabFits` on them. Decisions found: 12 scroll retries, 8 pass retries (18 jobs), 889 tab waits. Every job ran one session (bound 2040 s).

| Arm | Refused green jobs | Scroll | Pass | Tab |
|---|---|---|---|---|
| derived needs and tab gate (deployed) | 14 | 2 | 7 | 5 |
| derived needs, no tab gate | 9 | 2 | 7 | 0 |
| shipped needs 589, 436 | 1 | 1 | 0 | 0 |
| deployed, clock from the "serving" line (latest possible start) | 13 | 1 | 7 | 5 |

Refused by the deployed gates (job, run, gate, seconds into the step): 120992312974 (40134016822, tab, 1618), 121051706071 (40153925235, tab, 1696), 121058900267 (40153925235, pass, 1092), 121060093155 (40156393010, scroll, 1467), 121082316538 (40162251194, pass, 873), 121153583929 (40171953359, pass, 984), 121153590507 (40171955521, tab, 1575), 121153604305 (40171941566, tab, 1648), 121277247653 (40229095163, pass, 733), 121279958654 (40196209240, pass, 1090), 121279959618 (40196209240, tab, 1561), 121416196352 (40271367353, pass, 1203), 121425683979 (40277972324, scroll, 1167), 121440938424 (40282951274, pass, 624). Job 121425683979 is 3 s past the 1164 s limit and is admitted with the later clock; the other 13 are refused on both clocks.

## Open

- Whether 14% refused green jobs is an acceptable price for the bound is a lead decision. Cheaper options, not built: cap the tab wait to the time left instead of refusing it (the 5 tab refusals were navigations that took seconds); shorten the seek tail; gate per step instead of per pass.
- The wk-sim-hang note's Lean paragraph ("The deployed needs do not meet runPass_stop_le's premise") is outdated by this task; that note is outside this task's writes.
- `perSessionMin` unchanged: no theorem here needs it.
