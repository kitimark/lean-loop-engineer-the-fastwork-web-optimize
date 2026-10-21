---
id: 2026-10-2x-codemagic-pilot
kind: note
title: "Codemagic pilot: one webkit-sim cell on a free Mac mini M2 with the Xcode 27 image, side by side with GitHub"
status: draft
created: 2026-10-22
topics: [ci, codemagic, free-tier, webkit, simulator, measurement, lean]
---

Question: does the `webkit-sim` cell `sim (original, 430, 1, <sha>, v1)` run on a free Codemagic Mac (iOS 27.0 Simulator, Safari,
`ios_webkit_debug_proxy`), at what duration and minutes, and does it give the same class counts as its GitHub twin?
Tool and rules: `docs/team/tools/codemagic.md`. Config: `codemagic.yaml`. Adapter: `scripts/codemagic.mjs`. Rule: Lean
`Fw.Ci.Codemagic` (golden `packages/contracts/golden/ci/codemagic.jsonl`).

Unit of decision: one build (one cell) compared with the GitHub cell of the same lane. Nothing here is phone time: these are
counts and wall time on shared Macs.

## What ran (MEASURED, Codemagic builds of branch `ci/codemagic-pilot` at 476da151)

Three builds, the ceiling the task set. All used the same `codemagic.yaml` (`mac_mini_m2`, Xcode 27.0 image, `max_build_duration` 40).

| Build | Result | Start to finish | Billed (INFERRED rounding up) | Note |
|---|---|---|---|---|
| 1 `6ad8e6398f5c599c0322496c` | finished | 21.1 min | 22 | all steps green |
| 2 `6ad8ebe10ecd1a24bfc69ad3` | failed | 4.8 min | 5 | `simctl openurl` timed out on the first page load (determinism step, 55 s in); the session never started |
| 3 `6ad8ed7a51dd5bf84c327572` | finished | 18.2 min | 19 | all steps green |

Minutes used: 46 of the 500 free (stop line 400), by the adapter's ledger; the Lean rule allowed each trigger.

## The environment the builds saw (MEASURED, `fw-result/tools.txt`, `check-simulator.txt` of builds 1 and 3)

- macOS 27.0 (26A428), Xcode 27.0 (27A266a); runtimes iOS 26.5 (23F77) and iOS 27.0 (24A434). The runtime build equals the one the GitHub
  cell pins (24A434), so `check-simulator.sh --create` passed with no download. Codemagic's image page lists the iOS 27.0 devices but no
  runtime build number; the Simulator list above is the evidence.
- 3 CPUs, 10 GiB, arm64. The GitHub runner of the same cell: 3 CPUs, macOS 27.0.1 (26A434), imageVersion 20261019.0289.1.
- Node `v26.8.2` is the default on this image, not the repo pin 24.22.0 (the image page lists 24.21.0, so the page is stale or the default
  moved). The harness ran unchanged; the counts come from the page, not from Node. Not pinned in the pilot so that the three builds stay equal.
- `ios_webkit_debug_proxy` is not preinstalled: `brew install` took 76 s (build 1) and 41 s (build 3); the GitHub cell restores it from a cache in 17 s.
- Host load averages printed by `uptime` are 250 to 330 on Codemagic and about 600 in the session logs of the GitHub cell: both are
  oversubscribed VMs, so the load figure separates nothing (INFERRED from two sources).

## Per-step seconds, GitHub run 39624847034 against Codemagic builds 1 and 3 (MEASURED)

| Step | GitHub | Codemagic 1 | Codemagic 3 |
|---|---|---|---|
| pinned runtime check, create device | 5 | 3 | 2 |
| verify snapshot | 1 | 2 | 1 |
| `ios_webkit_debug_proxy` | 17 (cache hit) | 76 (brew) | 41 (brew) |
| tool facts | 1 | 5 | 3 |
| boot Simulator | 198 | 71 | 50 |
| determinism session (2 passes) | 1403 | 1051 | 935 |
| keep logs, delete Simulator | 20 | 9 | 9 |
| machine prepare and clone | not in the job steps | 39 + 8 | 32 + 7 |
| whole job / build | 33.4 min | 21.1 min | 18.2 min |

A second GitHub run of the cell (39631161575, same lane, a later commit on the same branch) took 30.2 min. The queue before a Codemagic
build started was 7 to 11 s (created to started). The upload and telemetry steps that GitHub bills as part of the job have no
Codemagic counterpart in this pilot.

## What was worse on Codemagic (MEASURED, session logs)

| | GitHub 39624847034 | GitHub 39631161575 | Codemagic 1 | Codemagic 3 |
|---|---|---|---|---|
| extra `openurl` asks before the Safari tab appeared | 3 | 2 | 14 | 17 |
| pass 2 scroll attempt 1 failed (Runtime.evaluate timed out after 120 s) | 0 | 0 | 1 | 1 |

Build 2 hit the same Simulator slowness at its worst: `simctl openurl` itself timed out, which the harness does not retry (the "no tab"
retry covers an openurl that returned but opened nothing). Causes are INFERRED (a Simulator slow to answer on a 3-CPU shared VM); the logs
do not show why. Build 2's failure is a finding: one of three builds failed at Simulator start.

## Class counts (MEASURED; the digest of a class table is `node scripts/codemagic.mjs digest`)

Rows are `Fw/Measure/Classes` classes over the 104 rows of `v1-session-1.md`.

| Run | quarantined | deterministic | stable |
|---|---|---|---|
| GitHub 39624847034 | 37 | 50 | 17 |
| GitHub 39631161575 | 32 | 59 | 13 |
| Codemagic 1 | 32 | 58 | 14 |
| Codemagic 3 | 34 | 57 | 13 |

Rows with another class between two runs: GitHub against GitHub 11; Codemagic 1 against Codemagic 3 7; Codemagic 3 against GitHub
39631161575 7; Codemagic 1 against GitHub 39624847034 17; Codemagic 3 against GitHub 39624847034 16. Per class, both Codemagic counts fall inside the
range of the two GitHub runs. Row by row, the Codemagic builds differ from GitHub 39631161575 in 6 and 7 rows, below the 11
between the two GitHub runs, but from GitHub 39624847034 in 17 and 16 rows, above it. This is not a result: the rule asks for at least 3 runs on separate jobs per provider, and the pilot has
2 finished builds per side. Read it as "no sign of a difference", INFERRED, and nothing more.

## Recommendation (INFERRED from n = 3 builds; the user decides, nothing is wired)

- A free Codemagic Mac mini M2 can run the webkit-sim cell end to end (iOS 27.0 runtime 24A434, Simulator, Safari, inspector) in 18 to 21
  min against 30 to 33 min on GitHub, in 46 of 500 minutes for three builds. At 19 to 22 billed minutes a cell, the 400-minute line allows about 18 to 21
  cells a month (INFERRED; billing rounding is not documented on the pages read).
- Failure rates do not rank the two providers: the CircleCI pilot's sim cell stalled in 1 of 2 runs (no output for 743 s; research note
  `10-20-circleci-pilot.md`), Codemagic failed 1 of 3 (quick, 5 billed minutes). At these sizes that is a tie. The case for putting Codemagic
  ahead of CircleCI m4pro in the pool-fallback order (after GitHub) is cost and time: a flat 500 free minutes with no card, and 18 to 21 min a cell.
- Before it takes load: (1) retry `simctl openurl` in the harness (failure in 1 of 3 builds), (2) cache or preinstall the proxy (saves about 40 to 75 s a build),
  (3) pin Node to 24.22.0 in the yaml, (4) run at least 3 finished builds to meet the class-count rule, (5) one concurrent build only, so it is a
  fallback slot and not a second lane.
- The wiring into `pool-fallback` is a follow-up that needs the user's approval; this branch does not touch it.

## Limits

- The ledger `.local/codemagic-ledger.json` is per checkout; another checkout does not see the 46 minutes.
- The month boundary and the rounding are Codemagic's and undocumented here (INFERRED).
- Only the original arm, breakpoint 430, one session, was run. Not the lane's other cells.
