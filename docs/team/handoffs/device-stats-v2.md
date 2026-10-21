# Handoff: device-stats-v2 (second reduction of the 2026-10-21 phone passes)

State: branch `worktree-wf_bd28aae1-6aa-1`, code and results in `cfa7e7d1`, this note in the next commit. Read first:
`results/phone/2026-10-21/summary-v2.md`, then `lean/Fw/Device/Stats.lean`.

## What exists
- `lean/Fw/Device/Stats.lean`: 60 Hz slots from the first frame, skipped slots, > 25/34/50 ms counts, hitch ms/s with
  Apple bands, p95, longest 30 fps run, a felt window of 3 s before the first tap, touch-to-first-moving-frame and finger
  offset, `reduceV2`. Theorems: `slot_skip_of_over_two_slots`, `ivs_twoSlots_skip`, `over50_le_over34_le_miss25`,
  `run30_le_skips`, `median_le_p95`, `p95_le_longest`, `marksW_map`, `offset_zero_of_follow`; `miss_without_skip` is
  the counterexample (golden kind `v2.counterexample`).
- Golden: `packages/contracts/golden/device/session.jsonl` (lines 1 to 92 are the first reduction, unchanged; v2 lines
  follow). Regenerate: `cd lean && lake env lean --run scripts/DeviceSessionGolden.lean > ../packages/contracts/golden/device/session.jsonl`,
  then the same command with `--check`.
- TS twin in `packages/measure-webkit/src/device-session.mjs` (from `CONST2` down), test `device-session-v2.test.mjs`.
  Lean `reduceV2` and the TS twin gave equal JSON on all four real passes (local cross-check, records not committed).

## TS stand-ins
- `summarizeV2` and `summaryV2Md` are glue: they group, count and format. Verdicts use `verdict`, the TS twin of Lean
  `verdict` checked on the first-reduction golden; the window and pass rates are plain arithmetic, not yet in Lean.

## Conventions
- Raw records stay local (scratchpad `phone/2026-10-21/rec-1..4.json`); summary-v2 holds counts and rates only, no
  times, scroll positions or touch values. The summary is written by a scratch script that first checks that
  `reducePass` reproduces `summary.json`, then calls `summarizeV2`.

## Open items
- The morph tween under scroll lock is not a recorded part, so the "animating" selection misses it.
- rAF times are frame starts, not glass times; WebKit hitches past the main thread need xctrace (phone-hitches-xctrace).
- Drags are short flicks; scrollY often changes only after lift (INFERRED: UI-process scroll reaches scrollY late).
- The 120 Hz display class is a constant; the page draws at 60 Hz.
