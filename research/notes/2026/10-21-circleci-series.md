---
id: 2026-10-21-circleci-series
kind: note
title: "CircleCI series: 20 pipelines per Arm class against the GitHub baseline (queue, duration, credits)"
status: draft
created: 2026-10-21
topics: [ci, circleci, free-tier, measurement, queue, credits, routing]
---

Question: how do the free CircleCI Arm classes compare with GitHub's free Arm runner for the `premise-tests` lane in duration and
queue spread, and what does that mean for `ci-route` and `land-lane-circleci`? Tool and rules: `docs/team/tools/circleci.md`;
pilot: `10-20-circleci-pilot.md`; the blocked first attempt (pipelines 261, 262): `10-20-circleci-series.md`.

## Result (MEASURED)

40 pipelines, all `success`, started one at a time through the API trigger on `ci/circleci-series` (commit e0bd7d6b, one commit for
all), 2026-10-21 05:49 to 07:55 UTC, medium and large alternating. Medium: pipelines 264, 266, ..., 302 (20). Large: 265, 267, ...,
303 (20). Rows: `results/circleci-series/rows/`; reduction: `results/circleci-series/summary.json`. The stop rules (1 h job cap, 10 min
queue, 1 GB-month storage) never fired. Credits had no Lean stop rule: the bound was the 40-run row cap `MAX_RUNS` in `scripts/circleci-series.mjs` (TS), and the series spent 643 credits under it. Seconds; p50 / p95 / max are nearest rank (ceil(pct n / 100)-th smallest; at n = 20 the
p95 is the 19th value, so one outlier is the max, not the p95; TS stand-in for p95, p50 is the Lean rule).

| Job | GitHub n=20 dur | `arm.medium.gen2` n=20 dur | `arm.large.gen2` n=20 dur |
|---|---|---|---|
| engine-chromium | 44 / 54 / 54 | 35.2 / 45.7 / 178.8 | 34.6 / 37.9 / 38.2 |
| engine-playwright-webkit | 61 / 83 / 105 | 52.9 / 55.8 / 55.9 | 51.6 / 54.5 / 56.1 |
| verdict | 11 / 17 / 17 (10 runs) | 9.4 / 10.0 / 21.3 | 9.2 / 9.7 / 11.7 |
| whole workflow | 97 / 761 / 1349 | 128.5 / 146.0 / 255.5 | 126.0 / 134.4 / 134.6 |

| Queue (engine jobs) | p50 / p95 / max |
|---|---|
| GitHub, n=40 jobs of 20 runs | 18 / 684 / 1284 |
| `arm.medium.gen2`, n=40 jobs of 20 pipelines | 31.9 / 37.4 / 40.0 |
| `arm.large.gen2`, n=40 jobs of 20 pipelines | 30.9 / 38.1 / 38.5 |

Queue is defined differently on the two sides: GitHub is run `createdAt` to job `startedAt`; CircleCI is `queued_at` to
`started_at` of the job (the wait for `requires` is not in it). The CircleCI queue is a flat 31 s start latency for every job,
including `verdict` (32 s), which is why the whole workflow is 126 to 129 s although the engine jobs are faster: queue 31 s,
engine 53 s, queue 32 s, verdict 9 s.

Credits (billed, Insights `credits_used`, MEASURED; they equal the Lean price list for all 40 workflows): medium 237 for 20
pipelines (11 per pipeline at the median, 25 for the outlier), large 406 (20 per pipeline at the median, 22 at most). Total 643
credits. GitHub bills 0.

Outlier: pipeline 300 (medium) ran `engine-chromium` 178.8 s, five times its median, queue 34.5 s; no other job was above 57 s.
Cause not found (one run; INFERRED a slow host).

## Meaning

- Duration: CircleCI is about 9 s faster per engine job than GitHub at the median (chromium 35 against 44 s, playwright-webkit
  53 against 61 s) and has a far tighter tail (no job over 57 s except the outlier). `arm.large.gen2` is not faster than
  `arm.medium.gen2` (workflow 126.0 against 128.5 s, within the spread) and costs 1.7 times the credits, so medium is the only class
  worth routing.
- Queue: at a quiet pool GitHub is faster at the median (18 against 31 s) and the whole lane is shorter (97 against 128 s p50). The
  GitHub p95 of 684 s comes from 3 of 20 runs with an 11 to 21 minute queue; CircleCI's worst queue in 40 jobs was 40 s. So
  CircleCI wins the tail and loses the median by about 13 s.
- Not measured: this series ran one pipeline at a time, so CircleCI's queue under concurrent load (the 30 per Arm class limit) is
  untested, and the GitHub sample spans two days and a busy pool while the CircleCI sample spans two quiet hours. The two
  samples are not the same hour.

For `ci-route`: GitHub stays first, CircleCI `arm.medium.gen2` is the failover and the hedge target. Inputs the router can use
now: CircleCI Arm medium queue p50 32 s / p95 37 s, lane wall p50 128.5 s / p95 146 s, about 12 credits a `premise-tests`
pipeline; GitHub queue p50 18 s, p95 684 s, wall p50 97 s. A hedge start on CircleCI pays when the GitHub wait passes about
30 s (97 s plus the wait against CircleCI's 128 s p50; INFERRED from the two medians). `arm.large.gen2` gets no allowlist entry.

For `land-lane-circleci`: a Linux/Arm land leg runs the same job on CircleCI without a verdict change here (40 of 40 passed;
the digest pairing is the pilot's check, not repeated), so the overflow design is sound for a leg of about this length. The task's
own measure stays open: land lane wall and queue under a busy GitHub pool and with several CircleCI pipelines at once.

## The key check (Lean + glue + test)

The first attempt spent two pipelines on a missing checkout key. `scripts/circleci.mjs key-check` (exit 0 ok, 6 missing, 7
unknown) is read-only and now runs before every CLI `trigger` and once before the series (not before each of the series' own 40 POSTs):

- Lean `Fw.Ci.Provider.keyVerdict`: a readable key list decides (a usable key, `deploy-key` or `github-user-key`, means ok; none
  means missing); an unreadable list (HTTP 403, which this token gets) falls back to the newest finished `Checkout code` step of
  the project's newest pipelines (success ok, failed missing, nothing seen unknown). A pipeline starts only on ok. Theorems per
  branch: `key_listed_ok`, `key_list_empty_missing`, `key_unreadable_clone_ok`, `key_unreadable_clone_failed_missing`,
  `key_unreadable_no_evidence_unknown`, `key_list_beats_clone`, `key_proceed_iff` and the never-starts theorems.
- Golden `keyCheck`, `keyKind`, `checkoutStatus` rows in `packages/contracts/golden/ci/provider.jsonl`; the test replays them and
  runs the glue against a fake API (readable list, 403 with each clone result, no pipeline, other errors thrown, no POST when
  not ok).
- Limit (INFERRED): with a 403 list the check reads the newest clone, so a key removed after that clone is not seen; the first
  pipeline would then fail at checkout and the series' three-failures rule stops it. The check ran green here (list 403, newest
  clone success, pipeline 263).

## Fixes made on the way

- `insights` used a route that answers 404; billed credits come from `GET /insights/{slug}/workflows/premise-tests?branch=..&reporting-window=last-7-days`.
- The series cap is 40 runs (20 per class).
