# gh-budget-watch-expiry: why the shared CI poller stopped `tooBig`, and the rules that close it

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

The task asked rule (a) to refuse non-run ids. This id is a valid sentinel, so (a) alone would not have stopped it; (c) does: the sentinel stays
(lists do not drop sentinels, see the limits below) but the tick it pins is capped. Rule (a) refuses what is neither: ids at or above 10^13 outside the sentinel range, and 0.

## The three rules (Lean `Fw.Ci.Budget`, section "(i) Stale watches and the bounded tick")

| rule | definition | theorems |
|---|---|---|
| (a) registration | `validWatch L r = validRunId L r || isSentinel r`; `step .register` keeps the state for others; the wire op answers an error | `register_refused`, `register_accepted`, `incident_id` |
| (b) stale drop | `listed` drops a real run unseen in `missMax` = 3 covering lists (`unseen`) or uncovered by a full list (`uncovered`); sentinels are not dropped by lists; there is no age rule; a dead waiter's watch is the follow-up `gh-budget-waiter-liveness` | `listed_unseen`, `listed_uncovered`, `listed_total`, `listed_kept_covered` |
| (c) bounded tick | `pageCap = max 1 (share1 tick / listCost)` = 10; `tickCost = listCost * min pageCap (max 1 pages)`; a full list cannot cover a run created at or before its oldest row, so it drops it `uncovered` | `tickCost_le`, `tick_charge_no_tooBig`, `tick_no_tooBig`, `defaults_shape`, `incident_tick`, `listed_uncovered`, `listed_total`, `listed_kept_covered`, `isFull_iff` |

Stale state.pages: a state file may store `pages` larger than the cap (the incident stored 11). `pagesOf` caps it at `pageCap` = 10
when the tick reads it, so `tickCost` is 20, not 22: `incident_tick` proves it for `pages = 11`, `tick_no_tooBig` for every state,
and the golden "next: a stale stored pages of 11 is capped at 10" pins the wire reply. State files that carry the removed
`registeredAt` still load; the key is ignored.

`listed_total`: after a list, every watch is still watched or has an incident with its id at the current time.
`listed_kept_covered`: every watch that stays is a sentinel, is in the list's rows, was created before the list window
(`createdAt < createdSince`: registered after the tick began, judged by the next tick, no miss counted), or is covered by the
list (`since <= createdAt`, and for a full list the oldest row is older than it). Incidents sit
in `State.incidents` until the poller logs them to `incidents.jsonl` and sends `ack n` (`ack_drops`).

`tick_no_tooBig` holds for every state, under `0 < listCost <= share1 tick <= share tick` (proved for `defaults`). The only stops
of `next` left are `failures` and `idle`.

## Goldens and TS

`packages/contracts/golden/ci-budget/wire.jsonl` (40 cases) and `limits.json` are generated (`lake test --
--write-ci-budget-golden`). The `listed` event carries `{rows, count, pagesRead, createdSince}`; Lean decides whether the list was
cut (`isFull count pagesRead := max 1 pagesRead * 100 <= count`, `isFull_iff`; goldens: 200 rows from 3 pages not cut, 200 from 2
pages cut). The TS glue decides nothing: it passes the list, the row count, the pages it asked for and the window start, reads
`pages` from the `next` reply, logs fwcore's incidents. The TS keeps two glue rules that Lean does not decide: the next `pages` is `floor(count / 100) + 1` (the list size the poller saw),
and a run seen `completed` is unregistered. Both are listed as TS stand-ins. Tests: `packages/gh-budget/test/stale-watch.test.ts` on
the simulated clock (temp dirs only).

## Accepted limits and follow-ups

- No change to the GitHub shares. No `gh api`.
- A waiter whose watch was dropped waits until its own timeout (default 540 s) and then says "timed out"; it does not learn of the
  drop. Follow-up: have `evaluate` read `incidents.jsonl`.
- A sentinel whose waiter died stays registered until `gh-budget-waiter-liveness` lands. It pins the list window, so every tick reads
  `pageCap` pages (listCost 20, the whole tick minute share) and waiters poll slower, but the poller never stops (`tick_no_tooBig`).
- Sentinels are not coverage-checked.
- Failure incident shape: a cleanup that throws in a signal handler is appended to `incidents.jsonl` as `{cleanupFailed, at}`, a
  message and a time without a run id. Tested in `stale-watch.test.ts` with a throwing core.
- A list with exactly `pagesRead * 100` rows is treated as cut (safe side: it may drop an older run as `uncovered`).
- Race, resolved: a watch registered between `next` and `listed` with `createdAt` before the tick's window is kept unjudged for one tick
  (`judge` branch `createdAt < since`), neither missed nor dropped.
- A fw watch alert for a stopped poller is a separate task.
