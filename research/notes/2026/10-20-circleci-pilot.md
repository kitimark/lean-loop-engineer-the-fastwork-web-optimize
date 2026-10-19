---
id: 2026-10-20-circleci-pilot
kind: note
title: "CircleCI pilot: first side-by-side runs of premise-tests (Arm) and webkit-sim (m4pro)"
status: draft
created: 2026-10-20
topics: [ci, circleci, free-tier, measurement, webkit, chromium, lean]
---

Question: does a free CircleCI class give the same verdicts as the GitHub twin, and at what duration, queue and credit
cost? Plan and capacity: `research/notes/2026/10-20-circleci-free-tier.md`. Tool and rules: `docs/team/tools/circleci.md`.

Setup (MEASURED): one commit (9145de1d), three CircleCI pipelines, each triggered with `pipeline/run`; the GitHub twins
are dispatches of the same lane on the same branch (runs 39315828784 premise-tests, 39318078000 webkit-sim). The
verdicts come from the Lean `compare` (premise digest for the engine jobs), replayed in `scripts/circleci.mjs`.

| Pair | CircleCI class | Verdict | CircleCI duration | Ratio to GitHub | Queue GitHub / CircleCI | Credits |
|---|---|---|---|---|---|---|
| engine (chromium) | arm.medium.gen2 | equal | 38.8 s | 0.99x | 135 s / 40 s | 4 |
| engine (playwright-webkit) | arm.medium.gen2 | equal | 51.6 s | 0.94x | 111 s / 14 s | 6 |
| verdict | arm.medium.gen2 | equal | 10.1 s | 0.92x | 669 s / 34 s | 2 |
| engine (chromium) | arm.large.gen2 | equal | 36.5 s | 0.94x | 135 s / 34 s | 8 |
| engine (playwright-webkit) | arm.large.gen2 | equal | 52.6 s | 0.96x | 111 s / 34 s | 11 |
| verdict | arm.large.gen2 | equal | 9.9 s | 0.90x | 669 s / 39 s | 2 |
| webkit-sim (original, 430, 1) | m4pro.medium | equal | 297 s | 0.19x | 87 s / 58 s | 992 |

Every compare exited 0 (no finding). Total CircleCI credits for the three pipelines: about 1025 of the free grant.

What this says:
- MEASURED: the verdicts and premise digests match on all three pairs. Arm medium and large take the same time within
  noise (large is not faster for these jobs, and costs twice the credits per minute); medium is enough.
- MEASURED: the Arm jobs run at about the GitHub duration (0.90x to 0.99x). The sim job is about five times shorter than
  the GitHub sim job (0.19x), but it is the credit cost: 992 credits for one breakpoint, so the free grant covers only a few
  sim runs a month. INFERRED from the rate (200 credits a minute): the sim lane is a fallback for degraded GitHub macOS, not
  a default.
- Queue is defined differently on the two sides and the numbers are not like for like. GitHub: run start to job start
  (includes waiting for `needs`, hence 669 s for the verdict job). CircleCI: `queued_at` to `started_at` (the wait for
  `requires` is not counted). Read the CircleCI queue as the real wait for a runner: 14 s to 58 s here.
- CONFIRMED: `arm.medium.gen2` and `arm.large.gen2` are accepted; the job API names them `arm-medium-gen2`, mapped in Lean
  (`classOfApi`). The Xcode 27.0 image with the iOS 27.0 runtime booted and ran the sim lane.

Limits: one sample per pair, so no spread is known (the 10-run series per class is open). The sim compare uses only the
first matching GitHub sim job. Storage counted by the ledger is 1 thousandths of a GB-month per Arm pipeline (upper bound,
far from the 1000 stop). Nothing here is phone time; counts and verdicts only.

Fixtures: `scripts/circleci-fixtures/premise-tests.json`, `premise-tests-large.json`, `webkit-sim.json` are the recorded
API responses (token not present; one simulator UDID in `v1-host.txt` was replaced by zeros).
