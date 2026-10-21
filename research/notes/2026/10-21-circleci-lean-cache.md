---
id: 2026-10-21-circleci-lean-cache
kind: note
title: "A Lake cache on the CircleCI land job: the cold Lean build was 75-80% of a leg"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, land, circleci, concurrency, cache]
---

# A Lake cache on the CircleCI land job (task circleci-lean-cache)

Follow-up of `10-21-land-lane-circleci.md`. Its CircleCI land legs took 450-579 s against 63-127 s on GitHub; the INFERRED cause was a
missing Lean build cache. This note builds that cache, measures it cold and warm on the same commit, and says whether a CircleCI leg
is now worth its queue. Tool docs: `docs/team/tools/land.md`, `docs/team/tools/circleci.md`.

## Verdict

**VERDICT circleci-lean-cache: a warm CircleCI leg is not slower than the GitHub wait it avoids once GitHub's queue passes about 25 s for a browser
leg, and at any wait for the three non-browser legs. At GitHub's measured p50 queue (18 s) the two browser legs are about 7-10 s slower on
CircleCI; at its p95 queue (684 s) every leg is 450+ s faster. (INFERRED from MEASURED medians, n small.)**

## What was built (CONFIRMED, `.circleci/config.yml`, `.circleci/job.sh`)

- Key rule, like `setup-lean`: `lake-v1-arm64-<sha256 of lean-toolchain + lake-manifest.json>-<sha256 of the Lean sources>`. The Lean source hash
  covers `lean/lakefile.toml`, `lean/*.lean` and the tracked files under `lean/Fw` and `lean/FwTest`. The restore keys are the exact key,
  then the toolchain+manifest prefix (a partial hit rebuilds only what changed). Path `~/.fw-lake` (Lake cache dir plus a key marker).
- Restored on every leg. Saved only when the key changes: `job.sh lake-probe` compares the marker with the full key (equal means the exact key
  was restored), and `lake-gate` halts the job with `circleci-agent step halt` before `save_cache` in that case. CircleCI caches are immutable,
  so when several legs of one pipeline miss the same key, the first writer wins and the others report "skipped".
- The storage ledger now counts the land jobs: Lean `Provider.landJobs` (five names, `landJobs_eq_legs` ties them to the overflow legs) feeds
  `savesCacheJob`; one theorem per land job. Without it the ledger read save steps only for the pilot jobs and a land save would be uncounted.

## Per-step seconds (MEASURED; CircleCI `arm.medium.gen2`, same commit 1d26f3be, five legs per pipeline)

Cold = no entry for the key and no prefix entry; warm = exact key restored. Ranges are over the five legs; pipeline ids are the CircleCI ids.

| step | cold, dc8f3e2e (#310) | warm 1, 4c414d39 (#312) | warm 2, 8c1d9994 (#313) | source change, 2881e5a2 (#314, partial hit) |
|---|---|---|---|---|
| queue | 28-39 | 28-39 | 28-39 | 26-34 |
| checkout | 3-5 | 3-5 | 3-5 | 3.2-3.9 |
| lake cache restore | 0.5-0.6 (miss) | 2.5-3.6 | 2.5-3.5 | 2.6-3.3 |
| lean toolchain | 8-9.6 | 8.2-9.7 | 8.5-9.9 | 8.2-9.2 |
| deps install | about 2.5 | about 2.5 | about 2.5 | 2.4-2.7 |
| **fwcore build** | **353-374** | **0.1** | **0.1** | **15.2** |
| suites check-sh / suites-a / suites-b | 31.6 / 94-98 / 66-68 | 22.8-23.1 / 94-98 / 66-68 | same | 22.6 / 94.2 / 66.4 |
| browser suite chromium / webkit | 123-135 / 161-200 | same | same | 160.2 / 156.0 |
| job total check-sh | 420.6 | 47.7 | 47.6 | 66.0 |
| job total suites-a | 493.5 | 118.0 | 119.7 | 133.2 |
| job total suites-b | 461.2 | 90.3 | 91.0 | 104.9 |
| job total chromium | 509.0 | 146.9 | 158.9 | 199.9 |
| job total webkit | 576.1 | 215.1 | 186.5 | 195.1 |

- The cold `fwcore build` (353-374 s) is 75-80% of the cold leg: the INFERRED cause is CONFIRMED. Warm, the step ran 322 ms ("Build completed
  successfully (672 jobs)"). A one-docstring change in one Lean module (#314) rebuilt in 15.2 s, so the prefix restore works.
- The browser suite varies 123-200 s between runs of the same commit (pool noise); the other steps are stable to a few seconds.
- A save step appeared only in the cold pipeline (check-sh stored, the other four legs "skipped") and in #314 (check-sh stored again, new key).
  The warm pipelines halted before `save_cache` (no save step).
- Pipeline #313 (warm 2) had suites-a fail: apps/runner `test/next.test.ts`, "a real `until false; do sleep 1; done` is a sleepLoop owned by
  the session", `fwcore obs.health failed: field startedAt: expected a non-negative integer`; 2012 of 2013 passed, and the same commit
  passed in #310 and #312. INFERRED: a process-start-time flake on the runner, unrelated to the cache. Follow-up, not fixed here.

## GitHub twin of the same commit (MEASURED, n = 1)

GitHub run 39619679268 (marker commit on `ci/land-circleci-lean-cache`, all five legs success). Its Lake key was a prefix (restore-key) hit,
because the Lean sources had changed.

| measure | seconds |
|---|---|
| queue (run created to job start) | 222-252 (pool busy; n = 1, not used for the verdict) |
| leg: check-sh / suites-a / suites-b / chromium / webkit | about 100 / 186 / 145 / 157 / 210 (check-sh summed from its steps) |
| setup-lean step | about 25 |
| fwcore build | 27-30 |

## Verdict arithmetic (INFERRED)

CircleCI warm wall = queue (about 30 s) + job total (medians of #312 and #313). GitHub wall = its queue + leg. The break-even GitHub queue is
CircleCI wall minus the GitHub leg: below it GitHub is faster, above it CircleCI is.

| leg | CircleCI warm wall | GitHub leg | break-even GitHub queue |
|---|---|---|---|
| check-sh | about 78 | about 100 | below 0 (CircleCI always) |
| suites-a | about 148 | 186 | below 0 |
| suites-b | about 121 | 145 | below 0 |
| chromium | about 184 | 157 | about 27 |
| webkit | about 234 | 210 | about 24 |

- GitHub queue, from the measured series (`10-21-circleci-series.md`, not re-measured): p50 18 s, p95 684 s. CircleCI queue p50 32 s there; wall p50 128 s.
- So at the p50 queue the two browser legs are 6-9 s slower on CircleCI, and the other three legs are not. At the p95 queue and at the 222-252 s wait
  seen on this session's GitHub run every leg is faster on CircleCI. The overflow rule only sends a leg to CircleCI when GitHub has no free slot,
  i.e. when the wait is long, which is the regime where CircleCI wins.

## Storage (MEASURED, one point in time)

| quantity | value |
|---|---|
| one Lake cache entry | 292.0 MiB (306,289,050 bytes) cold; 293.0 MiB after the docstring change |
| ledger per save, 30-day hold (upper bound) | 307-308 thousandths of a GB-month |
| per save at CircleCI's 15-day retention | about 153 |
| ledger after 4 pipelines (2 saves) | 615 thousandths, under the 1000 stop rule |

- Each distinct Lean source tree is a new exact key, so each Lean change that lands on CircleCI saves one more entry (a prefix hit then a save).
  At the 30-day bound the stop rule allows about 3 saves; at 15 days about 6. The policy "save only when the key changes" stops saves of the
  same key, not the growth per source change. Follow-up: a Lean verdict on the save count (or saving only on main-sha keys).

## Limits

- n is small: three same-commit pipelines plus one source-change pipeline (4 of the 6-pipeline budget); no macOS jobs, arm Linux only.
- The GitHub queue wait is the existing p50/p95 of the series note; this session's 222-252 s is one point.
- Storage is one point in time and the ledger in this worktree started empty (the 615 counts only these four pipelines).
- The first writer of a key wins; which leg saves is arbitrary (check-sh both times), so the per-leg totals above do not include a save.
- The generated `lake-*.key` files are hashed by CircleCI `checksum` with absolute paths (CircleCI documents absolute paths as supported).
