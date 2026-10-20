# Where the lag of `fw ci wait` comes from (task ci-wait-lag)

Question: after a CI run finishes, `fw ci wait` returns p50 27 s, p90 55 s, max 87 s later (poll period P = 30 s). The model
allows about 35 s. Status words: MEASURED (numbers from `.fw-console/timings.jsonl`), CONFIRMED (code cited), INFERRED.

## Answer

- The lag is not one thing. With P = 30 s a run that finishes at a random point waits 0..30 s for the next tick (mean 15 s):
  that part is the model and is not lag. The rest (pickup, view, verdict, cleanup, ingest, exit) is ours and grows with host load.
- MEASURED: lag by host load (125 waits that ended 0..90 s after the last job of a run; the load is the 1-minute load average
  stored in the span, 8 cores):

| load  | n  | p50 | p90 | max |
|-------|----|-----|-----|-----|
| <20   | 51 | 22 s | 36 s | 54 s |
| 20-60 | 33 | 23 s | 47 s | 86 s |
| 60-120 | 20 | 40 s | 59 s | 63 s |
| >=120 | 21 | 51 s | 81 s | 87 s |

  At low load the lag is the model (15 s mean + about 7 s of our work). At load >= 120 it doubles. The excess is CPU
  scheduling of our own processes, not GitHub.
- MEASURED: GitHub's marking delay (a run's `updatedAt` to the first list that shows it completed) is about 1 s (n = 34).
  GitHub list staleness is not a component.
- MEASURED: poller tick gaps are mostly exactly 30 s; a few stalls exist (poller process starved, or a handoff after the holder
  left). A stall adds its length to every waiter of that moment.
- Pairing a wait's end with a run's last job end is unreliable (grace waits, multi-run waits, a wait that began after the run
  ended). The table above is therefore an upper-bias estimate, kept only for the load shape. Review finding 1 (36% of waits exceed
  the P + slice + view model) is answered by the instrumentation below, not by subtraction: after it lands, `fw timings --lag`
  gives each component per wait.

## Instrumentation (this branch)

Each `fw ci wait` span now has `runIds` and `phases` (extra fields; `parseSamples` tolerates them; the key is `runIds`, not
`runId`, so `seenRuns` does not take a wait for a CI-run span).

| field | meaning |
|-------|---------|
| `how` | done, late, already, grace, timeout, stopped |
| `holder` | this waiter ran the poller |
| `regMs`, `retMs` | registered; wait.ts returned |
| `updMs` | the run's `updatedAt` per the list (the list now asks for `updatedAt`) |
| `prevTickMs`, `tickMs` | the tick before and the tick whose list showed the run completed |
| `readMs` | this waiter's read of `runs-status.json` that decided it |
| `viewEndMs`, `doneMs` | jobs fetched; verdict decided |
| `views`, `cached`, `lockMs`, `ghMs`, `loops` | charged views, cache hits, time in locks, time in gh, slice loops |
| `ingestStartMs`, `ingestEndMs` | fw.ts: the span ingest after the verdict |

`fw timings --lag [--since h]` splits a `done` wait into list / pickup / view / verdict / cleanup / ingest / exit. The parts
telescope: they add up to span end minus `updatedAt` (test: `apps/runner/test/timing-lag.test.ts`). It also prints the tick gap
around the finish, the list-staleness evidence (`prevTickMs` after `updMs`) and total by load. The instrumentation adds no gh
call (test: gh calls with phases equal gh calls without, 5 waiters).

Real-wait numbers come after this lands: MEASURED later, by `fw timings --lag` over >= 30 waits.

## Components in code (INFERRED until the spans exist)

1. list: `poller.ts` ticks every 30 s; the file `runs-status.json` is written once per tick. Not ours to cut except by P
   (a budget decision, ci-wait-lean).
2. pickup: non-holders re-read the file every SLICE = 2 s (wait.ts); the holder reads at once. Mean 1 s, worst 2 s. Under
   load each read also pays process-start jitter. A poller handoff (holder finished, lock released, another waiter takes
   `poller.lock` on its next slice) adds up to 2 s once, plus up to 30 s if no tick ran meanwhile (INFERRED; the phase
   `holder` and `gap` show it).
3. view: one charged `gh run view --json jobs` (cost 3) under the per-run and state locks, with fwcore `reserve` and `observe`
   spawns, state lock held across the gh spawn. 2-3 process spawns plus gh (about 0.5-1 s of gh). Under load 1-5 s
   (INFERRED). Lanes mode fetches the jobs of each lane serially (`jobsOf`), so N lanes pay N views.
4. verdict: fwcore `ci.verdict` spawn.
5. cleanup: `dropWaiter` spawns fwcore `unregister` under the state lock, then the poller lock is released.
6. ingest (ours, avoidable): after the verdict fw.ts calls `ingestRuns`, one more `gh run view` per run (the same data the
   jobs view just returned), inside the span. It was booked at cost 2 although the call costs 3 (the ledger needed a
   correction every run). CONFIRMED in `apps/runner/src/timing-ci.ts` (before this change) and `fw.ts`.
7. exit: output and process exit.
8. Not in any span: the agent's next turn after exit 3 (540 s slice timeouts: 118 exit-3 returns in the data), the agent
   re-calls `fw ci wait`. Each costs one model turn; the wait that follows registers fresh, so the next run's lag is not
   inflated, but the agent's view of "waiting" is longer than the span. Lanes mode adds a 300 s missing-lane grace by design:
   a wait for a lane that never starts returns late on purpose, it is not lag.

## Fixes that are ours

| fix | status |
|-----|--------|
| ingest booked at cost 2, real cost 3 | done here (`VIEW_COST = 3`) |
| ingest repeats the view the wait just made: build the CI spans from the cached `meta/<id>.jobs.json` (cache workflowName, headSha and job timestamps in `jobsOf`), no gh call, no exit-path time, 3 requests less per run | follow-up (touches charged/core owned by ci-wait-lean) |
| lane jobs views one after the other: fetch in parallel | follow-up |
| fewer fwcore spawns per wait (`reserve` + `observe` per charged call, `unregister` per waiter) | follow-up; measure with `lockMs`/`ghMs` first |
| run the ingest after the verdict is printed (detached) | follow-up, only if the ingest share stays large after the cached-jobs fix |
| P (poll period) | not ours; ci-wait-lean |

## Agents' `gh run list/view` loops and `wait-guard`

MEASURED from the agent transcripts (Bash tool calls with a gh run list/view/watch; dated lines only, 2026-10-17..19):

| day | gh run commands | list/view | in a loop | `gh run watch` |
|-----|-----------------|-----------|-----------|----------------|
| 10-17 | 1096 | 790 | 84 | 102 |
| 10-18 | 785 | 625 | 56 | 6 |
| 10-19 (to 09:xx UTC) | 279 | 219 | 2 | 7 |

Another 135 loops are in lines without a timestamp. The loops fell from 84 to 2 per day as `fw ci wait` came into use. The
hook (`apps/runner/hooks/wait-guard.mjs`, Lean `Fw.Ops.Wait`) is in shadow mode: it denies nothing, and it allows bounded
`gh run|pr|issue list|view` loops; it does not look at `gh run watch`.

Recommendation: deny both once `fw ci wait` has its measured lag (a loop that polls every 10-20 s spends 3-6x the requests of
the shared poller and starts one process per iteration, which is part of the host load that causes the lag). This is a policy
change in Lean (`lean/Fw/Ops/Wait.lean` plus the `ops.wait.jsonl` golden and a mode switch from shadow), so it is a follow-up
and `wait-guard.mjs` is unchanged here.

## Review findings

- ciwait-check finding 1 (36% of waits exceed the model): applied as above: measured components instead of subtraction.
  The file `ciwait-check.md` was not readable from this worktree, so the other findings are not answered here (open).

## Writes outside the task's list

`packages/gh-budget/src/{state,poller,cli,index}.ts` (`updatedAt` in rows and the list fields; the phases callback and
export), `apps/runner/src/{fw,timing}.ts` (span extras, `--lag`), `packages/gh-budget/test/fake-gh-core.ts` (rows carry
`updatedAt`). TS stand-ins (no Lean): `lagParts`, `lagView`, `waitSpanExtra`; the phase recording is glue.

## Round 2 (2026-10-20): merge with today's poller, Lean partition, rerun attempt

Merged main (gh-budget-watch-expiry, gh-budget-waiter-liveness): wait.ts keeps the per-phase spans with `runIds` next to the
liveness markers and list-based drops; `fw timings --lag` sits beside `--backfill` in fw.ts. CONFIRMED by the suites (gh-budget 58,
runner 1417, ci-paths, `lean/scripts/check.sh` green).

**Phase partition is Lean.** `Fw.Ci.Lag.parts` (lean/Fw/Ci/Lag.lean) cuts the path upd..end into seven pieces; theorem `parts_sum`:
the pieces add up to the total for any marks; `stale_nonneg`, `stale_zero_of_before`. Golden `packages/contracts/golden/ci-budget/lag.jsonl`;
`lagParts` replays it in `apps/runner/test/timing-lag.test.ts`.

**Baseline.** `pnpm fw timings --lag` on this host: "no `fw ci wait` spans with phases yet". Waits before this merge carry no phases, so the
output is the pre-instrumentation baseline; the component shares are MEASURED after >= 30 waits on merged code.

**Rerun attempt bug (run 39363764375). Cause (INFERRED from the code, reproduced by the new tests):** every per-run cache was keyed by run id
alone: the jobs cache `meta/<id>.jobs.json` ("a finished run's jobs never change"), the meta row, and the finished row in the poller's file.
After `gh run rerun --failed` the id stays, so `fw ci wait <id>` read attempt 1's failure.
Rules (lean/Fw/Ci/Attempt.lean, op `ci.attempt`, golden cases in wire.jsonl):
- `reuse`: cached jobs answer only for the attempt they were read at (the cache now stores `attempt`; `gh run view --json jobs,attempt`; the list carries `attempt`).
- `settled`: a jobs view on a different attempt than the row is `stale`, not a verdict; the waiter raises a floor, re-registers its watch (the poller dropped it on the old finish) and waits.
- `current`: a row below the floor is not decisive. `fresh` (30 s): a finished row older than that (poller file read before this wait began, or meta cache) is read again.
Accepted limit: a rerun waited within 30 s of the last read of a finished row can still see the old attempt (the window dedupes waiters that start together; 20 processes needed more than 10 s here).
