---
id: 2026-10-18-task-state-truth
kind: note
title: "task-state-truth round 6: the real log replayed through main and branch fwcore, before and after"
status: draft
created: 2026-10-18
topics: [console, plan, fwcore, task-state, replay]
---

Question: what does the board show for the real console log when it is replayed through main's fwcore and through the
round-6 branch fwcore (quiet state, identity-only stops, names never sight, a mark ends a quiet task)?

Status tags: MEASURED (replay on this Mac, a read-only copy of the console data, one run each). The replay is a pure
function of the log, so the CI-only rule for engine measurements does not apply.

## Method

- Input: a copy of `.fw-console/events.jsonl` (1331 events), `health.jsonl` and `spool/` (6542 files) into a temp dir,
  one copy per run. The copy took 4.3 s (1792323767807 to 1792323772071 ms). The real workflow journals were read in
  place (read only).
- Main: console-api and contracts from `main` at db41542a, fwcore built at db41542a (its build record matches the
  binary's sha256). No backfill: the 17 backfill lines are `task.park`, `task.integrate` and `task.handback`, which
  main's fwcore does not accept.
- Branch: this branch with the Lean sources of 233064f2 (the later commits change docstrings and this note), its own
  fwcore, and `docs/team/backfill/task-state-2026-10-18.jsonl` (17 lines).
- Steps: `Store.open`, submit each backfill line (actor lead, `cite` dropped), one `Drain.run()`, then `board()`.
  Query time `now` = 1792323772071 (the end of the copy) for both runs, so no sighting comes after `now`.

## Answer

| state | main | branch |
|---|---:|---:|
| running | 29 | 5 |
| quiet | 0 | 5 |
| integrated | 0 | 13 |
| parked | 0 | 9 |
| handedBack | 0 | 1 |
| done | 217 | 217 |
| ready | 24 | 19 |
| blocked | 25 | 26 |
| cut | 5 | 5 |

MEASURED. Backfill: branch accepted 17 of 17. The drain took 524 s on main (59635 records accepted, 6343 refused as
invalid by the strict `ObsRecord` schema) and 640 s on the branch (65978 accepted, 6700 identity stops, 0 sweep
errors).

Rows whose state changed (30 of 300). "Last seen" is `now` minus the row's last sighting.

| task | main | branch | last seen |
|---|---|---|---|
| `gate-settle`, `math-final`, `slow-site-build`, `variant-hidden-pause`, `visual-diff` | running | quiet | 756 to 912 min |
| `integrate-ports`, `variant-morph-panel-rest` | running | blocked | 835, 904 min |
| `ci-shape-obs`, `jev-oracle`, `lfg-premise-registry`, `lfg-ts-lint`, `lfg-workflow` | ready | parked (no handback) | |
| `lean-first-gate` | blocked | parked (no handback) | |
| the 17 `port-*` and `fix-*` rows below | running | the mark | |

The `port-*` and `fix-*` rows. The first 12 are the rows that showed quiet in round 5; the last 5 started after it.
Every one has a mark in the backfill and now shows that mark, not quiet (Lean `mark_ends_quiet`).

| task | main | branch | mark |
|---|---|---|---|
| `port-commission`, `port-hero`, `port-morph-panel`, `port-nav`, `port-overlays`, `port-pain`, `port-people` | running | integrated | `integrate-ports-2` |
| `fix-commission`, `fix-nav`, `fix-stagebg-webkit` | running | integrated | `integrate-ports-2` |
| `fix-misc` | running | handedBack | tip ef1774f |
| `fix-people-webkit` | running | parked | no-op, its only commit adds a handoff |
| `fix-commission-margin`, `fix-page-offset`, `fix-pain-notes` | running | integrated | `ci/integrate-ports-3` |
| `fix-nav-hittest` | running | parked | no-op, its only commit adds a handoff |
| `fix-orbit` | running | parked | ended with no commit |

The 5 rows still running on the branch (`task-state-truth`, `gate-shard-balance`, `engine-model-fix-2`,
`webkit-sim-rewrite`, `wktr-serial-baseline`) were sighted 0 to 2 min before `now`; they are the agents working
during the copy. The other `port-*` and `fix-*` rows (`port-parts`, `port-morph`, `fix-proofs` blocked; the
`port-morph-*` and `port-platform` rows done) are the same on both.

## Reading

- 24 of the 29 tasks main showed running are quiet, blocked or marked on the branch; none of them was sighted in the
  last 120 min, so none is running (Lean `running_needs_recent_sighting`, `no_forever_running`).
- The 5 quiet rows have no mark and no identity stop of their keys; they stay quiet with their last-seen time until
  a stop of the key or a lead or user mark (Lean `timeout_never_ends` for an unmarked task,
  `timeout_ends_only_by_mark`).
- Every parked row has an identity stop of every bound key or a park mark (Lean `ended_needs_identity_stops`).
- `lean-bin-slim`, which changed from ready to done in round 5, shows done on both sides now, so it is no
  longer a difference. Round 5 compared against main 712c9668 with a different backfill; which input made main show
  it ready there was not investigated.
- `blocked` wins over quiet while a dependency is open, so the two blocked rows above keep their last-seen time but
  show blocked.
