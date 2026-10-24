---
id: 2026-10-2x-unthrottle-parts-rest
kind: note
title: "unthrottle-parts rest mode: people.card agrees where it can be judged, commission agrees once its Lean class is the snap (a post-hoc fit)"
status: review
created: 2026-10-25
topics: [lag, webkit, ios-toolbar, scroll-driven, engine.scroll, measure]
---

# Rest mode, judged per pass and per arm

Task `unthrottle-parts-rest`, the split of `unthrottle-parts-measure` after its third refusal on rest cadence claims.
Earlier note: `10-2x-unthrottle-parts-measure.md`. Data: run 40101702393 (3 jobs, existing artifacts, no new CI run),
re-reduced into `results/unthrottle-parts/rest-40101702393.{json,md}`. Lean: `Fw.Device.ThrottleParts`; golden
`packages/contracts/golden/device/throttle-parts.jsonl`; reducer `packages/measure-webkit/src/throttle/parts.mjs`.

## Answer first

- **people.card: agree (partial).** MEASURED. The rewrite, lift and unthrottle arms ran at 20-30 ms gaps (K 3-4) and show
  0 band runs over 1741, 1639 and 1641 frames; the prediction (pulses, none when lifted) holds. The original arm is
  no-data: its three exercised passes ran at 59, 64, 64 ms (K 1), outside the domain. The earlier "disagree" counted
  those 18 K-1 runs against the prediction.
- **commission: agree in all four arms, but only after the Lean class changed.** The measured counts are the ones the
  earlier note called disagree (rewrite 23 band runs over 753 frames, 3 jobs). Lean source shows the commission follower
  snaps up on a rising target, so its throttled prediction is stills, not pulses. The fit was made after the data:
  INFERRED. It needs a fresh independent measurement before it counts as confirmed.
- **The earlier "23 ms / 20 ms median gap" for commission was a pooling artifact.** MEASURED: round 1 passes are
  people-anchored and slow, round 2 passes are commission-anchored and ran at 17 ms (K 5). The median is now taken per
  exercised pass and each pass carries its own K.

## Domain and the converse theorem

- **A pass counts only at K 3 or more (`minK`).** INFERRED as a modelling choice, not an engine fact: one dropped frame
  of a moving series makes a 1-2 frame hold, which a K-1 band [1, 2] cannot tell from jitter
  (`drop_in_band_low`); at K 3 or more it cannot (`drop_out_of_band`, `minK_iff`: K at least 3 for gaps up to 33.33 ms).
- **The fixed 5-6 band holds only for 14.29 ms to below 20 ms.** CONFIRMED in Lean: `throttleK_band_iff` is the converse
  of `throttleK_mem_band`. Rest mode (20 ms and up) falls outside it: `bandFor_rest` gives [4, 5] at 20 ms and 23 ms,
  `bandFor_5900` gives [1, 2].
- **`judge` pools passes in the domain only** (`pool`, `judge_noData_out`, `judge_out_cons`); one theorem per branch
  (`judge_stills_*`, `judge_none_*`). Golden: 468 pass-list vectors, 240 count vectors (`judgeCounts`), 13 `bandFor`
  vectors with `inDomain` and `fixed`. The TS twins replay all of them.
- **Cadence count.** `hit_throttled_cadence`: on a hit part with K 1 or more, a throttled curve has n-1 cadence-band
  counts. CONFIRMED in Lean.

## people.card per pass (MEASURED, run 40101702393)

| arm | job | round | gap ms | K | band | band runs | mid-moving | in domain |
|---|---|---|---|---|---|---|---|---|
| original | 1 | 1 | 59 | 1 | 1-2 | 4 | 485 | no |
| original | 2 | 1 | 64 | 1 | 1-2 | 8 | 489 | no |
| original | 3 | 1 | 64 | 1 | 1-2 | 6 | 493 | no |
| rewrite | 1-3 | 1 | 27, 24, 23 | 3, 4, 4 | 3-4, 4-5, 4-5 | 0, 0, 0 | 572, 588, 581 | yes |
| lift | 1-3 | 1 | 30, 25, 23 | 3, 3, 4 | 3-4, 3-4, 4-5 | 0, 0, 0 | 512, 573, 554 | yes |
| unthrottle | 1-3 | 1 | 26, 20, 25 | 3, 4, 3 | 3-4, 4-5, 3-4 | 0, 0, 0 | 558, 525, 558 | yes |

The original arm is the only slow one: the same page, the same driver, but 2.5 times the gap. Why is not known; the
accepted limit is that touch-driver losses and the Simulator's load stay as recorded (INFERRED: a slower frame clock on
that job). Every verdict for the arm is no-data, and the lifted arms compare against the rewrite, whose pool is in
domain.

## commission per pass (MEASURED)

All twelve passes are round 2, anchored on commission, 17 ms (18 ms once), K 5, band 5-6: inside the proved 60 Hz domain.

| arm | band runs per pass (job 1, 2, 3) | mid-moving frames | pooled |
|---|---|---|---|
| original | 6, 4, 4 | 324, 298, 261 | 14 / 883 |
| rewrite | 10, 13, 0 | 349, 354, 50 | 23 / 753 |
| lift | 0, 0, 0 | 342, 348, 39 | 0 / 729 |
| unthrottle | 1, 0, 0 | 332, 367, 286 | 1 / 985 |

Two jobs carry the rewrite's 23 runs; job 3's rewrite pass saw only 50 mid-moving frames. The rewrite arm stands at 23,
which is off the 10-run line, so the disagree with "pulses" was not an artifact of one pass.

## The commission class (Lean, INFERRED fit)

- Source: `apps/site/src/parts/commission/logic.ts` `frame`: `n1 = s.n < m ? m : s.n + (m - s.n) * g`. On a rising target
  the follower is set to the target, so the written value is the target curve itself.
- Lean: `commission_snaps_up` (a follower at or below the target becomes the target) and `enterFollow_rising` (a rising
  target gives follower = target); new shape `snap` (`reach_snap`: hit; `predicted_snap`: throttled main-thread snap is
  stills, `basis` names the two theorems). The commission part's shape moved from `chase` to `snap`.
- The commission and commissionEnter rows are identical because the shrink value is `max n r` and r stays 0 while the
  card enters.
- Under the new class the same counts are agree: rewrite 23 and original 14 are at least 10; lift 0 and unthrottle 1 are
  at most a fifth of the rewrite rate. INFERRED, post-hoc. It is not evidence that the class is right; a fresh run of the
  rewrite and lifted arms with the prediction fixed beforehand is the follow-up.

## Not claimed here

- hero.exit, platform.shrink and morph.panel are no-data in rest mode (platform anchor not found on all jobs; hero is
  exited; fade never found). Hero stays as measured in the earlier note.
- `partVerdict` ignores the original arm as a reference only; people.card's "agree (partial)" comes from the rewrite and
  both lifted arms. The original's no-data is shown, not hidden.
- The phone is not re-measured; touch-driver losses stay as recorded (6 of 9 passes usable per arm).

## Follow-ups

1. Independent commission measurement under the `snap` class (rewrite, lift, unthrottle on separate CI jobs).
2. Platform anchor not found: a task of its own.
3. Why the original arm ran at 60 ms in round 1 (job-level Simulator load or the flag-free page): not investigated.
4. Re-reduce the drag and finish summaries to the new schema (per-pass table) if a later reader needs it (not done here).
