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
| 39110348835 | e475bc6 (0549eaa + main) | frame budget 60, LPT k = (2, 4) | 6 | 65.1 | 12.2 min (08:10:23 → 08:22:35); whole run 14.2 min |

Per job, run 39101532038 → 39106417480 (min): Chromium 29.3 / 24.1 / 45.8 (desktop) → 6.2 / 5.7 / 6.6; WebKit
21.6 / 20.8 / 21.0 / 49.8 (desktop) → 12.4 / 12.1 / 11.05 / 11.5.

Run 39110348835 (workflow_dispatch on ci/gate-shard-balance, default inputs `runs 2, free 8, times measured`, all 33 parts,
both engines, `ubuntu-24.04-arm` jobs), per job in minutes:

| job | start | end | min |
|---|---|---|---|
| gate chromium j0 | 08:10:23 | 08:19:02 | 8.65 |
| gate chromium j1 | 08:10:24 | 08:19:19 | 8.92 |
| gate playwright-webkit j0 | 08:10:23 | 08:22:35 | 12.20 |
| gate playwright-webkit j1 | 08:10:23 | 08:22:08 | 11.75 |
| gate playwright-webkit j2 | 08:10:24 | 08:22:06 | 11.70 |
| gate playwright-webkit j3 | 08:10:24 | 08:22:16 | 11.87 |

The 6 gate jobs sum to 65.1 job-minutes (66.8 with guard 8 s, site build 45 s and merge 50 s). Gate wall is 12.2 min
(first gate job start 08:10:23 → last gate job end 08:22:35); the whole run is 14.2 min (created 08:09:16, ended
08:23:30). Queue time is separate: guard started 6 s after creation and the gate jobs started 1 s after `site` ended,
so the run never waited for a runner (I cancelled the other workflows my push had started, so the pool was free).
Against 39106417480: job-minutes 65.5 → 65.1 (the same work, so equal as expected), gate wall 18.9 → 12.2 min, of
which about 11.6 min is the WebKit desktop sweep floor. The four WebKit jobs end within 0.5 min of each other, so the
LPT deal is balanced to the floor; Chromium (k = 2) ends 3.3 min before WebKit and is not the critical path.

Per-cell verdicts: same in all three runs (504 cells per engine; Chromium 4 fail, 68 pass, 432 not-comparable;
WebKit 2 fail, 70 pass, 360 not-comparable, 36 unreachable:primary-pair, 36 unreachable:whole-width). Both runs
conclude `failure` because of the same failing cells. Run 39110348835 against both baselines, compared cell by cell on `summary.json`
(504 cells per engine, `scratchpad` script `cmp.mjs`): **WebKit: 0 differing cells. Chromium: 502 of 504 equal, 2
differ** in the failing count, not in the verdict class: `commission` × `desk-rm` and `hero.orbit` × `desk-rm` are
`fail` in all three runs, with 1 failing probe of 30 in the baselines and 2 of 30 in run 39110348835. Reason
(INFERRED): both are timing-sensitive probes, not caused by the shard plan. Commission margins are known intermittent
(`docs/team/handoffs/integrate-ports.md`: a different probe fails each run; here desk-rm-1280 in the baselines,
desk-rm-1279 and desk-rm-1511 now, orig 15.5 px) and the hero.orbit card z-index also moves with the animation phase
(desk-rm-860 in the baselines, desk-rm-860 and desk-rm-861 now). The plan only chooses which job runs a probe;
`plan_verdict_eq` says the merged verdict is independent of that choice.

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

## Round 2: a frozen page clock in both arms (MEASURED, CI runs 39115860145, 39115867180, 39116538316 on d9a6744)
Threat model: the gate must never report pass while a compared state was not compared (unsettled, missing, not comparable).
- **Why the baselines were not a result:** in 39101532038 and 39106417480, 312 of 392 samples per engine (79.6%) were
  unsettled, so the gate compared frames whose time was the machine's. Round 1's engine verdict ignored that (blocker, fixed
  in 5107fcc: the verdict counts unsettled from the Lean settle wait, probes and sweep stops, missing = unsettled;
  `Fw.Gate.Exit`, `exit.jsonl`).
- **Frozen clock (`Fw.Gate.Freeze`, `src/freeze.mjs`, `page.mjs` KIT_SRC):** Playwright `page.clock` is installed paused before
  load in both arms and both engines and moved only by the harness (16 ms per frame). Before every observation the document's
  finite animations are finished and infinite ones paused at the middle of the first iteration. The compared set did not change.
  Under the frozen clock `t = 16 * frames`, so the 60-frame budget decides (`spent_frozen_frames`), the wait depends only on the
  first 62 steps (`wait_frozen_agree`), and a real clock gives machine-dependent outcomes where the frozen one does not
  (`real_clock_machine_dependent`, `frozen_machine_independent`). `freeze_independent_of_elapsed`, `freeze_idem`,
  `runCount_freeze`, `settled_frozen_anims`: the frozen state does not depend on how long the machine took. `alignTarget_eq`,
  `stop_stays_in_cell`, `harness_grid_fits`: both arms leave every sweep stop at the same fake instant.
- **Settled ratio (MEASURED, 3 runs x 2 engines):** 392 of 392 samples settled (0 unsettled, 0 missing) in all 6 engine results;
  waits are 3 frames, 48 ms of fake time in Chromium. Baselines: 80 of 392 (20.4%).
- **Wall and cost (run 39116538316, the other two within 0.2 min):** gate wall 5.0 min (first gate job 09:45:50, last end
  09:50:52); whole run 7.1 min; guard started 6 s after creation, so no queue. 25.9 job-minutes in 6 gate jobs (Chromium 2.4 and
  3.5; WebKit 4.9 to 5.0 each). Round 1 on 33 parts: 12.2 min wall, 65.1 job-minutes. The part sets differ (main has 15 parts,
  252 cells per engine), so the numbers are not a like-for-like speed-up; the like-for-like check is main's own gate run
  39102911533 (same 15 parts).
- **Per-cell verdicts against main 39102911533 (same 15 parts):** Chromium 252 cells, 0 differ (251 pass, 1 not-comparable).
  WebKit 252 cells: 12 differ, all `fail` on main and `pass` now: hero.countdown (desk, touch, touch-rm, phone-landscape,
  dark; `will-change` auto vs transform on `face`) and hero.exit (desk, touch, touch-rm, phone-landscape, dw-arm-isolate, dark,
  sweep touch-1024-1201; `will-change`, and `copy`/`cue` opacity 0 vs 1, filter blur(18px) vs 0 at desk-861). Reason (INFERRED
  from the values): those were frames read while an exit or tween was in flight in one arm; with both arms at the same
  frozen instant and the animations finished they agree. They are real-time differences between the arms, not a missing
  comparison. One WebKit cell stays `fail` in every run and on main: platform.stageBg x sweep desktop-1512-320-1512 (13 of 57
  stops, stage and grain height 351.8 vs 319.6 px at 481 to 320 wide), so it does not come from the clock.
- **The 2 new Chromium cells** (`desk-rm-861` hero.orbit, `desk-rm-1279` commission) belong to the 33-part set. Main has 15
  parts, so they cannot be reproduced here; integrate-ports-3 brings them. Baselines 39101532038 and 39106417480 (36 rows) have
  no common-cell pass/fail meaning for 15 parts except that none of the 15 parts' cells is a failing one there.
- **Confounds to read with these numbers:** Chromium moved from puppeteer-core to playwright-core (same Chrome, same CDP
  emulation), so a Chromium difference could come from either change; none appeared against main. The gaps lane keeps its native
  timing. Frozen time is a different state from "after N real seconds": a bug that only shows at a particular real time is not
  reachable by this gate.
- **A bug the first two runs found (39114796757, 39114847922, commit b70291b):** main's anchors had no `kind` on the
  morph.countdown and morph.columns mount steps, so the original panel never mounted and 13 failing rows read 0 original nodes. The runner
  now refuses an unknown prepare kind and `test/prepare.test.mjs` checks every step.

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
