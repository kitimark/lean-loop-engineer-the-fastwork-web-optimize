---
id: 2026-10-20-circleci-pilot
kind: note
title: "CircleCI pilot: first side-by-side runs of premise-tests (Arm) and webkit-sim (m4pro)"
status: draft
created: 2026-10-20
topics: [ci, circleci, free-tier, measurement, webkit, chromium, lean]
---

Question: does a free CircleCI class give the same verdicts as the GitHub twin, and at what duration, queue and cost?
Plan and capacity: `research/notes/2026/10-20-circleci-free-tier.md`. Tool and rules: `docs/team/tools/circleci.md`.

Unit of decision: one pair (a CircleCI job and its GitHub twin on the same commit). Each pair is decided on its own, and a
row is a check only when both sides could have failed. The verdicts come from the Lean `compare` (premise digest for the
engine jobs, conclusion only for the sim job), replayed in `scripts/circleci.mjs`.

Setup (MEASURED unless marked): the six Arm pairs ran at commit 9145de1d (CircleCI pipelines 15 and 16, GitHub run
39315828784). The sim pair ran at 458c852e (CircleCI pipeline 45, GitHub run 39332408753), which contains the exit-status
fix 430fecdf. The GitHub twins are `gh workflow run` dispatches, not pushes: a push of a lane whose inputs equal main is
skipped as "unchanged", and a dispatch always runs; this is the documented practice in `docs/team/tools/fw-ci.md`.

Pipelines on this project (the project-wide numbering counts every push; job listing of each pipeline, 2026-10-19):
- API pilot pipelines: 15, 16, 18 (round 2), 36 and 45 (sim, this round). Pipeline 18 is the replaced sim row: its job
  exit was masked by `tee`, so its "equal" was not a check; its 992 credits were spent all the same.
- Pilot webhook pipelines 7, 14, 35 and 44 (pushes of `ci/circleci-pilot`) ran no workflow (lane-gated config), 0 credits.
- Other `ci/*` webhook pipelines 3, 5, 8-13, 17, 19-34, 37-40, 42, 43, 46, 47 (33 up to pipeline 47, job listings checked; later `ci/*` pushes 48-57, 59 and 60 not checked) each ran
  main's stub job `probe` (CONFIRMED by their job listings, e.g. pipeline 17 job 16). That is not pilot cost; about 1 credit
  each is INFERRED. Landing this branch ends it only for branches that merge main later; deleting the push trigger (setup
  step 4 in the tool doc) is open for the user.
- Pipelines 1 and 4 are the setup smoke API pipelines (main, `ci/circleci-smoke`); 2, 6 and 41 are main pushes, which
  the stub's `^ci/` rule does not run.

| Pair | CircleCI class | Verdict | CircleCI s | GitHub s | Ratio | Queue GitHub / CircleCI | CircleCI credits (INFERRED, Lean `credits` from the price list) | GitHub cost: 0 billed (public repo, standard runners; CONFIRMED research/notes/2026/10-20-circleci-free-tier.md:44) |
|---|---|---|---|---|---|---|---|---|
| engine (chromium) | arm.medium.gen2 | equal | 38.8 | 39.0 | 0.99x | 135 s / 40 s | 4 | 0 billed |
| engine (playwright-webkit) | arm.medium.gen2 | equal | 51.6 | 55.0 | 0.94x | 111 s / 14 s | 6 | 0 billed |
| verdict | arm.medium.gen2 | equal | 10.1 | 11.0 | 0.92x | 669 s / 34 s | 2 | 0 billed |
| engine (chromium) | arm.large.gen2 | equal | 36.5 | 39.0 | 0.94x | 135 s / 34 s | 8 | 0 billed |
| engine (playwright-webkit) | arm.large.gen2 | equal | 52.6 | 55.0 | 0.96x | 111 s / 34 s | 11 | 0 billed |
| verdict | arm.large.gen2 | equal | 9.9 | 11.0 | 0.90x | 669 s / 39 s | 2 | 0 billed |
| webkit-sim (original, 430, 1), pipeline 45, 458c852e | m4pro.medium | equal (both pass; conclusion only) | 307.3 | 1700 | 0.18x | 114 s / 64 s | 1025 | 0 billed |
| webkit-sim (original, 430, 1), pipeline 36, 430fecdf | m4pro.medium | FINDING: CircleCI fail, GitHub pass | 826.5 | 1164 | 0.71x | 367 s / 59 s | 2756 | 0 billed |

The Arm rows and pipeline 45 exited 0 on `compare`; pipeline 36 exits 1 (a finding). Arm durations are one sample each
(the GitHub job duration is its `completedAt` minus `startedAt`). Pipeline 36 is the earlier paired sim run, made right
after the exit-status fix and before this round's re-run; it was not planned as the replacement row, and it is reported
because a failed pair is a result.

The sim pair, step by step (CircleCI pipeline 45 spans from `run.json`; GitHub steps of run 39332408753, seconds):

| Step | CircleCI | GitHub |
|---|---|---|
| checkout | 6.9 | 9 |
| node and pnpm set up | 1.1 | 1 |
| runtime, snapshot, proxy | 13.3 | 26 (runtime build 6, snapshot check 1, ios_webkit_debug_proxy 19) |
| deps install | 0.4 | not a step |
| simulator boot | 32.6 | 378 |
| determinism session (`--runs 2`, the same command) | 235.3 | 1197 |
| simulator delete | 0.6 | 24 |
| upload and the rest | 1.3 | 65 (keep logs 37, artifact upload 15, telemetry 4, job set up and complete 4, tool facts and post steps and rounding 5) |
| between steps (no span) | 15.8 (12.9 between boot and session) | 0 |
| job | 307.3 | 1700 |

The 0.18x ratio is the boot (33 s against 378 s) and the session (235 s against 1197 s). GitHub's own boot was 74 s in the
earlier run 39318078000 and 378 s now, so the GitHub side varies as much as the ratio. The Arm pairs (0.90x to 0.99x) need no
step table; their step spans are in the fixtures. Pipeline 36 spent 751 s in the determinism session, exit 130.

What this says:
- One sample each, no spread yet, so no class decision before the 10-run series: medium and large took 38.8/36.5 s
  (chromium) and 51.6/52.6 s (playwright-webkit); large costs twice the credits per minute.
- MEASURED: the verdicts and premise digests of the six Arm pairs match. The Arm jobs run at about the GitHub duration.
- The sim verdict is conclusion-only (the class-table digest is follow-up `circleci-sim-digest`). One sim pair is equal
  (pipeline 45), one is a finding (pipeline 36): the CircleCI determinism session stalled with no output for 743 s (the
  watchdog limit is 720 s, `watchdog.mjs:41` exit 3, then SIGTERM, `session.mjs:59` exit 130) while the GitHub twin of the
  same commit passed. The cause of the stall is not diagnosed (the log ends at "proxy up"). With two samples the sim
  lane on CircleCI is not reliable enough to be a default.
- The sim row is a check now. The fix in 430fecdf makes `sim-run` return node's own exit status, and pipeline 36 shows it:
  the job failed. Before that, CircleCI could not fail on the session (the pipeline 18 "equal" was not a check). A node
  failure shows through four exit paths: `cli.mjs:239` (usage, exit 2), `cli.mjs:245` (an exception, exit 1),
  `watchdog.mjs:41` (a stall, exit 3) and `session.mjs:59` (SIGINT or SIGTERM, exit 130).
- Credits and the pools (INFERRED, price list). The Arm jobs cost 33 credits for the six, from the 400,000 open-source
  pool. A sim run costs 1025 credits (307 s at 200 a minute) from the 30,000 base pool: about 29 runs a month (24 at the
  25,000 FAQ figure). The three sim pipelines of the pilot spent 992 + 2756 + 1025 = 4773 credits, 16 % of the month. A
  10-run sim series would spend about a third of the monthly macOS pool (10 x 1025 of 30,000), and a stalled run costs
  2756 (9 %). CircleCI's billed values are not read (follow-up `circleci-insights-credits`).
- Queue is defined differently on the two sides and the numbers are not like for like. GitHub: run start to job start
  (includes waiting for `needs`, hence 669 s for the verdict job). CircleCI: `queued_at` to `started_at` (the wait for
  `requires` is not counted). Read the CircleCI queue as the real wait for a runner: 14 s to 64 s here.
- CONFIRMED: `arm.medium.gen2` and `arm.large.gen2` are accepted by pipelines 15 and 16; the job API names them
  `arm-medium-gen2` and `arm-large-gen2`, mapped in Lean (`classOfApi`). The Xcode 27.0 image with the iOS 27.0 runtime
  booted and ran the sim lane.

Limits: one sample per pair, so no spread is known (follow-up `circleci-series`). The sim pair compares the first matching
GitHub matrix job `sim (original, 430, 1, <sha>, v1)` only; the other breakpoints are not paired. Storage is counted by
the ledger from every fetched run, with the pnpm cache (107 MB) counted at every job, so it was an overcount (fixed, see "Cache accounting" below; follow-up
`circleci-cache-accounting`). Measured by the ledger: 108 thousandths of a GB-month per Arm pipeline (`storageMilli` of
107,354,269 bytes for pipeline 15; 107,354,252 for 16), 219 after the first three pipelines (15, 16, 18) and 222 after the
five fetched (15, 16, 18, 36, 45; `storage.milli` of the latest `run.json`). The stop is 1000: eight more Arm pipelines
reach it (222 + 8 x 108 = 1086), so a 10-run series per class (20 Arm pipelines) passes it unless the cache-save
accounting changes first. Credits are INFERRED unless the Insights API gives billed values. The route is not wired to any
lane. `wait --branch` skips webhook pipelines only. Nothing here is phone time; counts and verdicts only.

Fixtures: `scripts/circleci-fixtures/premise-tests.json`, `premise-tests-large.json`, `webkit-sim.json` (pipeline 45) and
`webkit-sim-stall.json` (pipeline 36) are the recorded API responses (token not present; one simulator UDID in
`v1-host.txt` was replaced by zeros; `v1-session-1.json` and `.log` are left out).

## Cache accounting (task circleci-cache-accounting, 2026-10-21)

The 108 thousandths per Arm pipeline above were an accounting artefact, not storage. CONFIRMED by the job steps of pipelines 15 and
16 (API v1.1 `GET /project/{slug}/{job}`, step `Saving cache`, output text): CircleCI itself skips the upload of a key that exists
("Skipping cache generation, cache already exists for key ..., or is locked for use by another job"), and the one real upload of
the pilot was "Total size uploaded: 9.3 MiB". The ledger had instead counted `du` of the pnpm store (53.6 MB) at every engine job.
CircleCI docs (configuration reference, `save_cache`): "If a cache already exists for the given `key`, CircleCI uses the existing
cache and proceeds to the next step"; the cache of a key "is immutable"; there is no `when`-by-key and `restore_cache` sets no flag.
The documented way to end a job early is `run: circleci-agent step halt` (the job ends as a success).

What changed:
- Config: the engine jobs `restore_cache`, then `cache-probe` (does the restored marker `~/.fw-cache/lock-sha256` equal the sha256 of
  `pnpm-lock.yaml`?), and last, after `finish`, `cache-gate`: on a hit it runs `circleci-agent step halt` so `save_cache` never runs;
  on a miss it writes the marker and `save_cache` stores the store and the marker. The key is `pnpm-store-v2-...` (a v1 cache is
  immutable and has no marker). The verdict job only restores.
- Ledger: `fetch` reads the `Saving cache` step of each engine job (Lean `savesCacheJob`) and counts the bytes the step uploaded
  (Lean `cacheSavedBytes`: absent 0, skipped 0, stored = the printed MiB plus one tenth, an upper bound). Lean `storageMilli` is unchanged.

MEASURED, 3 premise-tests pipelines on `arm.medium.gen2`, commit 3a531f48, one lockfile (ledger started empty; `storage` of each
`run.json`; credits are Lean `credits` over the job durations, INFERRED):

| pipeline | cache saves | cache bytes | ledger milli after | credits | old accounting |
|---|---|---|---|---|---|
| 254 | webkit job skipped, chromium job stored 9.3 MiB | 9,856,615 | 10 | 11 | 108 |
| 255 | both jobs halted before `save_cache` (no save step) | 0 | 11 | 12 | 108 |
| 256 | both jobs halted | 0 | 11 | 11 | 108 |

Before: 108 per pipeline, 324 after three. After: 10 for the first, then about 0.13 per pipeline (artifacts 52 KB, workspace 74 KB: 126 KB), 11 after three.
The stop at 1000 is now thousands of pipelines away (990 / 0.13), not 9. Digests equal in all three. Limit: the printed size has one decimal MiB, so a stored save is counted with one tenth more;
the workspace is still `du` of `/tmp/fw/ws` (24 KB per engine job).
