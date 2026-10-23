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
