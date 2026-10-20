---
id: 2026-10-20-circleci-series
kind: note
title: "CircleCI series: blocked at checkout (no checkout key); the GitHub baseline and the driver are ready"
status: draft
created: 2026-10-21
topics: [ci, circleci, free-tier, measurement, queue, credits]
---

Question: how do CircleCI Arm medium and large compare with GitHub's free Arm runner for the `premise-tests` job, in duration
spread, queue p50/p95 and credits? Tool and rules: `docs/team/tools/circleci.md`; pilot: `research/notes/2026/10-20-circleci-pilot.md`.

Unit of decision: a 10-run series per class, 20 pipelines in all (cap 30), started only through the API trigger on
`ci/circleci-series`.

## Result: the CircleCI series was NOT delivered

MEASURED: two pipelines were started (numbers 261 and 262, class `arm.medium.gen2`, commit 2d7720fe). Both ended `failed` in the
`Checkout code` step after about 1 s of job time; `verdict` did not run. No series exists; no CircleCI p50/p95 is claimed.

| Pipeline | Class | Result | Workflow wall | Job queue (engine jobs) | Job time | Credits (INFERRED, Lean price list) |
|---|---|---|---|---|---|---|
| 261 | arm.medium.gen2 | failed at checkout | 38.3 s | 36.3 s, 34.6 s | 1.1 s, 1.2 s | 2 |
| 262 | arm.medium.gen2 | failed at checkout | 39.6 s | 31.7 s, 37.8 s | 1.0 s, 1.0 s | 2 |

Cause (CONFIRMED by the job step output of both pipelines): `Warning: checkout key has zero length`, then `Load key ... error in
libcrypto` and `Permission denied (publickey)` from GitHub on the SSH `git clone`. The project is a GitHub OAuth project (the
pipeline definition's `checkout_source.provider` is `github_oauth`, read from the API), so the clone needs a checkout key (a deploy
key or a user key). The same pipeline worked three hours earlier (pipelines 254 to 256, checkout success, 2026-10-20 17:35 to
17:43 UTC). Since then the user deleted the push trigger (setup step 4); the pipeline definition now lists no trigger (API,
`triggers: []`). INFERRED: the key went with the trigger or was removed in the same settings visit; not verified. The key list
(`GET /project/{slug}/checkout-key`) answers 403 with this token, so the key state cannot be read from here either.

I did not create a key through the API: it adds a deploy key to the GitHub repository, a settings change the task does not
authorize. Spent: 2 of the 30 runs, 4 credits (INFERRED).

To resume (user step, then one command): in CircleCI, Project Settings, SSH Keys, add a deploy key (or a user key) for the
repository, then run
`node scripts/circleci-series.mjs run --branch ci/circleci-series --runs 10 --out results/circleci-series --scratch <dir> --config-root <main checkout>`
(20 sequential pipelines, medium then large, alternating; about 4 minutes each; refuses past 30 rows; stops after 3 failures in a
row), then `... insights` (billed credits, MEASURED), `... github`, `... summary`. The two failed rows stay in `rows/` and are
counted as runs (the script counts rows), so use `--runs 10` only after deleting them, or accept 18 new runs.

## What is ready (MEASURED, the GitHub twin)

Stored runs of `premise-tests` on GitHub's `ubuntu-24.04-arm` runner (free for this public repository), the newest 20 successful
runs of any branch and event in which both engine jobs ran (`results/circleci-series/github-runs.json`; run ids in
`summary.json`; 2026-10-18 to 2026-10-20; 10 pushes to main, 5 pushes to `ci/*`, 5 `workflow_dispatch`). A push whose lane inputs
equal main's skips the whole workflow, so most push runs have no engine job and are not in the 20. Seconds; p95 is the nearest
rank (ceil(0.95 n)-th smallest, the rule of Lean `Fw.Obs.Timing.p50` at 95 percent; TS stand-in, tested against the Lean `#guard`
values).

| GitHub job | n | duration p50 / p95 / max | queue p50 / p95 / max |
|---|---|---|---|
| engine (chromium) | 20 | 44 / 54 / 54 | 18 / 683 / 1238 |
| engine (playwright-webkit) | 20 | 61 / 83 / 105 | 18 / 684 / 1284 |
| verdict (runs where it was not skipped) | 10 | 11 / 17 / 17 | not comparable (it waits for the engine jobs) |
| whole workflow, run created to last job end | 20 | 97 / 761 / 1349 | |

GitHub queue = run `createdAt` to job `startedAt`. The p95 is two or three runs with a queue of 11 to 21 minutes (the max
1284 s, run 39357895585); the typical queue is 15 to 21 s. GitHub bills 0 credits for these runs.

CircleCI numbers that exist, one sample each (pilot, `10-20-circleci-pilot.md`): duration 36.5 to 38.8 s (chromium) and 51.6 to
52.6 s (playwright-webkit) on both Arm classes, queue 14 to 40 s, credits 4 and 6 (medium) and 8 and 11 (large) per engine job.
The four checkout-failed jobs above queued 31.7 to 37.8 s (pipeline 261, 262). Four jobs are not a queue distribution.

## Fixes made on the way

- `fetchPipeline` read the detail of a `not_run` job and died on 404 (`Job not found`, pipeline 261 job 81); it now skips jobs
  that never ran.
- `waitPipeline` can hit a 404 on the jobs of a workflow that is listed before its jobs are readable (seen once, right after the
  trigger); the series driver retries it every 15 s, at most 12 times.
- Result rows carry the pipeline number only; pipeline and workflow ids go to `.local/circleci-series-ids.json` (gitignored).

## Accepted limits

- No CircleCI p50/p95, no billed credits (Insights `credits_used`) and no Linux Docker class: the pilot config has only `machine`
  jobs, so there is no docker class to run. The `webkit-sim` lane is out of this series (macOS credits, base-pool budget).
- The GitHub baseline is not the same hour as any CircleCI run; the GitHub sample spans two days and includes one 21-minute queue.
