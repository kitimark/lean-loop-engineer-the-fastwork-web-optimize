---
id: 2026-10-21-land-lane-circleci
kind: note
title: "The land overflows to CircleCI: GitHub first, CircleCI for the legs GitHub has no slot for"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, land, circleci, concurrency]
---

# The land overflows to CircleCI (task land-lane-circleci)

The user asked for more land concurrency: GitHub Actions first, and when it has hit its concurrency limit, CircleCI takes the rest.
This note says what was built, what the two live runs showed, and the limits the rule lives with. Tool doc: `docs/team/tools/land.md`
("The land overflows to CircleCI"). Lean: `lean/Fw/Ci/Overflow.lean` (goldens `packages/contracts/golden/ci/overflow.jsonl`).

## What the rule is (CONFIRMED from Lean)

- GitHub has `ghCap = 20` job slots for the free plan. A queued or running workflow run holds its widest `needs` level (table `widths`, one row
  per `.github/workflows` name, an unlisted name counts 4). Free slots = 20 minus that sum, never below 0.
- The first legs that fit stay on GitHub, in matrix order; the others go to CircleCI if CircleCI is usable (`ccReady`: status healthy and fresh,
  a checkout key, credits and storage under their reserves). Otherwise they stay on GitHub and wait there.
- Theorems, one per branch of the rule: `github_first` (with room, no leg moves), `overflow_only_when_full`, `never_both` (a leg is on
  exactly one provider), `verdict_same` (one bound pass is judged the same on either provider), `pickKind_*` (refuse beats local beats
  wait beats accept when the two groups are combined). The axiom check of `lean/scripts/check.sh` is green (0 failing).

## Live runs (MEASURED, one each; no class counts are claimed from them)

| run | what | ids | result |
| --- | --- | --- | --- |
| paired | the same 5 legs of commit e4aef79b on both providers | GitHub run 39586853718, CircleCI pipeline 54ecd7d1-a61a-4bf7-9319-4df18982ed7f (number 304) | all 10 legs pass; every leg printed the same `sha` and `digest=remote:apps/runner,packages/engine-check` on both providers |
| forced overflow (1st try) | `FW_LAND_FORCE_FULL=1 node apps/runner/src/land-probe.ts` | CircleCI pipeline 5cece824-a357-4ea0-bfb7-f0418cc37450 | the adapter's first poll right after the trigger got `404 Workflow not found` on the job list of a new workflow, so the provider read as unavailable and the verdict was `local`; the pipeline itself passed. Fixed in `pollOnce` (a 404 there is "no jobs yet"), test added |
| forced overflow (2nd try) | same command, fixed | CircleCI pipeline 7733541c-8613-42c1-8412-0fae5bef0eb5, branch `ci/land-llc-forced2-86cc234` | plan `github-full`: GitHub none, CircleCI all 5 legs; marker without `[ci:land]`, so the GitHub `land` run on that push was skipped; the 5 CircleCI legs passed, the pass bound to the wanted sha and digest, and the land verdict was `accept remote-pass` |
| partial split | marker `[ci:land] ... [legs:check-sh,suites-a]` on `ci/land-llc-partial` | GitHub run 39590436245 | the guard's `exclude` left exactly the jobs `land (check-sh)` and `land (suites-a)`; passed (the `fromJSON` matrix exclude works on GitHub, which actionlint cannot show) |

Paired timings (MEASURED, one run each, so only a size, not a comparison): the GitHub run took 2 min 27 s from the first job to the last
(legs 63 to 127 s). The CircleCI legs took 450 to 579 s each plus 27 to 36 s queue (`arm.medium.gen2`; INFERRED cause: no CircleCI Lean build
cache existed yet on the first run, and `job.sh` installs the toolchain itself). CircleCI is slower on this lane; it is the overflow, not the fast path.

## How fresh the slot count is (the limit the decision takes)

The count is one `gh run list --limit 100 --json status,workflowName,databaseId` per decision, cached on disk for 120 s (the gh poll floor),
no retry on a refusal. So it is up to 120 s old. It also sees only the newest 100 runs: a run older than that and still going is not
counted (an under-count, so GitHub may be fuller than the rule thinks). The width table counts a finished job as still running (an
over-count, the safe side). An unreadable count means GitHub first, never overflow. The two errors point in different directions; neither is
bounded by a measurement here.

## Limits accepted

- Overflow covers Linux land legs. No hedge (start both and take the first). macOS lanes are follow-ups (tasks ci-route, pool-fallback).
- CircleCI concurrency under load is not measured: no busy window happened during this task.
- Credits count only pipelines this Mac fetched, in a rolling 30 days. An aborted CircleCI pipeline is not cancelled.
- If one provider's group says "local", the whole remote tier runs on this Mac. `ghPrev` (the last Actions flag) is passed as false.

## TS stand-ins (not proved in Lean)

The status-to-active filter of `readSlots`, `markerMessage` (the `[legs:a,b]` text and the missing `[ci:land]`), `legsCovered`, and the
sha-and-digest uniformity check of `normalizeCircle`. The rule itself and the group combination are replayed from the Lean golden.
