---
id: 2026-10-18-task-state-truth
kind: note
title: "task-state-truth round 5: the real log replayed through main and branch fwcore, before and after"
status: draft
created: 2026-10-18
topics: [console, plan, fwcore, task-state, replay]
---

Question: what does the board show for the real console log when it is replayed through main's fwcore and through the
round-5 branch fwcore (quiet state, identity-only stops, names never sight)?

Status tags: MEASURED (replay on this Mac, a read-only copy of the console data, one run each). The replay is a pure
function of the log, so the CI-only rule for engine measurements does not apply.

## Method

- Input: a copy of `.fw-console/events.jsonl` (1288 events), `health.jsonl` and `spool/` into a temp dir; the real
  workflow journals read in place (read only).
- Main: console-api and contracts from `main` at 712c9668, fwcore built at 712c9668 (its build record matches the
  binary's sha256), and the backfill as committed before round 5 (40 lines).
- Branch: this branch before the main merge (ca0689b8), its own fwcore, and the round-5 backfill (17 lines; the 23
  name-keyed agent.stop lines are dropped because a name never sights or stops).
- Steps: `Store.open`, submit each backfill line (actor lead, `cite` dropped), one `Drain.run()`, then `board()`.
  Query time `now` = 1792320600000 for both runs.

## Answer

| state | main | branch |
|---|---:|---:|
| running | 10 | 2 |
| quiet | 0 | 17 |
| parked | 0 | 7 |
| handedBack / integrated | 0 / 0 | 0 / 0 |
| done | 216 | 217 |
| ready | 39 | 21 |
| blocked | 30 | 31 |
| cut | 5 | 5 |

MEASURED. Backfill: main accepted 23 of 40 lines (main's fwcore has no `task.integrate`, `task.handback` or
`task.park`); branch accepted 17 of 17. The drain took 275 s (main, 63737 accepted) and 336 s (branch, 64030 accepted,
0 sweep errors).

Rows whose state changed (27 of 300; 159 more done or cut rows only lost the agent column, since such a task shows no
agent). Age is `now` minus the quiet row's last sighting.

| task | main | branch | last seen |
|---|---|---|---|
| `gate-settle`, `math-final`, `slow-site-build`, `variant-hidden-pause`, `visual-diff` | running | quiet | 703 to 859 min |
| `integrate-ports`, `variant-morph-panel-rest` | running | blocked | 782, 851 min |
| `jev-oracle` | running | parked | |
| `fix-commission`, `fix-misc`, `fix-nav`, `fix-people-webkit`, `fix-stagebg-webkit` | ready | quiet | 782 to 802 min |
| `port-commission`, `port-hero`, `port-morph-panel`, `port-nav`, `port-overlays`, `port-pain`, `port-people` | ready | quiet | 1021 to 1057 min |
| `ci-shape-obs`, `lfg-premise-registry`, `lfg-ts-lint`, `lfg-workflow`, `webkit-sim-rewrite` | ready | parked | |
| `lean-first-gate` | blocked | parked | |
| `lean-bin-slim` | ready | done | |

The two rows still running (`task-state-truth`, `gate-shard-balance`) have a sighting after `now`: the spool copy
was taken after the chosen query time.

## Reading

- 8 of the 10 tasks main showed running had no sighting for 11 to 15 hours. On the branch none of those 8 is
  running (Lean `running_needs_recent_sighting`, `no_forever_running`).
- The 12 `fix-*` and `port-*` rows turn quiet, not parked: their SpawnGuard keys were sighted and never stopped by
  identity, and no spool record carries the obs key on SubagentStop. They stay quiet until a lead or user mark or
  a stop of that key (stated limit; Lean `timeout_never_ends`).
- Every parked row on the branch has an identity stop of every bound key or a park mark (Lean
  `ended_needs_identity_stops`).
- The `lean-bin-slim` ready to done change and the `blocked` rows that carry a last-seen time were not investigated
  further (blocked takes precedence over quiet when a dependency is open).
