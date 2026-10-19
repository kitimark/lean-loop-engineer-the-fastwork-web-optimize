---
id: 2026-10-20-commission-margin-recur
kind: note
title: "Commission margin-inline gate readings fail intermittently: round 1 evidence"
status: draft
created: 2026-10-20
topics: [gate, chromium, commission, content-visibility, settle]
---

# Commission margin-inline readings: what round 1 measured

Status of every claim below: INFERRED until the diagnostic run 39324419271 is read (section "Round 2" is added then).

## Answer

- The failures are one reading per failing run: the first stop (stop 0, no resize yet) of one sweep, on the commission
  `inner` and `rows` boxes. The used auto `margin-inline-start/-end` of the original arm reads `0px`; the rewrite arm reads
  the steady value (`96px`/`132px` for inner, `8px` for rows). Every later reading of the sweep, after a resize, is fresh
  (MEASURED, five artifacts below).
- Both arms can be stale in the same run: in run 39314718340 the `pain-1440-600-1440` stop 0 reads `0px` on both arms
  (expected 96px/8px), so it passes by agreement, not by being right (MEASURED, `inner.items[0].style` of stop 0).
- The CSS rules and rects of orig and rewrite are identical at the failing stops; only the used margin differs
  (MEASURED: a deep diff of `parts.commission` of orig vs rewrite, `declared` lists excluded, shows only the four margin keys).
- Cause hypothesis (INFERRED): stop 0 reads the used margin of a box inside a `content-visibility:auto` subtree that is
  still skipped, before any layout pass has included the box (a later resize forces one). Round 2 tests it.

## The five round-1 runs (workflow breakpoint-gate, chromium 156.0.8078.4, runner ubuntu-24.04-arm)

| local id | run | branch | flags | commission |
| --- | --- | --- | --- | --- |
| r1 | 39313815482 | ci/countdown-one-chain | `hero.countdown:one-chain` | fail |
| r2 | 39314391342 | ci/exit-scoped-var | `hero.exit:scoped` | fail |
| r3 | 39314718340 | ci/ci-telemetry | none | fail |
| r4 | 39312308450 | ci/morph-layers | `morph.mount:shift-dormant` | pass |
| r5 | 39282664077 | ci/c3-gate | `preset=v2-proved` | pass |

The runner host name is not stored in the artifact (the chromium gate writes no `runner.json`); shard job ids and times
come from `gh run view --json jobs`.

## The failing readings (MEASURED, chromium.json `sweeps[].orig/rewrite[0].parts.commission`)

| run | reading id | stop | viewport | key | orig | rewrite | shard job (start-end UTC) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 39313815482 | pain-1440-600-1440#0 | 0 | 1440 | inner margin-inline-start/end | 0px | 96px | chromium j1, 118270614599 (19:48:44-20:01:19) |
| 39313815482 | pain-1440-600-1440#0 | 0 | 1440 | rows margin-inline-start/end | 0px | 8px | same |
| 39314391342 | pain-1440-600-1440#0 | 0 | 1440 | inner margin-inline-start/end | 0px | 96px | chromium j1, 118273411217 (19:56:47-20:09:26) |
| 39314391342 | pain-1440-600-1440#0 | 0 | 1440 | rows margin-inline-start/end | 0px | 8px | same |
| 39314718340 | desktop-1512-320-1512#0 | 0 | 1512 | inner margin-inline-start/end | 0px | 132px | chromium j0, 118274997440 (20:02:01-20:14:20) |
| 39314718340 | desktop-1512-320-1512#0 | 0 | 1512 | rows margin-inline-start/end | 0px | 8px | same |

- Shard of the failing sweep: from the three shard files of run 39314718340 (desktop on j0, pain on j1, phone and touch on
  j2). The shard of the same sweep in the other two runs is INFERRED by the same assignment.
- Settle of the failing stop: both arms `settled@2`, 192 ms waited, 3 frames, parked, no running animation (MEASURED).
- Same stop in the passing runs and the other arm: orig reads 132px (r1, r2 desktop stop 0) or 96px, so the box can read
  fresh at stop 0; the failure is intermittent per run and per arm.
- Readings of the same sweep after stop 0 (orig, inner margin-inline-start): desktop 132, 131.5, 16, 15.5, 0, 0 px...;
  pain 0 (stale), 0 (600px, legitimate), 96, 0, 96 px. The narrow phone and touch sweeps read 0px on every stop and both
  arms (legitimate, the box has no auto margin there).
- Timing: the stale reading has no time axis in the artifact (one reading per stop); it is the first read after the
  page-ready wait of the sweep.

## Round 2 plan

1. Run 39324419271 (ci/cmr-diag, chromium, parts=commission) loads fresh pages 2x2x12x2 times and prints `DIAGCV` lines
   (snapshots ready, settled, again, wig+1, wigback). A `0px` at ready/settled that is fresh after the wiggle confirms the
   hypothesis; otherwise it is reopened.
2. The fix is a general settle rule in Lean (`lean/Fw/Gate/Settle.lean`), not a tolerance and not a per-item selector.
