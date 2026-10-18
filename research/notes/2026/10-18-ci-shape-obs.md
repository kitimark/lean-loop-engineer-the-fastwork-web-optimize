# CI shape observation: imbalance, growth, timeout headroom, queue (ci-shape-obs, 2026-10-18)

Status: the decision is in Lean (`lean/Fw/Obs/CiShape.lean`, op `obs.ciShape`, golden
`packages/contracts/golden/obs/obs.ciShape.jsonl`). The collector, the `fw watch` alerts and the console card are glue.

## Why

Run 39101532038 (b35b541, ci/integrate-ports-3, 2026-10-18 05:43Z) took webkit `j3` 2986 s against 1249-1295 s for
`j0`-`j2`, and chromium `j2` 2749 s against a 3600 s timeout (MEASURED, `gh run view --json jobs`). Nothing told us
before that: the timing spans (`Fw.Obs.Timing`) fold the shards of one job family into one baseline, so a slow sibling
is invisible to them, and nobody tracks a workflow's total job time across runs. This note adds that observation. It
keeps the fix out: the shard plan itself belongs to `gate-shard-balance` (see "Feeding gate-shard-balance").

## What is recorded

`.fw-console/ci-shape.jsonl` (main checkout, gitignored) has one row per finished run x job:

| field | source | note |
|---|---|---|
| run, workflow, branch, sha (7), event, attempt | `gh run view` | |
| createdS | run `createdAt` | used to order runs; stays the same on a re-run |
| startedS | run `startedAt` | the start of the latest attempt (GitHub resets it on a re-run); the queue base |
| job, conclusion | job `name`, `conclusion` | display name, e.g. `gate playwright-webkit j3` |
| startS, endS | job `startedAt`, `completedAt` | a job that never started (zero time) has no row |

The timeout is not stored per row. On every decision, `fw watch` reads `timeout-minutes` from
`.github/workflows/*.yml` (job id to seconds, line-based) and passes it as `params.timeouts`. A job with no entry gets
GitHub's 360 min default.

Collection costs one charged `gh run view <id> --json createdAt,startedAt,attempt,event,headBranch,headSha,workflowName,conclusion,jobs`
per finished run (gh-budget, cost 2, non-blocking: on a budget wait it skips and the next pass retries):

- **Run ids:** these come from the gh poller's cached `runs-status.json`, from the watch snapshot's own CI rows, and
  from the lines `fw ci wait` prints. The collector makes no list call of its own.
- **Skips:** a run is skipped when it is cancelled or skipped, when it is not completed, or when it is already in the
  ledger.
- **Rate:** at most 4 views per pass.

## Sibling groups

The first token of a job name (the job id) goes through an alias table (default `sweeps -> gate`). Then the shard
tokens are dropped: `s`, `j`, `r` or `v` followed by digits. All three names below therefore map to group
`gate chromium`, so one group survives the s-to-j rename and the sweeps merge:

- `gate (chromium, s0)`;
- `gate chromium j0`;
- `sweeps (chromium)`.

The `#guard`s in the module show more cases, such as `counts (original, r1)`, which maps to `counts original`.

## Drift classes (all in `Fw.Obs.CiShape`, Nat seconds, exact rational comparisons)

| class | metric | fires when | default |
|---|---|---|---|
| imbalance | max/mean of the run times of one sibling group (counted jobs: not skipped, not cancelled) | n >= 2, max >= m_s, rho_n * sum < rho_d * n * max | rho = 3/2, m_s = 300 s |
| growth | job seconds of the run (sum over counted jobs) vs the median of the last N runs of the same workflow, any branch | window >= n_min runs, x >= m_j, g_n * p50 < g_d * x | N = 5, n_min = 3, g = 2, m_j = 600 s |
| nearTimeout | run s / timeout s of a job that ran | theta_n * T < theta_d * run | theta = 3/4 |
| queue | job start minus its ready time: the later of the run start and the last end among jobs of another family that ended by its start | queued > q | q = 1200 s |

`ci.shape` alerts are deduplicated per (workflow, class):

- **Raised:** a class is raised on the first run where it fires after a run where it did not.
- **Open:** it stays open while the workflow's newest run fires it. `fw watch` shows open alerts as `ci.shape`, with
  subject `<workflow>/<class>`.
- **Witness:** every alert carries one. Imbalance has the group, its max and its floored mean. Growth has the job
  seconds and the median. nearTimeout has the job, its run time and its timeout. Queue has the job, its estimate and q.

## Thresholds and their basis in the history (backfill of 621 job rows, 2026-10-17 17:49Z to 10-18 06:07Z)

| threshold | value | basis (MEASURED on the backfill unless marked) |
|---|---|---|
| rho | 3/2 | Lean's own plan for the 3 chromium shards gives 267/188 = 1.42 (Fw.Gate.Schedule plan, INFERRED from the gate-speed-ci note); `main` runs measure 1.11-1.42; the integrate runs 1.76 (b35b541 webkit) and 2.30 (ebb1612). 3/2 sits between the planned ratio and the bad runs |
| m_s | 300 s | the old 8-shard layout had max/mean 2.2-3.7 with shards under 6 min (e.g. 56d3f96 chromium 206 s max); a ratio over seconds-long shards costs no wall time |
| g, N, n_min | 2, 5, 3 | normal gate runs cost 1000-2400 job-s; the integrate runs 5271, 7803, 12833, 12887. The median (not the min) ignores a single failed-early run (fb88aa2, 79 job-s) |
| m_j | 600 s | failed-early runs of a few minutes never count as growth |
| theta | 3/4 | the alert must come before the 60 min timeout: 45 min. Measured: chromium j2 2737 s and 2749 s = 0.76; webkit j3 2986 s = 0.83 |
| q | 1200 s | free-runner pickup is usually < 2 min; the tail runs on busy hours were 1496-1992 s |

## Theorems (all `$$` docstrings in the module; standard axioms only)

`imbalance_ge_one`: sum <= n * max, so max/mean >= 1.

`imbalanced_iff`, `growth_iff`, `nearTimeout_iff`, `queued_iff`, `alert_iff`: each class fires exactly on its metric.

`no_alert_on_balanced` and `no_imbalance_on_balanced_run`: with rho >= 1, equal shards never fire.

`growth_of_few_above`: the median cannot hide a jump while at most half of the window was already high.

`growth_within`: suppose the window is a ++ [v] ++ b, with every a <= v and 2|b| <= |w|. Then a run above g * v fires.
In other words, a non-decreasing series that grows by more than g within floor(N/2)+1 runs is caught.

`growth_mono`: a costlier run fires too.

`raised_iff`, `dedup`, `open_iff`: between two raises of one class there is a run where it did not fire.

`caught_before_timeout` and `caught_series`: if a job's run time grows by at most (1 - theta) * T per run, a run
inside T is flagged near the timeout before any run passes T.

`queued_le`: the queue estimate never exceeds the true wait, whatever the `needs` graph.

`imbWitness_spec`: the named group is imbalanced and has at least 2 siblings.

Limits, stated rather than hidden:

- **Slow creep:** growth slower than x g per floor(N/2)+1 runs is not a growth alert. `caught_series` makes
  nearTimeout the absolute backstop for that case.
- **Branch order:** runs of all branches share one window and one order (creation time). An integrate branch
  interleaved with small feature runs therefore raises, clears and raises again. That matches what CI paid for, so it
  is kept.

## Replay over the backfill (fwcore `obs.ciShape`, 621 rows, 1.9 s)

breakpoint-gate (times are run creation, UTC):

| raised at | run | sha / branch | class | witness |
|---|---|---|---|---|
| 10-17 17:49:43 | 39055444534 | 56d3f96 main | imbalance | group `gate playwright-webkit` (old `sweeps` jobs, aliased) 331 s vs mean 142 s (old 8-shard layout) |
| 10-17 19:24:43 | 39062347763 | bb78c5f ci/integrate-ports | growth | 5271 job-s vs median 2079 |
| 10-17 20:32:47 | 39067170911 | 411847d ci/integrate-ports | growth | 7803 vs 2358 |
| 10-17 22:14:52 | 39074271060 | 85cafde ci/gate-speed-ci | imbalance, queue | chromium 304 vs 91; s0 queued 1992 s |
| 10-17 22:32:03 | 39075461722 | 4ef66bc ci/integrate-ports-2 | imbalance | webkit 315 vs 176 |
| 10-17 23:45:10 | 39080214138 | ea1433c ci/gate-settle | imbalance | webkit 331 vs 195 |
| 10-18 00:04:46 | 39081429894 | 5a85f53 ci/integrate-ports-2 | growth, nearTimeout | 12833 vs 1651; chromium j2 2737 s of 3600 |
| 10-18 00:53:52 | 39084461260 | ebb1612 ci/fix-page-offset | imbalance | webkit 847 vs 368 (2.30) |
| 10-18 05:43:32 | 39101532038 | b35b541 ci/integrate-ports-3 | imbalance, growth, nearTimeout | webkit j3 2986 vs 1698 (1.76); 12887 vs 1004; chromium j2 2749 of 3600 |

5a85f53 also had webkit at 1.76, but that run did not re-raise imbalance: ea1433c, the run just before it, already
fired imbalance, so the alert was still open (dedup).

When the new rule would first have flagged each problem:

| problem | first alert (UTC, run creation) | run | class |
|---|---|---|---|
| any breakpoint-gate imbalance | 2026-10-17 17:49:43 | 56d3f96 | imbalance (old layout) |
| imbalance of the new 3+4 layout | 2026-10-18 00:04:46 | 5a85f53 | imbalance open (webkit 1.76) |
| imbalance of the new 3+4 layout, as a fresh raise | 2026-10-18 00:53:52 | ebb1612 | imbalance |
| shard near its timeout | 2026-10-18 00:04:46 | 5a85f53 | nearTimeout (chromium j2 0.76) |
| growth | 2026-10-17 19:24:43 | bb78c5f | growth |

All four of these first alerts came before b35b541 at 05:43Z. On the latest run (b5669db main, 06:07Z) nothing is
open.

Other workflows raised:

- webkit-sim: growth and nearTimeout at 22:04 (fb88aa2); queue at 22:46.
- gate-gaps: growth at 22:04 and 05:43.
- wktr-fixtures: queue at 22:39 and 01:38; nearTimeout at 00:28 (fixtures j2 3865 s of 3600: the job ran past its
  limit).

Replay inputs:

- **Re-runs:** for the 10 attempt-2 rows, startedS is the earliest job start of the run (INFERRED: the backfill did
  not keep the run's `startedAt`).
- **Timeouts:** they come from the `timeout_min` column of the backfill.

## Console

`fw watch` logs the `obs.ciShape` reply (the last 8 runs of each workflow, plus the open alerts) as `ciShape` on the
health line. console-api passes it through unchanged. The Health tab has a "CI shape" card that shows:

- the open alerts with their witnesses;
- per workflow, its last 3 runs: job minutes, max/mean per group and the fired classes.

The card only renders; it compares nothing.

## Feeding gate-shard-balance (no duplication)

This module observes and alerts; it never plans shards. gate-shard-balance owns two things:

- the per-load cost table: the cost of each breakpoint/zone load, taken from runs;
- the Lean shard plan with its makespan bound (Fw.Gate.Schedule).

The interface between the two:

- The ledger rows are the measured per-shard run seconds that the cost table can be checked against. Its makespan
  bound predicts max over a group; this ledger measures it. gate-shard-balance reads `ci-shape.jsonl` and does not
  re-fetch from gh.
- The imbalance class is the acceptance test for gate-shard-balance: a plan is good when, on its runs, `imbalanced` is
  false for every gate group, which is `alert_iff`'s first clause.
- `groupOf` and `rho` are the only shared notions. gate-shard-balance should import `Fw.Obs.CiShape.imbalanced`
  rather than define its own ratio.
