# gh-budget-watch-expiry: why the shared CI poller stopped `tooBig`, and the three rules that close it

Task gh-budget-watch-expiry. Status words: CONFIRMED (source cited), MEASURED, INFERRED.

## Origin of the stray watch

The id `1000000000838323` is not a stray test write and not a bad GitHub id: it is a branch waiter's sentinel
(CONFIRMED). `packages/gh-budget/src/wait.ts:37` defines `sentinelId = 10^15 + fnv(branch\nworkflow\nsha)`; the `--branch`
path sets `id = sentinelId(t)`, `createdAt = t.since`, then `addWaiter` writes a marker and sends `register`. No test writes
the real `.git` dir: `test/util.ts:mkWorld` uses `mkdtempSync`.

The waiter (CONFIRMED by re-computation, reviewer's evidence): `fnv("ci/cmr-diag\nbreakpoint-gate\n37c5a5a6df28a9d02bc82d926182ae383d4b0a70")
= 838323`, and `git log -1 --format=%ct 37c5a5a6` = 1792443738, equal to the watch's `createdAt` (`t.since` defaults to the
commit time). So it was `fw ci wait --branch ci/cmr-diag --workflow breakpoint-gate` on that wip commit.

Why it stayed: a sentinel is not a run, so the list never shows it and the poller's "completed runs are unregistered" loop never
fires. It leaves only through `dropWaiter`. The first idea, a waiter killed by SIGKILL, does not fit: it would leave its marker
`r1000000000838323.<pid>.<hex>`, and none exists for this id, and a later waiter of the same id that swept a dead marker would
have sent `unregister`. The likely path (INFERRED, not recorded anywhere) is the signal handler: `dropWaiter` unlinked the marker
first, then the `unregister` step failed (its fwcore child was killed with the process group, or `lockSync` timed out), and the
`catch { /* best effort */ }` in the signal handler of `cli.ts` swallowed the error. The marker was gone, the watch stayed.

Fix at the source (this round): `dropWaiter` sends `unregister` before it unlinks the marker, so a failed step leaves a marker a
later sweep reaps; the signal handler writes a failed cleanup to `incidents.jsonl` (`{cleanupFailed, at}`) instead of swallowing it.
Test: `stale-watch.test.ts` "the unregister goes before the marker is unlinked".

Consequence chain (CONFIRMED from the lead's state backup): the watch's `createdAt` (~04:02) held the list window open
(`created>=`), the list grew to 1000+ rows, glue set `pages = 11`, `tickCost = 2*11 = 22 > share1 tick = 20`, and
`charge` answered `stop tooBig` (`Budget.lean`, `charge` second branch). That stop is permanent until `--resume`.

The task asked rule (a) to refuse non-run ids. This id is a valid sentinel, so (a) alone would not have stopped it; (b) and
(c) do. Rule (a) refuses what is neither: ids at or above 10^13 outside the sentinel range, and 0.

## The three rules (Lean `Fw.Ci.Budget`, section "(i) Stale watches and the bounded tick")

| rule | definition | theorems |
|---|---|---|
| (a) registration | `validWatch L r = validRunId L r || isSentinel r`; `step .register` keeps the state for others; the wire op answers an error | `register_refused`, `register_accepted`, `incident_id` |
| (b) stale drop | `expire` drops a watch registered more than `maxAge` = 10800 s (3 h) ago (`Watch.registeredAt`, stamped by `register` from the clock; the commit time of its run does not count), on every op through `clocked`; `listed` drops a real run unseen in `missMax` = 3 covering lists; sentinels are never judged by lists | `expire_total`, `expire_sound`, `expire_old`, `expire_keeps_young`, `register_stamps`, `register_survives_expire`, `maxAge_covers_chain`, `listed_unseen` |
| (c) bounded tick | `pageCap = max 1 (share1 tick / listCost)` = 10; `tickCost = listCost * min pageCap (max 1 pages)`; a full list cannot cover a run created at or before its oldest row, so it drops it `uncovered` | `tickCost_le`, `tick_charge_no_tooBig`, `tick_no_tooBig`, `defaults_shape`, `incident_tick`, `listed_uncovered`, `listed_total`, `listed_kept_covered`, `isFull_iff` |

Bound of `maxAge` (CONFIRMED): the longest workflow chain is guard 5 + plan 5 + shard 75 (`.github/workflows/mutants.yml:119`,
`timeout-minutes: 75`) + merge 10 = 95 min = `workflowChain` 5700 s. 10800 s leaves 5100 s of queueing on free runners and
concurrency groups; `maxAge_covers_chain` proves `workflowChain + 3600 <= maxAge`. The earlier 7200 s left only 25 min.

Age from registration, not from the commit: a waiter on a commit 4.5 h old is alive from the moment it registers, so
`tooOld` is `maxAge < now - registeredAt` and `register_survives_expire` proves a fresh registration survives any `expire` up to
`maxAge` later whatever `createdAt` says. The state field is read as `createdAt` when absent (older state files).

`listed_total`: after a list, every watch is still watched or has an incident with its id at the current time.
`listed_kept_covered`: every watch that stays is a sentinel, is in the list's rows, was created before the list window
(`createdAt < createdSince`: registered after the tick began, judged by the next tick, no miss counted), or is covered by the
list (`since <= createdAt`, and for a full list the oldest row is older than it). Incidents sit
in `State.incidents` until the poller logs them to `incidents.jsonl` and sends `ack n` (`ack_drops`).

`tick_no_tooBig` holds for every state, under `0 < listCost <= share1 tick <= share tick` (proved for `defaults`). The only stops
of `next` left are `failures` and `idle`.

## Goldens and TS

`packages/contracts/golden/ci-budget/wire.jsonl` (41 cases) and `limits.json` are generated (`lake test --
--write-ci-budget-golden`). The `listed` event carries `{rows, count, pagesRead, createdSince}`; Lean decides whether the list was
cut (`isFull count pagesRead := max 1 pagesRead * 100 <= count`, `isFull_iff`; goldens: 200 rows from 3 pages not cut, 200 from 2
pages cut). The TS glue decides nothing: it passes the list, the row count, the pages it asked for and the window start, reads
`pages` from the `next` reply, logs fwcore's incidents. TS stand-ins: none. Tests: `packages/gh-budget/test/stale-watch.test.ts` on
the simulated clock (6 tests; temp dirs only).

## Accepted limits and follow-ups

- No change to the GitHub shares. No `gh api`.
- A waiter whose watch was dropped waits until its own timeout (default 540 s) and then says "timed out"; it does not learn of the
  drop. Follow-up: have `evaluate` read `incidents.jsonl`.
- A killed waiter's watch lives up to 10800 s after its registration now (was forever). A shorter bound for sentinels (the waiter
  timeout) is a follow-up.
- A list with exactly `pagesRead * 100` rows is treated as cut (safe side: it may drop an older run as `uncovered`).
- Sentinels are kept without a coverage check (they are not runs): under a full, narrowed list a sentinel's run may lie outside the
  pages read, and only the age rule bounds the watch (`listed_kept_covered` names the sentinel disjunct).
- Race, resolved: a watch registered between `next` and `listed` with `createdAt` before the tick's window is kept unjudged for one tick
  (`judge` branch `createdAt < since`), neither missed nor dropped.
- A fw watch alert for a stopped poller is a separate task.
