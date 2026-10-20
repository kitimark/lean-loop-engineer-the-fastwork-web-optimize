# gh-budget-watch-expiry: why the shared CI poller stopped `tooBig`, and the three rules that close it

Task gh-budget-watch-expiry. Status words: CONFIRMED (source cited), MEASURED, INFERRED.

## Origin of the stray watch (CONFIRMED)

The id `1000000000838323` is not a stray test write and not a bad GitHub id: it is a branch waiter's sentinel.
`packages/gh-budget/src/wait.ts:37` defines `sentinelId = 10^15 + fnv(branch, workflow, sha)`; `wait.ts:225-226` sets
`id = sentinelId(t)`, `createdAt = t.since` for a `--branch` wait; `wait.ts:228` `addWaiter` (defined at `wait.ts:155-163`)
writes a marker file and sends `register` to fwcore. `10^15 + 838323` is a hash value below 2^32. No test writes the real
`.git` dir: `packages/gh-budget/test/util.ts:mkWorld` uses `mkdtempSync` for the state dir.

Why it stayed: a sentinel is not a run, so the list never shows it and the poller's "completed runs are unregistered" loop
(`poller.ts`, old line 55) never fires. It leaves only through `dropWaiter` (`wait.ts:170-181`), which runs when that waiter
exits. A waiter killed without its signal handler (SIGKILL, closed terminal) leaves the watch in `state.json` for good: the
marker file of a dead pid is only swept when another waiter of the same id leaves. Nobody reaps it. (INFERRED: which waiter
died is not recorded; the state file and waiter dir are the evidence.)

Consequence chain (CONFIRMED from the lead's state backup): the watch's `createdAt` (~04:02) held the list window open
(`created>=`), the list grew to 1000+ rows, glue set `pages = 11`, `tickCost = 2*11 = 22 > share1 tick = 20`, and
`charge` answered `stop tooBig` (`Budget.lean`, `charge` second branch). That stop is permanent until `--resume`.

The task asked rule (a) to refuse non-run ids. This id is a valid sentinel, so (a) alone would not have stopped it; (b) and
(c) do. Rule (a) refuses what is neither: ids at or above 10^13 outside the sentinel range, and 0.

## The three rules (Lean `Fw.Ci.Budget`, section "(i) Stale watches and the bounded tick")

| rule | definition | theorems |
|---|---|---|
| (a) registration | `validWatch L r = validRunId L r || isSentinel r`; `step .register` keeps the state for others; the wire op answers an error | `register_refused`, `register_accepted`, `incident_id` |
| (b) stale drop | `expire` drops a watch older than `maxAge` = 7200 s (60 min job timeout + queueing), runs on every op through `clocked`; `listed` drops a real run unseen in `missMax` = 3 covering lists; sentinels are never judged by lists | `expire_total`, `expire_sound`, `expire_old`, `listed_unseen` |
| (c) bounded tick | `pageCap = max 1 (share1 tick / listCost)` = 10; `tickCost = listCost * min pageCap (max 1 pages)`; a full list cannot cover a run created at or before its oldest row, so it drops it `uncovered` | `tickCost_le`, `tick_charge_no_tooBig`, `tick_no_tooBig`, `defaults_shape`, `incident_tick`, `listed_uncovered`, `listed_total` |

`listed_total`: after a list, every watch is still watched or has an incident with its id at the current time. Incidents sit
in `State.incidents` until the poller logs them to `incidents.jsonl` and sends `ack n` (`ack_drops`).

`tick_no_tooBig` holds for every state, under `0 < listCost <= share1 tick <= share tick` (proved for `defaults`). The only stops
of `next` left are `failures` and `idle`.

## Goldens and TS

`packages/contracts/golden/ci-budget/wire.jsonl` (38 cases, 7 new) and `limits.json` are generated (`lake test --
--write-ci-budget-golden`). The TS glue decides nothing new: `poller.ts` passes the list to the `listed` event, reads `pages`
from the `next` reply, logs fwcore's incidents. Tests: `packages/gh-budget/test/stale-watch.test.ts` on the simulated clock
(5 tests; temp dirs only).

## Accepted limits and follow-ups

- No change to the GitHub shares. No `gh api`.
- A waiter whose watch was dropped waits until its own timeout (default 540 s) and then says "timed out"; it does not learn of the
  drop. Follow-up: have `evaluate` read `incidents.jsonl`.
- A killed waiter's watch lives up to 7200 s now (was forever). A shorter bound for sentinels (the waiter timeout) is a follow-up.
- `full` is `rows.length >= 100 * pagesRead`: a list that is exactly full by coincidence is treated as cut (safe side: it may drop an
  older run as `uncovered`).
