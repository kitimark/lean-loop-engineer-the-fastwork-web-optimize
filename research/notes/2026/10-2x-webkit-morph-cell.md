---
id: 2026-10-2x-webkit-morph-cell
kind: note
title: "The WebKit morph trajectory cell never gave a verdict: the probe cannot see a coarse-pointer flag at 641 and 1280, and a pooled repeat rule turns two noise widths into no verdict"
status: review
created: 2026-10-24
topics: [trajectory, webkit, mac-webkit, v2-proved, unthrottle, lean, gate]
---

# The WebKit morph cell

Task `webkit-morph-cell`. The v2-proved preset stayed empty because the WebKit family morph cell (the Mac lane, the only
engine that decides the morph pushes) answered "no verdict: coverage" or failed for every flag.

## Answer

- **Cause (CONFIRMED from the probe source and run `40080296257`, artifact `trajectory-apple`).**
  1. The probe emulates a coarse primary pointer up to 640 CSS px and a fine one from 641 (`registry.mjs` `envFor`, touch
     environment only when `w <= 640`; `engines.mjs` `hasTouch` flips `(hover: none)` and `(pointer: coarse)` together).
     `engine.scroll:unthrottle` puts its whole style rule behind `@media (pointer: coarse)`, so at 641 and 1280 the
     candidate is the faithful arm plus an unstyled empty block. Every `new` unit there is timing noise.
  2. The Mac morph walk has coverage noise at every width: the macOS VM frames are slow (gap p50 23 ms, p90 78 ms), and the
     faithful arm itself fails coverage in 42 units at each width. Even the control `hero.exit:faithful` has 42 coverage
     repeats on the Mac morph path.
  3. `Fw.Gate.Trajectory.outcome` pooled the groups: a coverage group at two or more widths means "no verdict: coverage".
     Two noise widths (641 and 1280) always trigger it.
- **Numbers (MEASURED, run `40080296257`, Mac morph, unthrottle against faithful).**

| width | new units | both fail:coverage | cleared |
|---|---|---|---|
| 390 | 0 | 42 | 42 |
| 640 | 0 | 42 | 0 |
| 641 | 84 coverage, 1 content | 42 | 0 |
| 1280 | 42 coverage | 42 | 44 |

  The two widths where the flag is inactive carry all 127 new units. The two widths where it is active carry none.
- **Fix (PROVED in Lean).** Each width of a run is decided on its own: it rests on a reading (`measured`) or on a proof that
  the candidate equals its faithful arm there (`sameByProof`). Units at same-by-proof widths count nothing. The repeat
  rule stays, over measured widths only. The rule is engine-independent: on Chromium too, the unthrottle units at 641 and
  1280 count nothing. Every flag that is active at all widths is unchanged.

## The decision

`Fw.Gate.Trajectory.basisAt flags w` is `sameByProof` when the run names flags, all are in `coarseOnly`
(`engine.scroll:unthrottle`), and the probe emulates a fine pointer at `w` (`probeCoarse w = decide (w <= 640)`).
A search shared with any flag that is active at that width is measured there.

One theorem per branch of the verdict, each on a named shape:

| branch | theorem |
|---|---|
| engine does not decide the path | `outcome_uncovered` |
| lane width not walked | `outcome_widths` |
| content repeats across measured widths | `outcome_unthrottle_coarse_fail` |
| coverage repeats across measured widths | `outcome_unthrottle_coarse_coverage` |
| units only at same-by-proof widths | `outcome_unthrottle_fine_same`, `outcome_same_by_proof` |
| other flag, same units | `outcome_other_flag_unproved` |
| shared search with an active flag | `outcome_shared_search_unproved` |
| cell width test | `inactiveAt_iff`, `basis_*`, `outcome_congr_measured` |

Soundness link: `inactive_unthrottle_same` joins `Fw.Parts.EngineScrollUnthrottle.guard_fine_noop` (the page is unchanged
at a fine pointer), `guard_fine_cost` (no restyle) and `visible_idle` (a zero-height empty box paints nothing).

The golden `packages/contracts/golden/gate/trajectory.jsonl` gains ops `cellEnv` (rows `[w, coarse]` and `coarseOnly`) and
`cell` (a stored run, its basis per width, its outcome). `test/trajectory.test.mjs` replays them against `plan.mjs`
(`probeCoarse`, `basisAt`, `cellOutcome`) and checks `probeCoarse` against the real `envFor`.

## Limits

- The proof covers the flag's engine-model effect and a zero-height empty block. Layout and `scrollHeight` are not modeled;
  the probe's scroll-height readings are the independent evidence.
- `plan.mjs` `cellOutcome` is a TS stand-in for the Lean `outcome`, checked against the golden, until the reducer reads the
  Lean decision directly.
- For `engine.scroll:unthrottle` the repeat rule rests on the two coarse widths (390, 640) only, so a pass needs no group to
  repeat across those two. That is weaker evidence than the four-width rule, and it follows from the design.
- Evidence: the cell decision is `lean/Fw/Gate/Trajectory.lean:2953-3180`; its TS twin is
  `packages/gate-breakpoints/src/trajectory/plan.mjs:37-67`, replayed against the golden in
  `packages/gate-breakpoints/test/trajectory.test.mjs:207-219`.
- Playwright WebKit on macOS stands in for Safari. The phone is not measured.
- **Split (follow-up).** Walk coverage noise on the Mac morph path for a flag that is active at every width is not fixed here:
  such a flag still shows the same coverage repeat as the control. Fixing it needs a probe change (a longer morph walk or a
  per-width retry), named `webkit-morph-walk-noise`.

## Results

All runs `?preset=v2-proved` (the preset holds `engine.scroll:unthrottle` only), recorded in
`packages/contracts/golden/preset/v2-proved.trajectory.jsonl`.

| run | engines | cells |
|---|---|---|
| `40097658094` (push) | Chromium, Linux WebKit | Chromium hero pass, Chromium morph pass, Linux WebKit hero pass |
| `40099056290` (dispatch) | Linux WebKit, macOS WebKit | Linux hero pass, Mac hero pass, Mac morph pass |
| `40080296257` (earlier, `fw=` alone) | all | Mac morph was "no verdict: coverage"; now pass |

- The Mac morph walk of `40099056290` again shows 42 coverage groups at 390, 641 and 1280 (MEASURED, units file
  `trajectory-apple`). Pooled, that is a coverage repeat (the old rule: no verdict). Counted over the measured widths (390 and
  640) it is one width, so the verdict is pass. The 390 group is the walk noise named above, not the flag.
- All four cells of `engine.scroll:unthrottle` pass: `Fw.Preset.Gen.run` writes it as the only member of v2-proved.
- Two Mac morph runs are stored (`40080296257`, `40099056290`), both pass. This is a verdict cell, not a class count; no count over
  3 separate CI jobs is claimed.
- The breakpoint gate on `preset=v2-proved` for both engines ran as run `40101370753` (workflow breakpoint-gate, head
  `0bd2a50c6`, `fw ci wait` verdict pass, conclusion success) (MEASURED). Dispatched by the lead with
  `pnpm -s fw run --gate --engines both --preset v2-proved --ref ci/webkit-morph-cell`.
