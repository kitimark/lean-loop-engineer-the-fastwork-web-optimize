# CI telemetry: first step tables and the top 3 optimize candidates (2026-10-20)

Status: MEASURED, one run per lane, so no history yet: every verdict is `noBaseline` (the Lean verdict needs 3 earlier
runs of the same lane, job, step, provider and runner class). Treat the ranking as candidates, not results. Tool:
`docs/team/tools/ci-telemetry.md`. Runs on branch `ci/ci-telemetry` (GitHub, free Linux arm64 runners, 4 cores,
15.6 GB, class `ubuntu24-arm64-4c`):

| lane | run | head |
|---|---|---|
| breakpoint-gate | 39314718340 (dispatch) | 1791b7ec |
| lean | 39314681455 (push) | 1791b7ec |
| premise-tests | 39314697927 (dispatch) | 1791b7ec |
| premise-tests | 39318599357 (dispatch) | cde71c57 (producer fixes below) |

The breakpoint-gate run failed in `gate playwright-webkit j0` (Smoke test, "orig 430px open: no answer in 30 s", a
browser smoke timeout; the other 6 gate jobs passed: chromium j0 to j2, webkit j1 to j3). Its telemetry record still
exists, so `finish` also works on a failed job; the failing step's exit is not in that record, because the in-job
jobs API reports the running step before its conclusion settles. The collector fills it from `gh run view --json jobs`
(`backfillExits`). The cause of the smoke timeout is not investigated here.

Provenance of the numbers: the breakpoint-gate and lean records were written by the first producer (class
`ubuntu24-arm64-arm64-4c`, and the telemetry action's own steps, `Run ./.github/actions/telemetry`, still among the
steps; this note leaves those rows out). Only premise-tests run 39318599357 used the fixed producer. No gate or lean
run has a step table from the final producer; the tables below are the old-producer records with the telemetry rows
removed by hand. Their class is the old one, so a new run does not share their baseline.

## What the records show (seconds; old-producer records for breakpoint-gate and lean, see above)

breakpoint-gate, steps of the 6 gate jobs that completed plus `site` (chromium = ch, webkit = wk):

| step | site | ch j0 | ch j1 | ch j2 | wk j1 | wk j2 | wk j3 |
|---|---|---|---|---|---|---|---|
| (queue) | 79 | 270 | 158 | 335 | 214 | 115 | 335 |
| setup-lean (lake cache) | 54 | | | | | | |
| setup-pnpm | 4 | 4 | 5 | 3 | 6 | 6 | 5 |
| gate-engine (engine install) | | 20 | 20 | 19 | 32 | 51 | 36 |
| smoke test | | 2 | 4 | 2 | 13 | 8 | 13 |
| run the job (probes, then sweeps) | | 699 | 733 | 725 | 787 | 805 | 771 |
| (job) | 75 | 735 | 774 | 757 | 847 | 879 | 837 |

lean (one job): queue 16, setup-lean 38, lake build 11, check.sh 13 (inside it: parallel group 11.3, props lint 11.2,
sweepsgen scope 10.1, shard golden check 7.7), job total 70.
premise-tests (first run): queue 79 and 251, gate-engine 35 and 24, tests 14 and 6, job 61 and 46.
(second run: queue 5 and 5, setup-pnpm 15 and 12, job 47 and 60).

Resource probes (every 5 s; mean / peak CPU, peak memory used of 15.6 GB):

| job | CPU mean / peak | memory peak |
|---|---|---|
| gate chromium j0 / j1 / j2 | 39 / 36 / 36 %, peak 81 / 81 / 79 % | about 3.0 GB |
| gate webkit j1 / j2 / j3 | 91 / 89 / 90 %, peak 100 % | 4.1 to 4.8 GB |
| site (breakpoint-gate) | 14 %, peak 37 % | 2.1 GB |
| lean | 31 %, peak 92 % | 3.7 GB |

Cache: the `lake` cache restored 5.36 GB (site) and 5.21 GB (lean) and saved 156 MB of growth in the lean job. Disk
free never went below 100 GB.

## Top 3 slow steps as optimize candidates (INFERRED from one run each)

1. **Gate job body "Run the job (probes, then whole sweeps)": 700 to 805 s, 92 to 95 % of each gate job.** The webkit
   jobs are CPU-bound (mean 90 %, peak 100 % of 4 cores) and take about 60 s longer than chromium; the chromium jobs
   use 36 % of the CPU, so they wait on something other than compute (page waits or serial work). Next measurement: the
   per-sweep spans inside the job, and a webkit run with fewer parallel pages, to see whether 4 cores is the limit.
2. **Queue time of the gate fan-out: 115 to 335 s per gate job (plus 79 s for `site`).** 8 jobs of one run compete for
   free runners, so the last job starts 5.5 minutes after the run was created, which is about a third of the wall time.
   Premise-tests showed 251 s, 79 s and 5 s in three jobs, so this depends on the runner pool at the time, not only on
   us. Candidate: fewer, larger shards, or starting the longest job first (needs more runs to see a pattern).
3. **Lean toolchain and cache restore: setup-lean 54 s (site) and 38 s (lean), with a 5.2 to 5.4 GB `lake` cache.**
   This is paid in every `site` and `lean` job and is larger than the build it feeds (`lake build` 11 s). Candidate:
   restore only the part the job reads (the lean-bin-slim work), measured as the restored bytes and the step time.
   Also visible: gate-engine (engine install) 19 to 51 s per gate job, longest for webkit.

Not a candidate yet: `lean/scripts/check.sh` (13 s, the longest checks about 11 s, all inside one parallel group).

## What the first records fixed in the producer

- The GitHub API names the action steps `Run ./.github/actions/telemetry`, so the step filter on the name `Telemetry`
  let the start and finish steps into the table (and made the second one look like a repeat of the first). The filter
  is now case-insensitive and matches anywhere in the name. Verified in run 39318599357 (no telemetry step rows).
- `ImageOS` is already `ubuntu24-arm64` on these runners, so the class read `ubuntu24-arm64-arm64-4c`. The class no
  longer repeats the arch. Records of the first three runs carry the old class, so the new runs start a new baseline.

- Round 2 check, premise-tests run 39324688269 (dispatch, head 1bacb6b0, both jobs passed): `machine.cpu` is
  `arm 0x41 part 0xd49` (the arm64 runners have no cpuinfo model name; so `lscpu` gave no usable "Model name" and
  the implementer and part fallback ran; INFERRED), and the last step before finish (upload-artifact) now has exit 0 where the first
  records had none. MEASURED, collected with `fw ci telemetry github 39324688269`.

## Findings about the method

- The in-job jobs API call (`/actions/runs/{id}/attempts/{n}/jobs`, `GITHUB_TOKEN`, workflow permission `contents: read`)
  works on this public repo: every record has a queue time and the full step list. CONFIRMED (runs above). So
  `actions: read` is not needed on GitHub.
- A step list taken inside the job misses the steps that run after it (upload-artifact appears, the finish step does
  not): the table covers everything up to the finish step, not the artifact upload itself.
- Step names for `uses:` steps carry the action pin, so a version bump starts a new baseline for that row. Accepted.

## Not covered

- CircleCI: no run (task limit). The config lines are in the tool doc.
- Network bytes: no tool in these jobs reports them. Simulator boot: `webkit-sim` was not run here.
- No history: the verdict column becomes useful after 3 runs per lane on the same class.
