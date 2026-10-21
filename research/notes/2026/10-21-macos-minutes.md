---
id: 2026-10-21-macos-minutes
kind: note
title: "macOS minutes, 2026-10-20 11:37 to 10-21 12:05 UTC: 1,118 job-min (~1,095/day, an upper bound), 82 % from dispatches; after the check, the plan saves ~35-55 job-min/day firm, plus up to ~115 on diagnostic trajectory series"
status: review
created: 2026-10-21
topics: [ci, macos, github-actions, webkit-sim, trajectory-probe, slots, circleci, pool]
---

# macOS minutes: where they go, what is saved, what to cut next

User 2026-10-21: "do we have any tasks that consider about this optimization ?" This note writes up the lead's
investigation: a measure job (window below), a synthesis, and an adversarial check of the synthesis. **The check's
corrections and verdicts are binding.** Where it corrects the synthesis, this note follows the check.

**User decision (2026-10-21): macOS-minute experiments run on GitHub Actions only, with no CircleCI spend. Savings
measured on GitHub are assumed to carry over to CircleCI.** For this public repo GitHub minutes are free. What a macOS
job-minute costs is slot time: 5 concurrent macOS jobs per account, so one burst makes the other lanes wait.

## Answer

- **Where the minutes go (MEASURED, table lanes).** 94 macOS jobs used 1,117.8 job-min in 24.5 h, about 1,095/day.
  trajectory-probe used 623.8 (56 %) and webkit-sim 494.1 (44 %). The other five macOS lanes used 0. **Dispatches used
  914.0 of 1,117.8 job-min (82 %)**: trajectory-probe 588.6, webkit-sim 325.4. Dispatches skip the trigger guard by
  design (`.github/scripts/changed-inputs.mjs:221@409ad8e4`), so only the dispatcher can cut them. 223.1 job-min (20 %)
  did not succeed. In webkit-sim that was 185.0 of 494.1 (37 %).
- **~1,095/day is an upper bound, not a steady rate (INFERRED).** Most of the window's traffic came from work that has
  since finished:
  - The 3 six-cell webkit-sim dispatches were ci/webkit-lag-probe, which landed at 8b768018 (10-21 01:27 UTC).
  - Most of the webkit-sim push runs (168.7 min) were webkit-sim-failfast's own test pushes.
  - The 12-run ci/scoped-close-start-cause series (273.55 min) was 2 fresh runs plus the lead's 10 queued runs for a
    5-vs-5 permutation test (docs/team/handoffs/scoped-close-start-cause.md:3,21).
- **Width coverage of trajectory dispatches (MEASURED, table widths).** 31 of the 33 apple dispatch runs walked all
  four widths. Only 39504209400 and 39542978747 ran a subset.
- **What is already saved (table saved).** The intent guard and the main-push change cut the rate from ~4,000 to
  ~390 job-min/day before this window (INFERRED: the lead's replay, data not committed). The rate rose again with new
  dispatch work. webkit-sim-failfast, the exit watchdog and pool-caps already cover hangs. The 55-min hang in this
  window (class a) is from before failfast and is fixed on main.
- **Ranked plan after the check (table plan; job-min/day at the window's rate, all upper bounds):**

  - Rank 1, traj-dispatch-scope: <= ~115. Scope diagnostic runs only; verdict runs save 0.
  - Rank 2, webkit-sim-target-lost: ~20-30. Bound the page-target-lost wait at 480 s and relaunch once (a new
    SimBound class).
  - Rank 4, macos-teardown-trim: ~15-25. Skip the Simulator shutdown on a discarded VM, collect host state only on
    failure, cache iwdp.
  - Rank 6, folded into pool-fallback: 0 GitHub min. Review input: charge m4pro at an enforced m4pro timeout.
  - Rank 7, pool-raw-cache: ~0 today. Parked until a traffic trigger.
  - **Dropped:** rank 3 (folding cells for the existing lanes; kept only as a spec rule for smoothness-webkit-cadence)
    and rank 5 (series admission). Rank 3 breaks the 38-min job cap and the vms-3 sample. Rank 5 fails because the
    series bore its own wait.
  - **Totals:** ranks 2 and 4 save ~35-55/day firm (3-5 % of ~1,095). With diagnostic scoping, up to ~35-170/day
    (3-16 %). The synthesis claimed 190-260; the check refuted that.

Tables: every table below is the verbatim output of `node research/notes/2026/macos-minutes/tables.mjs` (Node 24.22.0, run from the repo root). `node
research/notes/2026/macos-minutes/tables.mjs --check` exits 0 only if each generated block appears in this note byte
for byte. Inputs are in `research/notes/2026/macos-minutes/`:
- `jobs.json`: the 94 macOS jobs with steps, from the measure job's telemetry rows and `gh run view --json jobs`.
- `circleci.json`: CircleCI Insights runs and per-job totals.
- `facts.json`: hand-entered classes, the plan and the earlier savings, each with its source.

All three are copies of uncommitted scratch data, with no paths, actors or session ids. Minutes are sums of whole
seconds of job wall (startedAt to completedAt), rounded half up to 0.1 min.

## 1. Where the minutes went (window 2026-10-20 11:37 to 2026-10-21 ~12:05 UTC, 24.5 h)

Coverage (from the measure job):
- Runs: `gh run list` per macOS workflow.
- Jobs: the telemetry store (`.fw-console/timings.jsonl`, written by apps/runner/src/ci-telemetry.ts) plus 31 `gh run
  view --json jobs` calls.
- Not seen: macOS jobs of other repos on the same account, and attempt-1 jobs that the store overwrote. Only 2 runs
  have attempt > 1: 39459660693 and 39466179818.

<!-- generated: tables.mjs lanes -->
| lane | runs | jobs | job-min | share | dispatch job-min (share) | push job-min | non-success jobs / job-min (share) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| trajectory-probe | 39 | 67 | 623.8 | 56 % | 588.6 (94 %) | 35.2 | 4 / 38.2 (6 %) |
| webkit-sim | 12 | 27 | 494.1 | 44 % | 325.4 (66 %) | 168.7 | 9 / 185.0 (37 %) |
| wktr, wktr-fixtures, engine-premises, gate-gaps, sim-speed | 0 | 0 | 0.0 | 0 % | 0.0 | 0.0 | 0 / 0.0 |
| **all** | 51 | 94 | 1117.8 | 100 % | 914.0 (82 %) | 203.8 | 13 / 223.1 (20 %) |
| all, per day (x 24 / 24.5 h) |  |  | 1095.0 |  | 895.4 |  |  |

MEASURED. Every count comes from jobs.json, which lists the run id and job name of each row. 47 rows also carry the
job id.

<!-- generated: tables.mjs widths -->
| trajectory-probe dispatch runs with apple jobs | runs | jobs | job-min | subset runs (widths) |
| --- | --- | --- | --- | --- |
| two legs 390_641 + 640_1280: all four widths (MEASURED, job names) | 24 | 49 | 544.1 |  |
| one job, step 'Walk the hero path (both arms, every width)': all four (INFERRED, step name) | 7 | 7 | 26.2 |  |
| a subset of the widths (MEASURED, job names) | 2 | 3 | 18.3 | 39504209400 (390+1280), 39542978747 (390) |
| **all four widths: 31 of 33 runs** | 33 | 59 | 588.6 |  |

Single-job runs are counted as all four widths because of their step name, `Walk the hero path (both arms, every
width)`, so that row is INFERRED.

<!-- generated: tables.mjs series -->
| group | runs | jobs | job-min | job-min/day at the window rate | median job |
| --- | --- | --- | --- | --- | --- |
| all dispatch runs on ci/scoped-close-start-cause | 12 | 24 | 273.6 |  |  |
| the queued runs (5-vs-5 permutation test) | 10 | 20 | 227.5 |  |  |
| saved had each queued run walked one leg (drop its shorter .. longer leg) | 10 | 10 | 110.7 .. 116.8 | 108 .. 114 | 11.5 min |

The series row is MEASURED. The exact sum is 16,413 s = 273.55 min; the measure job printed 273.5. The saving row is
INFERRED: it assumes each queued run walked one leg. The check rounds it to **<= ~115/day**.

<!-- generated: tables.mjs wait -->
| jobs | count | external wait job-min, every wait (share of all) | external wait job-min, waits > 120 s (share of all) |
| --- | --- | --- | --- |
| all macOS jobs | 94 | 478.9 (100 %) | 454.3 (95 %) |
| the queued series runs | 20 | 406.8 (85 %) | 405.0 (85 %) |
| every other job | 74 | 72.1 (15 %) | 49.4 (10 %) |
|   of which webkit-sim | 27 | 20.2 (4 %) | 13.9 (3 %) |
|   of which inside the series' span (first queued run created .. last series job end) | 74 | 6.4 (1 %) | 6.4 (1 %) |

External wait is MEASURED as wait minus same-matrix wait; how it splits into cap and provisioning is INFERRED.
- The queued series bore its own wait: 85 % on both bases. The check's 405.3 sums the rounded per-job list minutes
  (405.0 here).
- Other jobs waited ~72-74 min: 72.1 across all their waits, or 478.9 - 405.3 = 73.6 in the check.
- Only 6.4 min of that wait fell inside the series' span (webkit-sim run 39511908073, cells v3 and r3).

So a per-series slot cap moves almost no waiting off other lanes, and rank 5 is dropped.

<!-- generated: tables.mjs concurrency -->
| macOS jobs running at once | 1 | 2 | 3 | 4 | 5 | 6 |
| --- | --- | --- | --- | --- | --- | --- |
| minutes | 210.4 | 204.8 | 16.1 | 19.9 | 71.3 | 2.3 |

MEASURED: the peak was 6 concurrent macOS jobs for 2.3 min, against the stated account cap of 5. The cause is not
known. It may be how the cap counts, or 1 s timestamps plus overlap while runners are provisioned. It stays open under
pool-fallback.

## 2. webkit-sim's lost minutes, split by cause (the check did the split; it is no longer a task)

<!-- generated: tables.mjs lost -->
| class | jobs (run cell min) | jobs | job-min | state | tag |
| --- | --- | --- | --- | --- | --- |
| (a) pre-failfast hang (Keep-logs held by a wedged CoreSimulator) | 39426562165 v1 55.0 | 1 | 55.0 | fixed on main: 056de8de bounded steps + job cap | MEASURED |
| (b) deliberate fault runs (webkit-sim-failfast tests) | 39444758495 v1 13.2; 39447914983 v1 9.9; 39459660693 v1 7.7 | 3 | 30.7 | keep: requested | MEASURED |
| (c) page target lost, proxy and socket up | 39503100190 r2 34.5; 39503100190 v3 22.8 | 2 | 57.3 | open: webkit-sim-target-lost | MEASURED |
| (d) Keep-logs 3-min timeout after good sessions | 39503100190 r3 14.8; 39511908073 r2 13.0; 39530935381 r3 14.2 | 3 | 42.0 | open: macos-teardown-trim | MEASURED |
| **all non-success** |  | 9 | 185.0 of 494.1 |  |  |

MEASURED from step data, plus two failed-step logs (jobs 118915144635 and 118917087975 of run 39503100190):
- **(a)** Run 39426562165 hung in the Determinism sessions step, before failfast existed. Fixed on main: commit
  056de8de (bounded log and shutdown steps, landed via 6c9d13ec on 10-20 17:24 UTC) plus the job cap
  (`.github/workflows/webkit-sim.yml:271@409ad8e4`). The step comment at `webkit-sim.yml:407-409` names this run.
- **(b)** Deliberate fault runs; keep them. The exact sum is 1,844 s = 30.73 min. The check's 30.8 adds the rounded job
  minutes 13.2 + 9.9 + 7.7.
- **(c)** The inspector lost the page target while the proxy and socket stayed up. In r2 the log shows
  `Runtime.evaluate timed out after 120000 ms`, then `waiting for the Safari tab (876 s of 480 s, try 1): no page
  target`. In v3 there were four tab waits, up to 487 s of 480 s. Failfast does not catch this class: it watches for a
  dead proxy or a dead Safari.
- **(d)** In these jobs the `Keep logs and host state` step ran into its 3-min timeout (188-189 s) after the sessions
  had passed, so the cell failed. The step's `cp` (`webkit-sim.yml:418@409ad8e4`) had already saved the result. In
  39503100190 and 39511908073, merge and lag-report were then skipped. 8b768018 later made lag-report run on partial
  sessions.
- **Dropped:** the synthesis proposed a stop rule, "skip queued sibling cells after a harness-error exit". In every
  failing dispatch the sibling cells succeeded (e.g. v1, v2 and r1 of 39503100190), so the rule would throw away good
  measurements (MEASURED).

## 3. What earlier work already saved

<!-- generated: tables.mjs saved -->
| change | state | saved | its lanes' job-min in this window | tag |
| --- | --- | --- | --- | --- |
| intent guard cb11bf12 + main push runs only the seeder 14a17b94 | on main | rate ~4,000 -> ~390 job-min/day (10-17/18 vs 10-18..10-20); webkit-sim 375 min of the old window would not start | - | INFERRED: lead's replay of 10-17..10-20, data not committed |
| exit watchdog 9e5641cd | on main | ~150 min of hangs after a result in the 10-20 v2 window | - | INFERRED: 1 job measured, 4 inferred (lead's replay) |
| webkit-sim-failfast 056de8de | on main | fault runs end 63-159 s after the kill instead of 26-66 min; class a below is the pre-failfast case | 494.1 | MEASURED: 63 s in run 39459660693 (handoff webkit-sim-failfast.md:20-21); 63-159 s over 39447914983, 39444758495, 39459660693 per the lead synthesis |
| pool-caps (webkit-sim cap 38 min) | on main | 285 job-min per 3 days with fail-fast, replayed at 10-17..10-20 traffic; not seen in this window | 494.1 | INFERRED: replay, not measured here |
| sim-speed | done | 0 (host-bound; xlarge rejected as paid; pre-boot no gain) | - | MEASURED: research/notes/2026/10-17-sim-speed.md |
| wktr-fixture-speed | done | wall 45 -> 24 min, job-min unchanged | 0.0 | MEASURED earlier; lane idle in this window |
| pool-fallback, ci-route | open | 0 GitHub job-min (they cut waiting) | - | INFERRED |

The rows tagged INFERRED come from the lead's replay of 10-17..10-20. This note does not re-derive them because that
data is not committed.

## 4. Ranked plan after the check

<!-- generated: tables.mjs plan -->
| rank | change | check verdict | task | job-min/day (upper bound) | tag / basis |
| --- | --- | --- | --- | --- | --- |
| 1 | scope diagnostic trajectory dispatches to the widths their question needs; verdict runs walk all four | adjust | traj-dispatch-scope | <= ~115 | INFERRED: the one diagnostic series run as one leg (table series); 0 for verdict runs |
| 2 | bound the page-target-lost wait at 480 s and relaunch once (SimBound class) | adjust | webkit-sim-target-lost | ~20-30 | INFERRED: class c plus the ~8.5 extra min of class d (check) |
| 3 | fold webkit-sim cells into fewer booted jobs (existing lanes) | drop | - (spec rule for smoothness-webkit-cadence) | 0 | CONFIRMED: 3 cells ~41.7 min > 38-min cap; breaks vms 3 |
| 4 | trim webkit-sim teardown/setup; keep the cp that feeds the upload | keep | macos-teardown-trim | ~15-25 | INFERRED: table teardown |
| 5 | cap the slots of one dispatch series | drop | - (fold into pool-fallback/ci-route) | 0 | MEASURED: the series bore its own wait (table wait) |
| 6 | charge m4pro at an enforced m4pro job timeout, not at p90 | adjust | pool-fallback (review input) | 0 | CONFIRMED: pool-fallback title; 0 GitHub min |
| 7 | replay cached raw artifacts for push runs | keep parked | pool-raw-cache | 0 | INFERRED: ~0 today (push repeats were requested); <= ~134 at 10-18..10-20 traffic, not re-derived |
|  | **firm (ranks 2, 4)** |  |  | ~35-55 | 3 % - 5 % of 1095/day |
|  | **with diagnostic scoping** |  |  | ~35-170 | 3 % - 16 % of 1095/day |

- **Rank 1, traj-dispatch-scope (adjust).**
  - Mechanism: the plumbing already exists (CONFIRMED). `fw run --trajectory --widths` sets the widths
    (apps/runner/src/run.ts:54,355@409ad8e4). Lean has `pickWidths` (lean/Fw/Gate/Trajectory.lean:691@409ad8e4) and
    `legTable`/`legs` (:2820-2826). Run 39504209400 already used it. The task adds a dispatch policy and a check, not
    new plumbing.
  - Scope limit: a stored run gives no verdict unless all four widths are present. `outcome` returns
    `.unjudged .widths` (:2951), and `outcome_widths` (:2961) proves it. So only runs marked diagnostic may pass a
    nonempty subset of the widths. Verdict runs always walk all four.
  - Slots: a run takes 1 slot only when its widths fall within {390,641} or within {640,1280} (`legTable`/`legs`,
    lean/Fw/Gate/Trajectory.lean:2820-2826@d72e6153; `plan_webkit_apple`, :2906, covers only the all-widths case). scoped-close-start-cause's question named 390, 640 and 641, so it would still need both legs
    (INFERRED). Its 108-114/day is the ceiling, not an expectation.
  - Kept: REPS 5 per leg (`.github/workflows/trajectory-probe.yml:546@409ad8e4`).
- **Rank 2, webkit-sim-target-lost (adjust).** Bound the page-target-lost wait (class c) at its 480 s and relaunch once,
  as a new class in Fw.Measure.SimBound. Saves ~20-30/day (INFERRED, the check: class c plus the ~8.5 extra min of class
  d). The teardown table measures that extra at 8.3 job-min.
- **Rank 3, cell fold (drop for the existing lanes).**
  - It breaks the job cap: 3 cells x 751 s median measurement + ~250 s of setup and teardown = ~41.7 min, over the
    38-min cap (`webkit-sim.yml:271`) (MEASURED durations).
  - It breaks the cross-VM sample the lag mode asks for: `vms 3` (`webkit-sim.yml:42`; vms 1..3 in
    lean/Fw/Measure/SimPlan.lean:159@409ad8e4).
  - With fewer VMs the class can only come out stricter (`classify_mono`, lean/Fw/Measure/Classes.lean:323@409ad8e4),
    so a smaller sample would look optimistic. The synthesis cited `claim_needs_two`, but that is a WKTR rule
    (lean/Fw/Measure/WktrVariance.lean:212@409ad8e4).
  - Kept only as a spec rule for the new smoothness-webkit-cadence leg: all arms x reps in one booted job, rotated, with
    A/A.
- **Rank 4, macos-teardown-trim (keep).**
  - The VM is discarded after the job: "the runner is discarded" (`webkit-sim.yml:423`), and xcode-27 is a
    GitHub-hosted public image (research/notes/2026/10-17-gha-public-runners.md:25).
  - Per job it saves ~16 s of shutdown/delete (:424-429), ~20 s of host-state collection (keep the unconditional `cp` at
    :418) and ~10 s net of the iwdp install (:318).
  - The table below gives 20.3/day, plus 8.3 job-min of Keep-logs timeouts: ~15-25/day (INFERRED).
  - Overlap: per the binding check, the Keep-logs class-d minutes (~8/day) count in both rank 2 and rank 4, so the firm
    total overlaps by about 8/day (INFERRED).
  - It also removes failure class (d), 3 of the 9 webkit-sim failures.
- **Rank 5, series admission (drop).** The series bore 85 % of the external wait itself (table wait). Any admission rule
  goes into pool-fallback/ci-route. The 6-vs-5 peak is unresolved.
- **Rank 6, pool-fallback review input (adjust; not a new task).** pool-fallback already charges credits at cap + setup
  and proves `never_exceeds_quota` (its graph title). Charging m4pro at its p90 would break that bound, because p90 is
  not an upper bound: the failed m4pro pipeline cost 2,756 credits, 2.7x a good run (table m4pro). Instead, set an
  enforced m4pro job timeout from m4pro's own cap, and charge at that timeout.
- **Rank 7, pool-raw-cache (keep, parked).** ~0 today, because the 7 push runs whose own diff missed the lane inputs
  (93.6 min) were requested repeats (MEASURED by the measure job). Start only after push macOS job-min > 100/day for 3
  days. The 134/day at 10-18..10-20 traffic is not re-derived and stays INFERRED.

<!-- generated: tables.mjs teardown -->
| webkit-sim step | jobs | median s | change |
| --- | --- | --- | --- |
| Keep logs and host state | 18 | 21.5 | kept: cp feeds the upload; host state only on failure() |
| Shut down and delete the Simulator | 18 | 16 | skip: the VM is discarded |
| ios_webkit_debug_proxy (brew install) | 18 | 14 | cache it |
| Boot the Simulator | 18 | 156 | kept |
| Determinism sessions (the measurement) | 18 | 751 | kept |
| trim: 46 s per job x 27 jobs | 27 |  | 20.7 job-min, 20.3/day |
| Keep-logs timeouts: 3 jobs over the median | 3 | 188, 189, 188 | 8.3 job-min |

MEASURED medians over the 18 successful webkit-sim jobs. The trim's per-job seconds come from facts.json
(`teardownTrim`, the check's estimate), so the trim row is INFERRED.

## 5. CircleCI (no spend in these experiments, user 2026-10-21)

<!-- generated: tables.mjs circleci -->
| CircleCI workflow (last 30 days) | runs | credits, run level | credits, insights summary |
| --- | --- | --- | --- |
| webkit-sim | 3 | 4773 | 4773 |
| probe | 60 | 62 | 62 |
| premise-tests | 48 | 724 | 71 |
| **all** | 111 | 5559 | 4906 |
| left of 30000 (of 25000) |  | 24441 (19441) |  |

<!-- generated: tables.mjs m4pro -->
| m4pro webkit-sim pipeline (UTC) | wall s | status | credits |
| --- | --- | --- | --- |
| 2026-10-19 20:17 | 356 | success | 992 |
| 2026-10-19 21:23 | 887 | failed | 2756 |
| 2026-10-19 22:05 | 372 | success | 1025 |

MEASURED from CircleCI Insights (last 30 days, all branches). m4pro has used 0 credits since 10-19. The check re-added
these numbers but did not re-fetch them: 992 + 2,756 + 1,025 = 4,773, and 4,773 + 62 + 724 = 5,559. For premise-tests,
the run-level sum (724) and the Insights summary (71) disagree. This stays **unresolved**; the run-level sum is the
safer figure. The 30,000-credit plan is confirmed; the 25,000 figure is not.

## 6. What not to cut

- **webkit-sim push counts.** A push is already at its minimum: 1 VM, 1 session, 2 passes. Keep the cross-VM matrix for
  the determinism classes (`classify_mono`, Classes.lean:323).
- **trajectory REPS 5 per leg and the apple witness** (trajectory-probe.yml:546). Rank 1 cuts only widths that a
  diagnostic question does not need, never reps.
- **WebKit cadence: >= 5 reps per arm plus A/A** (`minReps`, lean/Fw/Gate/Smooth.lean:410@409ad8e4).
- **Requested repeat pushes, deliberate fault runs, and ci/* runs.** ci/* runs are never cancelled (`ci_never_cancelled`,
  lean/Fw/Ci/Cancel.lean:72@409ad8e4).
- **Already rejected:** paid runners (user rule), pre-boot or clone (no measured gain, 10-17-sim-speed.md), and
  cancel-in-progress (<= ~6 min/day, 10-20-macos-pool-v2.md:68).

## Accepted limits

- The window is one day, dominated by tasks that have since finished, so every per-day rate is an upper bound.
- The CircleCI premise-tests figures, run level vs summary (724 vs 71), stay unresolved.
- The 6-vs-5 macOS concurrency peak stays open (pool-fallback).
- `tables.mjs` is a JS stand-in over copies of uncommitted scratch data. It holds no decision logic. The decisions
  belong in the Lean tasks above.
- Rounding: sums use exact seconds, so three figures differ from the check's, which adds rounded job minutes: class b
  30.73 vs 30.8, the series 273.55 vs 273.5, and the series' wait 405.0 vs 405.3. No conclusion changes.

## What this changes in the plan

- **docs/team/work-graph.json, macOS lanes:**
  - The lead's graph r176 already holds the check's ranks: traj-dispatch-scope (rank 1), webkit-sim-target-lost (rank
    2), macos-teardown-trim (rank 4) and pool-raw-cache (rank 7, parked).
  - This note is their evidence: cite it in each task, together with the generated tables.
  - All four stay GitHub only.
- **pool-fallback:** add the review input from rank 6: charge m4pro at an enforced m4pro job timeout, never at p90.
  Also add the open 6-vs-5 concurrency peak, and the rule that any series admission goes here, not into a new task.
- **smoothness-webkit-cadence (spec):** run all arms x reps in one booted job, in rotated order, with A/A. Do not fold
  cells for the existing webkit-sim lanes (rank 3 dropped).
- **Re-measure:** take the next macOS-minutes window after these tasks land. The per-day rates here are upper bounds
  from one day of finished work.
