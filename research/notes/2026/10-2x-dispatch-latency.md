# Dispatch latency: where `fw run` and `fw watch` wait

Task dispatch-latency. Claims carry CONFIRMED, INFERRED or MEASURED.

## What was split

- `run dispatch` is now four spans: `run plan`, `run dispatch lock`, `run dispatch backoff`, `run dispatch call` (apps/runner/src/run-phases.ts, `GhClock`, `phasedEnv`).
- `watch pass` gets sub-spans `watch pass gh lock`, `gh call`, `gh backoff` (only when non-zero) and `other` (apps/runner/src/watch.ts, `passParts`).
- Step names and the judged goldens live in `lean/Fw/Obs/Timing.lean` (`runSteps`, `passSteps`, `judge_insert_step`); a TS test compares the names with the Lean text (CONFIRMED by test).

## Historical timings (MEASURED, `.fw-console/timings.jsonl`)

`run dispatch` 2.5-13 s usually, outliers 25-35 s, one 103 s. A 124 s `watch pass` overlapped the 103 s dispatch. A plain `gh run list` takes about 1.1 s.

## Real dispatches, split spans (MEASURED)

Before (old bounds; two concurrent dispatches, load 1.85; runs 39867859419, 39867864566, cancelled):

| Part | Dispatch 1 | Dispatch 2 |
|---|---|---|
| plan | 185 ms | 178 ms |
| lock | 42 ms | 2250 ms |
| call | 2199 ms | 2720 ms |

After (new bounds; two concurrent dispatches, load about 4.0, shared gh-budget lock busy with other fw processes; runs 39868526163, 39868530589, cancelled):

| Part | Dispatch 1 | Dispatch 2 |
|---|---|---|
| plan | 213 ms | 185 ms |
| lock, first wait | 13.47 s | 13.45 s |
| backoff | 2.4 s | 2.4 s |
| lock, after backoff | 54 ms | 2385 ms |
| call | 2237 ms | 2451 ms |

The totals are not comparable: contention differed between the two pairs. The pairs show the shape, not a speed-up.

## Slow part

- The slow part is lock wait (MEASURED: 2.25 s behind one call before, 13.5 s behind many after). The gh call itself is 2.2-2.7 s, which is GitHub response time and stays a judged sub-span, not a fix.
- Cause (CONFIRMED by reading `packages/gh-budget/src/charged.ts`): `chargedOnce` holds the shared state lock for the whole gh process. fwcore keeps one `pending` slot (`Budget.lean` `observe`), so calls must serialise.
- The 2.4 s backoff is fwcore's `reserve` answering `.wait` (INFERRED: the per-minute share window; the span does not capture the reason).
- The 103 s outlier is INFERRED to be a hung lock holder (old gh timeout 60 s, old lock wait 120 s); not reproduced on the real API.

## The lighter change

A hung gh no longer holds everybody for 60 s, and a waiter no longer waits 120 s.

| Call | gh timeout | lock wait |
|---|---|---|
| dispatch, before | 60 s | 120 s |
| dispatch, after | 20 s | 60 s |
| watch, before | 60 s | 120 s |
| watch, after | 10 s | 3 s |

A lock wait past the bound gives the named refusal `busy` (nothing dispatched, nothing booked, no retry). Lean proves the bounds lighter and that three dispatches fit (`dispatch_limits_lighter`, `watch_limits_lighter`, `three_dispatches_fit`, `watch_gh_block_bound` in `Timing.lean`).

Synthetic pair (MEASURED, real gh-budget code, a fake gh that sleeps 90 s; holder starts, waiter starts 1 s later; not a real GitHub call):

| Bounds | Holder killed after | Waiter got the lock after |
|---|---|---|
| before (60 s) | 60094 ms | 59140 ms |
| after (20 s) | 20104 ms | 19490 ms |

## Limits and follow-ups

- GitHub API latency is outside our control. No polling below 120 s was added.
- Releasing the lock during the gh process needs a Lean redesign of the single `pending` slot (follow-up).
- `DISPATCH_LIMITS`, `WATCH_LOCK_WAIT_MS`, `passParts`, `stepOf` are TS stand-ins checked against Lean text, not generated.
- Backoff reason is not recorded in the span.

## Follow-ups (task dispatch-latency-followups)

1. **Other callers bounded.** The charged wrapper's default gh timeout (wait, poller, `fw ci budget --probe`, timing ingest, `fw ci state`) was 60 s, so one hung non-dispatch call filled the whole 60 s dispatch lock wait and the dispatch was refused `busy`. The default is now 40 s: a `gh run list --limit 1000` took 22319 ms (MEASURED 2026-10-23), so 20 s would break `fw ci state`. Lean proves a hung holder of any caller ends before the dispatch wait with a 20 s margin (`hung_holder_fits`, `every_caller_fits`, `Timing.lean`); `land.ts` keeps its own 20 s (`landCallTimeoutMs`, a TS stand-in).
2. **Busy is a wait.** The poller's lock wait is 10 s (`pollLockWaitMs`); `busy` gives a 2 s retry (`busyRetryS`), never a stop and never a `stopped` status (test `charged.test.ts`). The refusal text says "nothing was dispatched" only for `workflow run`; other calls say "no request was made" (`busyMessage`, test `run-phases.test.ts`).
3. **Lock split from reserve.** New parts `run dispatch reserve` and `watch pass gh reserve`: lock ends when the first fwcore reserve request starts, reserve ends at issue or wait. The 13.47 s holder stays INFERRED: the lock file keeps a pid only, the span does not record who held it, and the 3 s watch lock wait plus a 54 s `fw land` local tier at that moment are the candidates. A repeat needs the holder's command at the time of the wait.
4. **Bounds generated from Lean.** `packages/gh-budget/src/bounds.gen.ts` (`GH_BOUNDS`) is written by `lean --run scripts/TimingGolden.lean` and checked by `--check` in `check.sh`. `DISPATCH_LIMITS`, `WATCH_LOCK_WAIT_MS`, the 10 s watch `gh run list` timeout, the default timeout and the poller bounds read it; no regex read of Lean text remains for bounds. Step names are still compared with the Lean lists by a test.
5. **Probe committed.** `node scripts/gh-hung-probe.mjs` re-runs the pair (real gh-budget code, fake gh sleeping 90 s, not a GitHub call). Re-run 2026-10-23:

| Bounds | Holder killed after | Waiter got the lock after |
|---|---|---|
| before (60 s, wait 120 s) | 60008 ms | 59095 ms |
| after (20 s, wait 60 s) | 20006 ms | 19079 ms |

   The golden has 6 `run split:` cases, not 7 (`#guard` in `Timing.lean`).

## `fw ci state` timing (item 6)

`fw ci state` now writes `ci state gh lock`, `gh reserve`, `gh call`, `gh backoff` (only when non-zero) and `reduce` (everything outside the gh calls: parse and id search) beside the whole `ci state` span (`ciStateParts`, `ciStateSteps` in Lean).

One real run, unknown id (all three lists), load 4.06 (MEASURED 2026-10-23, `.fw-console/timings.jsonl`):

| Part | ms |
|---|---|
| lock | 3 |
| reserve (3 calls) | 1123 |
| gh call (3 calls) | 37586 |
| reduce | 153 |
| whole span | 38892, exit 2 |

Per list call, including its reserve, from a separate timed run (not in timings.jsonl, which has no per-call span; the three sum to 34384 ms): limit 100 took 2789 ms, 400 took 9276 ms, 1000 took 22319 ms.

- **The slow part is the gh call**, which grows with the list size (about 22 ms per run listed: gh pages 100 rows per request). It is not the gh-budget lock (3 ms), so follow-ups (1)-(3) are not the fix for it; they bound hung holders only.
- **Exit 2** means the run id is in none of the lists (100, 400, 1000 newest runs; `ciState` prints `<id> unknown`), after all three calls ran. The slow alerts of 34.9 s, 37.3 s (exit 2) and 43.0 s match this: three lists cost about 35-38 s. A run id that is on a branch is cheap when `--branch` or `--workflow` narrows the list; an id older than 1000 runs is always the 35 s path.
- Follow-up outside the unit: callers that know the branch should pass `--branch`, so the 1000-run list is never read for a run that is not there.
