---
id: 2026-10-17-macos-queue
kind: note
title: "macOS CI queueing: our own jobs fill the account's 5 macOS slots (shared by xcode-27 and macos-26); the preview image is not the bottleneck"
status: review
created: 2026-10-17
topics: [ci, github-actions, macos, xcode-27, concurrency, webkit, wktr, sim-speed]
---

Question: why do macOS jobs (sim-speed run 39038015877, wktr run 39038292689) sit queued 20+ min, and what should
each macOS lane do about it?
Data: every run in `gh run list --limit 100` (70 runs, 11:19 to 14:04 UTC on 2026-10-17) and `gh run view <id> --json
jobs`, snapshot at about 14:13 UTC. Runner labels come from each run's workflow file at its `headSha`.

## Answer

- **Cause: our own jobs hold all 5 macOS slots.** The number of our macOS jobs running at once never went above 5, and
  stayed at exactly 5 for 33.7 min. Every delayed macOS start (14 of 14) began 2 to 18 s after another of our macOS
  jobs ended. MEASURED.
- **The pool is shared by every macOS label.** `macos-26` jobs start in slots freed by `xcode-27` jobs and the other
  way round (e.g. wktr/archive [macos-26] started 7 s after webkit-sim/sim [xcode-27] ended). So the `xcode-27`
  preview image is not the bottleneck, and moving lanes to `macos-26` would not shorten the queue. MEASURED.
- The limit is GitHub's: 5 concurrent macOS jobs on Free, Pro and Team, 50 on Enterprise. Larger runners share the
  same macOS cap. CONFIRMED: https://docs.github.com/en/actions/reference/limits ("Maximum concurrent macOS jobs ...
  is shared across standard GitHub-hosted runners and GitHub-hosted larger runners").
- "At most one other macOS run was active" counts runs, not jobs. sim-speed alone asks for **10** `xcode-27` VMs (5
  arms x 2 reps, no `max-parallel`), and webkit-sim asks for 2 on every push. MEASURED and CONFIRMED (workflow files).
- About 17 % of the slot time since 13:30 went to webkit-sim runs on branches that do not touch WebKit. Those branches
  were cut before `main` gained the webkit-sim `paths:` filter. MEASURED.

## 1. Queue wait per runner label (MEASURED)

Wait = job start minus job creation. Creation is the run's creation time, or the time the job's last `needs` job
completed. For a job still queued, gh reports `startedAt` equal to its creation time (e.g. probe (bg, 2) shows 13:47:38
= plan done), which supports this rule.

| label | jobs | started | median wait | p90 | max (started) | still waiting / cancelled while queued |
|---|---|---|---|---|---|---|
| `xcode-27` (preview) | 37 | 28 | 0.1 min | 15.3 min | 24.8 min | probe (bg, 2) and probe (pre, 2) of 39038015877: 27+ min and still queued; 7 webkit-sim jobs cancelled while queued (up to 17 min) |
| `macos-26` (GA) | 8 | 7 | 6.3 min | 9.6 min | 10.8 min | wktr (j3) of 39038292689: 12+ min and still queued |
| `ubuntu-24.04-arm` (plan/lean jobs) | 68 | 65 | 0.1 min | 0.6 min | 3.0 min | none |

- Before 13:32, macOS concurrency was at most 4, and all 14 `xcode-27` jobs started within 10 s.
- Every wait over 1 min happened between 13:32 and 14:13, while 5 jobs were running.

| our running macOS jobs | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| minutes at that level (11:20 to 14:13) | 22.3 | 66.2 | 4.9 | 11.8 | 33.7 |

Running set at the queued jobs' creation times (MEASURED):

| time (UTC) | running (5 = full) |
|---|---|
| 13:51:31 (wktr 39038292689 created) | webkit-sim v1+v2 (39036078841, ci/webkit-fix), sim-speed fast-1, quiet-1, bg-1 |
| 14:02:50 (wktr j1-j3 created) | webkit-sim v2 (39036078841), webkit-sim v2 (39038861282, ci/chromium-ci), sim-speed quiet-1, pre-1, fast-2 |
| 14:08 | wktr j2, webkit-sim v2 (39036078841), webkit-sim v1 (39038861282), sim-speed pre-1, base-1 |

Slot use from 13:30 to 14:13: 200 of 215 VM-min (93 %). By lane (MEASURED):

| workflow / branch | macOS jobs | VM-min since 13:30 |
|---|---|---|
| webkit-sim / ci/webkit-fix (39036078841; job v2 still in "Determinism sessions" after 57 min, timeout 90) | 2 | 75.2 |
| sim-speed / ci/sim-speed | 8 started of 10 | 63.7 |
| wktr / ci/wktr-local | 7 | 26.6 |
| webkit-sim / ci/wktr-local, ci/chromium-ci, ci/trigger-scope (branches that do not change WebKit) | 6 | 34.5 |

## 2. Why

- **Account macOS cap of 5, filled only by our jobs.** CONFIRMED by the limits page, MEASURED above. Our plan tier
  is unknown, but the observed ceiling of 5 fits Free, Pro or Team. INFERRED.
- **Preview-image capacity: no evidence.** Whenever fewer than 5 of our jobs ran, `xcode-27` jobs started in 5 to
  10 s, and every delayed start lines up with the end of one of our jobs. This holds for both labels. MEASURED.
- **Per-ref `cancel-in-progress` does not stop jobs across branches.** Each workflow uses `group: ${{ github.workflow
  }}-${{ github.ref }}`, so pushes to five different `ci/*` branches each start their own webkit-sim (2 VMs).
  CONFIRMED (workflow files).
- **Stale trigger filter.** On `main`, webkit-sim.yml has a `paths:` filter (packages/measure-webkit, snapshot,
  scripts). On origin `ci/trigger-scope`, `ci/mutants-ci`, `ci/chromium-ci` and `ci/wktr-local` it still has none. So
  9 of the 16 webkit-sim runs came from branches that change no WebKit code. CONFIRMED (`git show
  <ref>:.github/workflows/webkit-sim.yml`), MEASURED (run list).
- **One wktr hop is serial and uses a macOS slot.** wktr's `archive` job runs on `macos-26` only to fill a cache: 30 s
  of work after a 10.8 min wait for a slot. Then the matrix jobs queue again. MEASURED (39038292689).

## 3. Options and their cost

| option | effect on the queue | cost to the experiment |
|---|---|---|
| (a) move lanes to GA `macos-26` | **none**: the same 5-slot pool (MEASURED handoffs across labels) | webkit-sim and sim-speed would lose the iOS 27.0 runtime, which only `xcode-27` has (feasibility note §"images", CONFIRMED there). Gain: no preview-image risk (weekly updates, no SLA). |
| (b) only lanes that must match iOS 27 stay on `xcode-27`, and they run less often | large: fewer VMs per push | Counts arrive per dispatch, not per push. |
| (c) cap macOS concurrency | removes starvation between our lanes | A concurrency group holds only 1 running member, so a shared `macos` group runs one macOS workflow at a time. `queue: max` makes pending runs wait FIFO (up to 100), but it cannot be combined with `cancel-in-progress: true` (CONFIRMED: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax). A budget is better: `strategy.max-parallel` per matrix, summing to 5 or less (`max-parallel`: standard key, section not re-read, INFERRED). |
| (d1) rebase the `ci/*` branches on `main` (gets the webkit-sim `paths:` filter) | removes about 17 % of slot time (34.5 of 200 VM-min) plus 7 queued-then-cancelled jobs | none |
| (d2) fold wktr `archive` into each wktr job (cache restore + fetch on miss), or run it on ubuntu with `enableCrossOsArchive` | removes one serial queue hop (10.8 min here) | a small duplicate download on a cache miss (INFERRED) |
| (d3) lower webkit-sim `timeout-minutes` (90) and default VMs (2 → 1 on push) | caps a stuck or slow session; one job here has held a slot 57+ min | fewer independent VMs per push; use dispatch with `vms=2-3` for determinism runs |
| (d4) GitHub Support raise / Enterprise (50 macOS) | removes the cap | plan or cost change, user decision (limits page: "GitHub Support can increase job concurrency limits") |
| (d5) self-hosted runner on this Mac | — | breaks "measure on CI, not on this Mac"; not recommended |

Recommendation per lane:

| lane | does the iOS version matter? | recommendation |
|---|---|---|
| webkit-sim | **yes**: it counts Mobile Safari's WebKit, pinned to iOS 27.0 (24A434) to match the phone | keep `xcode-27`; (d1) now; push runs 1 VM, dispatch for 2-3; `max-parallel: 2`; (d3) shorter timeout |
| sim-speed | **yes, for its purpose**: it tunes boot and connect of the iOS 27 runtime that webkit-sim uses (INFERRED from the workflow header) | keep `xcode-27`; it is a one-off probe, so dispatch only, `reps=1` or `max-parallel: 2`, and drop arms it has settled. Its 10-VM push is the largest single queue source. |
| wktr | **no**: prebuilt iOS-sim WKTR r324039 on `macos-26` (iOS 26.5 Simulator), for engine-internal counts, not device parity | already on `macos-26`; (d2); `max-parallel: 1-2` or `jobs=2` |
| gate-gaps macOS arm | **no**: the WebKit media width is an int by type, a source fact (10-17-gate-gaps-fractional.md) | no such job exists in any workflow on any ref (grep, CONFIRMED). Do not add a CI lane, since the local WKWebView run plus source and Lean already cover it. If it is ever needed: 1 job, `macos-26`, dispatch only. |

Budget across lanes while all are active: webkit-sim 2 + wktr 2 + sim-speed 1 = 5. INFERRED: no lane then waits on
another lane's matrix.

## What this changes in the plan

- §4.6 (CI lanes / version skew): say the macOS lanes share one 5-job pool for the account, across `xcode-27` and
  `macos-26`. Give each macOS workflow a `max-parallel` budget (webkit-sim 2, wktr 2, sim-speed 1) and run
  determinism and probe runs by dispatch only.
- docs/team (CI workflow owners): rebase each `ci/*` branch on `main` before pushing, so webkit-sim's `paths:` filter
  applies. Fold wktr `archive` into the wktr jobs.
