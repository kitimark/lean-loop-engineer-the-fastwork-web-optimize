---
id: 2026-10-2x-macos-telemetry
kind: note
title: "macOS telemetry, 4.3 days to 2026-10-21 18:58 UTC: GitHub macOS jobs ran about 1,375 wall min/day, 78 % in measure steps; the slow tail of the measure steps is the largest cut (up to 268 min/day), then a cap on non-success jobs (about 122)"
status: review
created: 2026-10-22
topics: [ci, macos, github-actions, codemagic, circleci, telemetry, webkit-sim, trajectory-probe, slots]
---

# macOS telemetry: where the macOS minutes of all three providers go, and the ranked cuts

Task `macos-telemetry` (measure-engineer). It extends `research/notes/2026/10-21-macos-minutes.md` from one 24-hour
window to the whole history the repository has (7 days asked, 4.3 days exist), adds the per-step-class split, the
per-provider rows and a ranked cut list. **Every table below is rendered by Lean** (`Fw.Obs.MacTelemetry`, op
`obs.macReduce`) from the committed dataset `packages/contracts/golden/obs/mactelemetry-window-input.jsonl` and is pasted
here verbatim; `apps/runner/test/ci-telemetry-mac.test.ts` fails when a block in this note differs from what Lean renders.
Implementing the cuts is a follow-up.

## Answer

- **Where the minutes go (MEASURED, tables jobs and classes).** GitHub macOS jobs used about **1,375 wall min/day**
  (1,427 billed min/day, rounding each job up to a minute). **Measure steps are 1,068.5 of them (77.6 %)**; the
  Simulator boot is 72.1 (5.2 %); setup, cache, runtime and proxy together are 59.8 (4.3 %); teardown is 45.6 (3.3 %);
  upload, telemetry and post (dropped from matched time) are 21.1 (1.5 %). **107.7 min/day (7.8 %) lie in no step**: the gap
  between a job's wall time and its steps (runner start and the "Complete job" tail; INFERRED, not controllable from a workflow).
- **One step is 38 % of everything (MEASURED, table steps).** `webkit-sim / sim / Determinism sessions`: 527.6 min/day,
  median 825 s, longest 3,894 s (65 min). Its tail above the median is 174.3 min/day.
- **A third of the time is in jobs that did not succeed (MEASURED, table jobs).** 463.6 of 1,375 min/day (33.7 %). In
  webkit-sim it is 260.7 of 673.6 (38.7 %), in wktr-fixtures 55.0 %.
- **Ranked cuts (table cuts, min/day of GitHub macOS time; not additive, see "The cuts").**
  1. Bring slow measure steps down to their median: up to **267.5** (upper bound).
  2. Stop a non-success job at 1.5 x the median success wall of its job: about **121.7** (estimate).
  3. Drop the teardown steps: up to 45.6 (upper bound), **most of it already removed in webkit-sim by
     `macos-teardown-trim`** (below), so at most about 11 remain (INFERRED).
  4. Run the sim job on Codemagic up to the allowance: about 16.2 (estimate on 3 builds).
  5. Everything else is at most 14.2 (simBoot tail) and the telemetry steps are 3.6 (0.2 %): not worth cutting.
- **Savings are INFERRED until a cut lands.** The tables measure what happens; a cut's number assumes the rest of the job is unchanged.

## Method and limits

- **Window (MEASURED).** Asked: 7 days to 2026-10-21 18:58:35 UTC. The first run of the seven macOS workflows is
  2026-10-17 11:19 UTC (webkit-sim; trajectory-probe starts 10-20 08:59), so the data span is 373,126 s = **4.32 days**.
  Lean divides by the data span, not by the stated 7 days (`Input.winMs`, theorems `winMs_le`, `winMs_stated`); the 7-day
  statement would have understated every per-day figure by 38 %. The history is shorter than 7 days because the
  workflows are that new (INFERRED: nothing older is on GitHub for them).
- **Run level covers every run (MEASURED, table runs).** 3,415 completed runs of the seven workflows (`gh run list`
  per workflow, 1000 per call; no list hit the cut). Run wall minutes are the run's start-to-update time, Linux
  jobs included, so they are a coverage figure, not macOS minutes.
- **Job detail is a sample (accepted limit).** `gh run view` for every run would be 3,415 calls; Lean (`obs.macSample`,
  theorems `pick_length_le`, `pick_subset`, `pick_all_one`) picks at most 200 runs, evenly inside each workflow and event
  stratum (dispatch, other). It drew 193 runs of the 376 candidates (the share per stratum rounds down, so the draw
  stays under the bound). Each job is weighted by candidates / read of its stratum (`weightPm`), so the per-day figures are
  estimates over the 376 candidate runs, not counts. Steps are kept for macOS jobs only (`obs.macIs`).
- **Runs under 120 s hold no macOS minutes (INFERRED).** They are not candidates. The 3,039 such runs total 164 wall
  min over the 4.32 days (38 min/day if all of it were macOS: under 3 % of 1,375).
- **Thin rows (accepted limit).** Codemagic has **3 builds** (all 2026-10-21, `mac_mini_m2`, the pilot's) and CircleCI **3
  jobs** (`m4pro-medium`, 2026-10-19, the pilot's). Their rows are facts about those jobs, not rates; the provider and
  class tables mix job mixes (the GitHub columns average all macOS jobs, the others are the `sim` job), so they show
  coverage and where a step class sits, not a provider comparison. The like-for-like comparison is in
  `research/notes/2026/10-2x-codemagic-pilot.md` and `docs/team/tools/circleci.md`.
- **Step classes (Lean `classOf`).** Ordered rules over the step name (setup, cache, runtime, proxy, simBoot, measure,
  upload, teardown, telemetry, post; about 20 `decide` theorems). `upload`, `telemetry` and `post` are dropped from matched time on every provider
  (`matched` is false), so `matched` job time is the wall time minus those three: the number to put beside a Codemagic
  or CircleCI job.
- **Queue.** The time from the job becoming eligible (the run's creation, or the latest end of another job of the same
  run that ended before it started, a `needs` edge) to its start (`eligibleMs`, `queueMs`): 237.6 min/day in the jobs
  table. A macOS job waits for one of 5 concurrent macOS slots (INFERRED).
- **Privacy.** The dataset holds ids, workflow, job and step names, conclusions and epoch times. No commit, branch, author or URL.

## The tables (Lean-rendered, verbatim)

### Runs: every run of the seven macOS workflows

<!-- mt:begin runs -->
| workflow | runs | dispatched | success | failure | cancelled | candidates | read | run wall min | run wall min/day |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| trajectory-probe | 356 | 54 | 69 | 5 | 0 | 76 | 36 | 1659.5 | 384.2 |
| webkit-sim | 642 | 34 | 40 | 28 | 41 | 94 | 49 | 2726.7 | 631.4 |
| wktr | 632 | 6 | 38 | 2 | 46 | 68 | 35 | 1738.1 | 402.4 |
| wktr-fixtures | 569 | 3 | 14 | 1 | 8 | 24 | 12 | 590.9 | 136.8 |
| engine-premises | 552 | 0 | 5 | 0 | 3 | 15 | 7 | 180.8 | 41.8 |
| gate-gaps | 661 | 3 | 79 | 4 | 44 | 96 | 50 | 1648.2 | 381.6 |
| sim-speed | 3 | 0 | 0 | 3 | 0 | 3 | 1 | 103.0 | 23.8 |
<!-- mt:end runs -->

`candidates` are the runs of 120 s or more, `read` the distinct runs whose jobs were read and held a macOS job. Run
wall for `sim-speed` is 3 runs, all failures.

### Jobs: GitHub macOS jobs per workflow, weighted to the candidate runs

<!-- mt:begin jobs -->
| workflow | jobs read | mean wall min | est. wall min/day | est. billed min/day | est. matched min/day | est. queue min/day | non-success wall min/day | non-success share |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| trajectory-probe | 48 | 6.2 | 135.0 | 141.8 | 133.7 | 50.7 | 0.0 | 0.0% |
| webkit-sim | 85 | 17.9 | 673.6 | 691.0 | 659.8 | 98.2 | 260.7 | 38.7% |
| wktr | 80 | 8.0 | 288.4 | 304.8 | 286.1 | 71.4 | 90.9 | 31.5% |
| wktr-fixtures | 27 | 14.4 | 180.2 | 186.2 | 179.1 | 7.1 | 99.1 | 55.0% |
| engine-premises | 15 | 2.9 | 21.7 | 23.3 | 21.5 | 1.4 | 7.3 | 33.9% |
| gate-gaps | 50 | 0.3 | 7.5 | 7.6 | 7.3 | 1.2 | 0.0 | 0.0% |
| sim-speed | 10 | 9.8 | 68.6 | 72.2 | 66.3 | 7.6 | 5.6 | 8.2% |
<!-- mt:end jobs -->

webkit-sim is 49 % of the wall time (673.6 of 1,375), wktr 21 %, trajectory-probe 10 %, wktr-fixtures 13 %. The
non-success share is the share of wall time spent in jobs that failed, were cancelled or timed out.

### Providers

<!-- mt:begin providers -->
| provider | jobs | mean wall min | mean billed min | mean matched min | mean queue min | est. wall min/day | est. billed min/day | CircleCI credits/day |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| github | 315 | 9.5 | 9.8 | 9.3 | 1.6 | 1375.3 | 1427.1 | - |
| codemagic | 3 | 14.6 | 15.3 | 14.5 | 0.1 | 10.2 | 10.6 | - |
| circleci | 3 | 7.9 | 8.3 | 7.9 | 1.0 | 5.5 | 5.7 | 1157 |
<!-- mt:end providers -->

CircleCI credits/day are the 3 jobs' billed minutes at 200 credits per minute (`circleCreditsPerMin`), scaled like the
GitHub rows: a statement about the pilot, not a rate. Codemagic's billed minutes round up to a whole minute with a
minimum of one (`Job.billedMin`).

### Step classes

<!-- mt:begin classes -->
| class | in matched time | GitHub s/job | Codemagic s/job | CircleCI s/job | GitHub min/day | GitHub share of wall |
| --- | --- | --- | --- | --- | --- | --- |
| setup | yes | 11.9 | 47.5 | 9.4 | 28.8 | 2.0% |
| cache | yes | 1.6 | 0.0 | 0.0 | 3.8 | 0.2% |
| runtime | yes | 5.2 | 0.0 | 0.0 | 12.5 | 0.9% |
| proxy | yes | 6.1 | 62.3 | 0.0 | 14.7 | 1.0% |
| simBoot | yes | 30.0 | 72.1 | 45.4 | 72.1 | 5.2% |
| measure | yes | 444.5 | 680.3 | 418.7 | 1068.5 | 77.6% |
| upload | no | 3.6 | 3.9 | 0.6 | 8.7 | 0.6% |
| teardown | yes | 18.9 | 9.8 | 1.0 | 45.6 | 3.3% |
| telemetry | no | 1.5 | 4.5 | 1.0 | 3.6 | 0.2% |
| post | no | 3.6 | 0.7 | 0.0 | 8.8 | 0.6% |
| (gap: wall minus steps) | - | 44.8 | 0.3 | 0.6 | 107.7 | 7.8% |
| (job wall) | - | 572.2 | 881.6 | 477.0 | 1375.3 | 100.0% |
<!-- mt:end classes -->

The Codemagic and CircleCI columns are the average of the `sim` job's steps; the GitHub column averages every macOS job.
Codemagic's 47.5 s of setup and 62.3 s of proxy compare with 11.9 s and 6.1 s on GitHub (3 builds against 315 jobs).

### Busiest steps

<!-- mt:begin steps -->
| step (workflow / job / step) | class | read | est. min/day | median s | max s | tail above median min/day |
| --- | --- | --- | --- | --- | --- | --- |
| webkit-sim / sim / Determinism sessions | measure | 77 | 527.6 | 825.0 | 3894.0 | 174.3 |
| trajectory-probe / probe apple / Walk the paths of this leg (all three arms, its widths) and reduce | measure | 27 | 118.6 | 618.0 | 684.0 | 3.6 |
| wktr-fixtures / fixtures / WKTR fixtures, fresh process per pass and cell | measure | 12 | 107.9 | 718.0 | 3660.0 | 50.0 |
| wktr / wktr / WKTR, fresh process per pass, per variant | measure | 28 | 101.6 | 501.0 | 887.0 | 13.5 |
| wktr / wktr / WKTR, the original, fresh process per pass (cold, then warm) | measure | 25 | 76.2 | 481.0 | 620.0 | 6.5 |
| webkit-sim / sim / Boot the Simulator (kept booted for the whole job) | simBoot | 77 | 69.0 | 111.0 | 262.0 | 13.7 |
| sim-speed / probe / Probe (boot, connect, one page, then the extra sessions) | measure | 10 | 57.3 | 497.0 | 835.0 | 9.0 |
| wktr-fixtures / fixtures / WKTR fixtures, fresh process per pass and arm | measure | 8 | 41.6 | 687.0 | 874.0 | 4.3 |
| webkit-sim / sim / Keep logs and host state | teardown | 59 | 18.3 | 27.0 | 188.0 | 8.6 |
| webkit-sim / sim / Shut down and delete the Simulator | teardown | 75 | 16.7 | 20.0 | 142.0 | 7.6 |
| engine-premises / webkit / WKTR premise run, fresh process per pass | measure | 8 | 13.2 | 211.0 | 296.0 | 1.2 |
| wktr / wktr / Select Xcode 26.5 and show the tools | setup | 56 | 11.2 | 13.0 | 108.0 | 6.4 |
<!-- mt:end steps -->

`tail above median` is, per step, the weighted time above its own median (only for steps read three times or more).

### Ranked cuts

<!-- mt:begin cuts -->
| rank | cut | saves min/day | share of GitHub macOS wall | kind |
| --- | --- | --- | --- | --- |
| 1 | Bring slow measure steps down to their median | 267.5 | 19.4% | upper bound |
| 2 | Stop a non-success job at 1.5 x the median success wall of its job | 121.7 | 8.8% | estimate |
| 3 | Drop the teardown steps (device deletion, log keeping, shut down) | 45.6 | 3.3% | upper bound |
| 4 | Run the sim job on Codemagic up to the allowance | 16.2 | 1.1% | estimate |
| 5 | Bring slow simBoot steps down to their median | 14.2 | 1.0% | upper bound |
| 6 | Bring slow setup steps down to their median | 9.8 | 0.7% | upper bound |
| 7 | Bring slow proxy steps down to their median | 6.8 | 0.4% | upper bound |
| 8 | Drop the telemetry steps (the telemetry action, runner facts, host sampler) | 3.6 | 0.2% | upper bound |
| 9 | Bring slow upload steps down to their median | 2.9 | 0.2% | upper bound |
| 10 | Bring slow runtime steps down to their median | 1.8 | 0.1% | upper bound |
| 11 | Bring slow cache steps down to their median | 1.7 | 0.1% | upper bound |
<!-- mt:end cuts -->

## The cuts

Each row is one cut on its own against the same baseline, so the rows overlap and **must not be added**: the cap on
non-success jobs (rank 2) removes mostly the tail that rank 1 also counts, and the Codemagic shift (rank 4) moves
jobs that ranks 1, 3, 5 and 6 also touch. `upper bound` is the whole class or tail removed; `estimate` assumes a rule
(Lean `capSaving_le`: the cap never saves more than the capped jobs took; `capTerm_success`, `capTerm_few`: a success job and a
group with fewer than three successes are never capped; `shiftSaving_le`: the shift never frees more than the sim jobs
take; `shiftSaving_no_codemagic`: no Codemagic build, no shift).

1. **Slow measure steps (up to 267.5 min/day, 19.4 %).** The median step is not the problem, the tail is: Determinism
   sessions median 825 s against a 3,894 s maximum (174.3 min/day above the median); `WKTR fixtures, fresh process per
   pass and cell` median 718 s, maximum 3,660 s (50.0). The cut is a per-step timeout near 1.5 x the median (the same
   idea as rank 2, applied to the step so that the rest of the job still runs). INFERRED: the long runs are hangs or
   retries, not heavier work; the step names do not say.
2. **A cap on non-success jobs (about 121.7 min/day, 8.8 %).** A job that did not succeed is cut at 1.5 x the median
   success wall of the same workflow and job, for groups with three successes or more. The existing pool-caps and the
   webkit-sim failfast already stop some of these (`10-21-macos-minutes.md`); this number is what is left in the
   window, counting only jobs that ran past the cap.
3. **Teardown (up to 45.6 min/day, 3.3 %).** `Keep logs and host state` (18.3) and `Shut down and delete the Simulator`
   (16.7) are webkit-sim steps that `macos-teardown-trim` removed or cut to a copy (it landed on main at 2026-10-21
   16:49 UTC). 75 of the 85 sampled webkit-sim `sim` jobs still ran the shutdown step, the last at 02:57 UTC, so the
   window mostly predates the trim. At most about 11 min/day (45.6 - 35.0) remain in wktr, wktr-fixtures,
   engine-premises and gate-gaps: the follow-up `macos-teardown-followups` (INFERRED arithmetic from three table cells).
4. **Codemagic shift (about 16.2 min/day, estimate on 3 builds).** The pilot's stop line is 400 of 500 free minutes per
   30 days (`codemagicStopMin`); the shift moves as many `sim` jobs as that covers. It frees GitHub slot time, not
   GitHub cost (GitHub minutes are free for this public repository). The 3 builds took 4.8 to 21.1 min each (one failed): too few to
   rate.
5. **The rest.** Simulator boot tail 14.2, setup tail 9.8, proxy tail 6.8, upload tail 2.9, runtime tail 1.8, cache
   tail 1.7, telemetry steps 3.6 min/day. The telemetry steps are the measurement itself (0.2 % of the wall time): keep.
   `post` (8.8 min/day, 0.6 %) belongs to the runner's own post-job steps and has no cut.

What to build next, in this order: (a) per-step timeouts for the measure steps of webkit-sim, wktr and wktr-fixtures
(ranks 1 and 2 together; the cap number in rank 2 shrinks once rank 1 lands); (b) the teardown follow-up for the four
other workflows (at most 11 min/day, already specified); (c) more Codemagic builds before any shift is decided.

## The three fixes (done with this task)

1. **`fw ci state` showed too little (MEASURED).** `gh run list --limit 100` spanned only about 51 minutes when a
   burst of runs was on, so older runs of a branch were missing. `ciState` now asks for 100, then 400, then 1000 runs
   until the branch and workflow are covered, and accepts `--branch` and `--workflow` (`apps/runner/src/ci.ts`,
   `STATE_LIMITS`; tests in `apps/runner/test/ci.test.ts`). TS stand-in (I/O glue, no decision).
2. **`fw ci wait` turned a success into a failure (MEASURED cause).** In the cached
   `.git/fw-gh-budget/meta/39629760037.jobs.json`, 1 of 10 matrix jobs had `conclusion: ""`: GitHub had not yet written
   the conclusion of a job that was done. The wait folded the empty conclusion to failure and cached it. Lean now
   decides (`Fw.Ci.Attempt.jobsSettled`, theorems `jobsSettled_closed`, `jobsSettled_open_young`, `jobsSettled_open_old`;
   op `ci.attempt` takes `open` and `ago`): an open job inside a 300 s grace after the finish is read again, up to 6 times
   5 s apart, and an unsettled view is never cached; the failure line names the non-success jobs. Golden
   `packages/contracts/golden/ci-budget/wire.jsonl` (4 new cases); tests in `packages/gh-budget/test/wait.test.ts`.
3. **`fw ci telemetry` had no number to put beside Codemagic or CircleCI (done).** Each job span now ends with a
   `(matched: wall - upload, telemetry, post)` row from Lean `obs.macMatched`. The spec premise (3 to 6 min of upload and post per GitHub job) did not hold: these classes average 8.7 s per job, so matched time is 9.3 against 9.5 wall min (MEASURED, tables classes and providers); the gap to Codemagic lies elsewhere.

## Reproduce

```
pnpm -s fw ci telemetry macos-window --days 7 --sample 200 --now 1792609115000 --codemagic-builds 6ad8e6398f5c599c0322496c,6ad8ebe10ecd1a24bfc69ad3,6ad8ed7a51dd5bf84c327572 --out <file>      # collect (about 20 min, polite gh use)
cd lean && lake env lean --run scripts/MacTelemetryGolden.lean --report      # reduce the committed dataset
cd lean && lake env lean --run scripts/MacTelemetryGolden.lean --check       # golden and report up to date
```

The collector is I/O glue (`apps/runner/src/ci-telemetry-mac.ts`, a TS stand-in covered by fake-provider tests); the
sample, the macOS-job test and all arithmetic are Lean. The 3 Codemagic builds were read by id (`--codemagic-builds`),
the CircleCI jobs through the project's pipelines.

## References

- `research/notes/2026/10-21-macos-minutes.md` (the 24-hour window and its ranked plan), `docs/team/handoffs/macos-teardown-trim.md`,
  `docs/team/tools/ci-telemetry.md`, `research/notes/2026/10-2x-codemagic-pilot.md`, `docs/team/tools/circleci.md`.
- Lean: `lean/Fw/Obs/MacTelemetry.lean`, `lean/Fw/Obs/MacTelemetryWire.lean`; goldens `packages/contracts/golden/obs/mactelemetry*.jsonl`.
