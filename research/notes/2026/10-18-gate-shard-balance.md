---
title: Why breakpoint-gate run 39101532038 took so long, and the settle-budget plus LPT-shard redesign
date: 2026-10-18
status: MEASURED
---

# Breakpoint-gate shard balance (gate-shard-balance)

Question (user): why did breakpoint-gate run 39101532038 (job 117598896525) take so long, and can we fix it with a
revised design that is proved in Lean?

## Answer first
- **Root cause (MEASURED, run 39101532038):** the settle wait had no frame budget, only `timeoutMs` 30000. It waits
  until the roots of all 33 parts are still, and some part is always moving (marquees, carousels, the countdown).
  Result: 312 of 392 arm samples per engine waited the full 30 s. The mount ready idle wait also ran to its 20 s cap.
  The desktop jobs, which hold the 57-stop desktop sweep, took 45.8 min (Chromium) and 49.8 min (WebKit).
- **Fix 1, settle frame budget (commit 088315d, Lean `Fw.Gate.Settle`):** stop after 60 frames
  (`wait_stops_by_frames`). Fold the bounded mount idle wait into the sample, so a sample that is still moving is never
  a pass (`fold_unsettled_never_pass`, which reuses `unsettled_never_pass`). This cut the total from 212.4 to 65.5
  job-minutes. The per-cell verdicts are equal to the baseline.
- **Fix 2, LPT shard plan over measured costs (commit 0549eaa, Lean `Fw.Gate.Shard`, `ShardCosts`, `ShardObs`):**
  each probe and each whole sweep is a unit, with its cost measured in run 39106417480. The units are dealt longest
  first onto the least-loaded job, and the number of jobs comes from Graham's bound for the free-runner pool. The
  workflow's planner (`gate-jobs.mjs --params measured`) only passes on the Lean jobs from
  `golden/gate/shards.jsonl`.
- **The floor is the WebKit desktop sweep** (57 stops × 2 arms, about 647 s, about 696 s with setup). A sweep cannot
  be split, because each stop's verdict depends on the collapsed history before it (sweeps-speed note). So no plan
  beats about 11.6 min wall time per run on WebKit.

## Evidence (MEASURED)
| run | commit | design | jobs | job-minutes | gate wall (first job start → last job end) |
|---|---|---|---|---|---|
| 39101532038 | site baseline | no frame budget, k = (3+desktop, 4+desktop) by the old deal | 7 | 212.4 | ~50 min (desktop jobs) |
| 39106417480 | 088315d | frame budget 60, old deal | 7 | 65.5 | 18.9 min (07:08:56 → 27:51; starts queued behind other workflows) |
| RUN2 | 0549eaa | frame budget 60, LPT k = (2, 4) | 6 | RUN2MIN | RUN2WALL |

Per job, run 39101532038 → 39106417480 (min): Chromium 29.3 / 24.1 / 45.8 (desktop) → 6.2 / 5.7 / 6.6; WebKit
21.6 / 20.8 / 21.0 / 49.8 (desktop) → 12.4 / 12.1 / 11.05 / 11.5.

RUN2JOBS

Per-cell verdicts: same in all three runs (504 cells per engine; Chromium 4 fail, 68 pass, 432 not-comparable;
WebKit 2 fail, 70 pass, 360 not-comparable, 36 unreachable:primary-pair, 36 unreachable:whole-width). Both runs
conclude `failure` because of the same failing cells. RUN2CELLS

Run 39106417480 measurements behind the cost table:

| | Chromium | WebKit |
|---|---|---|
| per-probe weight (Σ arm waits) | 4.4–16 s | 4.2–77 s |
| unsettled frames, ms per frame | 19–70 | 40–630 |
| settled samples, longest wait | 850 ms | 32.8 s (at 3 frames) |
| desktop sweep, settle-wait sum | 296 s | 535 s |
| desktop sweep wall / plus setup | 347 s / ≈398 s | 647 s / ≈696 s |

A time cap instead of a frame budget would change WebKit outcomes: settled WebKit samples take up to 32.8 s, because
a frame there can take up to 630 ms under concurrency 4. The frame budget bounds the work without depending on the
wall clock.

## Design
1. **Cost table** (`Fw.Gate.ShardCosts.reduce`, data in the generated `ShardObs.lean`): for a job $j$ with probes $P$
   and concurrency 4, $\mathrm{over}(j) = (4 \cdot \mathrm{probeWall} \mathbin{∸} \sum w) / \max(1, |P|)$ and
   $\mathrm{cost}(p) = \lceil (w_p + \mathrm{over}) / 4 \rceil$. A sweep costs its measured wall. Setup is the mean job
   setup (Chromium 38.1 s, WebKit 49.7 s). `probeCost_cover`: the probe costs cover the measured probe wall. A unit
   with no measurement gets the default, which is the largest entry (`costOf_missing`, `costOf_le_dflt`).
2. **Plan** (`Fw.Gate.Shard.lpt`): sort units by cost, longest first, with ties broken by index. Then put each unit
   onto the first job with the least load. Theorems: `plan_partition` (every unit lands in exactly one job, as a
   permutation), `plan_makespan_bound` (Graham: $k \cdot \max \le \sum + (k - 1) \max_u c(u)$),
   `plan_deterministic` (the same units in any order give the same plan), `plan_verdict_eq` (the merged per-cell
   verdict is the unsharded verdict for every plan), `plan_valid` and `chosen_valid` (the probes and whole sweeps are
   all covered).
3. **Choice of k** (`chooseK`, `chooseK_spec`, `shardBound_sound`): over $k_c, k_w \in [1, 8]$, minimise the bound
   $r \sum D + (m - 1) \max D$ on $m \cdot$ the makespan of $r$ concurrent runs on $m$ free runners.
4. **Glue**: `gate-jobs.mjs` reads `shards.jsonl` and filters it to the scope; `check.sh` runs
   `ShardGolden --check`; `gate-jobs.test.mjs` re-checks coverage and Graham's bound for every golden line.

## Lessons
- A settle wait needs a frame budget, not only a time cap. A page with a permanent animation never becomes still, so
  a time-only wait always uses its whole cap (here 30 s × 312 samples).
- With the waits bounded, the critical path is the largest unit that cannot be split, not the number of jobs. Plan
  jobs by measured cost, and stop adding jobs once each job reaches that floor.

## Open
- The WebKit desktop sweep is the floor. To lower it, either lower the frame budget (each WebKit frame is 40–630 ms
  under concurrency 4) or run that sweep at concurrency 1. Each needs a new verdict comparison.
- The cost table comes from one run. Regenerate `ShardObs.lean` with `scripts/shard-obs.mjs` after any harness
  change.
