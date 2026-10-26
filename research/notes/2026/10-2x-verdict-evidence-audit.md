# Verdict evidence audit (task verdict-evidence-audit, incident inc-empty-evidence-win)

Question: which Lean verdicts that compare a base sample with a candidate sample can read a win (gain, pass) when one
side holds no evidence or too little? The rule after this task: a side below its minimum is undecided (`none`,
`noData`, `.undecided`), never a win; with complete evidence the verdict is the old one.

Status: CONFIRMED by the Lean theorems named below (`lake build`, `lean/scripts/check.sh`) and by the golden diffs: every
golden file this task regenerated only gained lines (0 removed lines in `offscreen`, `offscreen-windows`,
`offscreen-webkit`, `touch-lock` and `faithful.verdict`), so no complete-evidence verdict changed.

## Table

| Function | Callers | Minimum evidence per side | Empty side before → after | Theorems: (a) short side never a win · (b) complete evidence unchanged | Golden rows (empty / short) | TS twin, test |
|---|---|---|---|---|---|---|
| `TouchLock.cmp` | `MorphEndCount.cmpBy`; TS `touchlock.mjs` `summarize`, `throttle/morph-end-report.mjs` | 1 value | `.overlap` → `.overlap` (unchanged, never `.lower`) | (a) `cmp_empty_faith`, `cmp_empty_cand`, `cmp_lower_nonempty` | `touch-lock.jsonl` 20-21 | `touchlock.mjs` `cmp`, `touchlock.test.mjs` (replays op `cmp`) |
| `TouchLock.cmpKnown` (new) | none yet (see open 1) | `minSamples` = 1 value | new: `none`, golden word `undecided` | (a) `cmpKnown_empty_faith`, `cmpKnown_empty_cand`, `cmpKnown_short`, `cmpKnown_some_needs` · (b) `cmpKnown_of_known` | `touch-lock.jsonl` 43-49 (op `cmpKnown`) | none: TS stand-in missing (open 1) |
| `TouchLock.look` | TS `touchlock.mjs` `summarize` | 1 value | `.same` → `.same` (unchanged) | none: an empty side reads the same look; use `lookKnown` | `touch-lock.jsonl` 27-28 (added), 26 (both empty) | `touchlock.mjs` `look`, `touchlock.test.mjs` (replays op `look`) |
| `TouchLock.lookKnown` (new) | none yet (see open 1) | `minSamples` = 1 value | new: `none`, golden word `undecided` | (a) `lookKnown_empty_faith`, `lookKnown_empty_cand`, `lookKnown_short`, `lookKnown_some_needs` · (b) `lookKnown_of_known` | `touch-lock.jsonl` 50-56 (op `lookKnown`) | none: TS stand-in missing (open 1) |
| `MorphEndCount.flagVerdict` (checked only, fixed in toolbar-sim-lane) | TS twin `flagVerdict` in `throttle/toolbar-report.mjs` | `minCostWindows` whole Layout/RecalcStyle windows on the base | `.win` → `.undecided` (toolbar-sim-lane); empty cand `.noWin` | (a) `flagVerdict_cost_unknown_not_win`, `unthrottle_no_cost_undecided`, `flagVerdict_empty_cand`, `VerdictEvidence.morphEnd_win_needs_cost` · (b) `flagVerdict_cost_known` | existing rows of toolbar-sim-lane | unchanged; `throttle-toolbar.test.mjs` |
| `Offscreen.verdict` (and `verdictAll`, `judge`) | `OffscreenGolden`; TS `offscreen.mjs` `verdict`, `summarize` | `minRuns` = 3 runs, same positive window, every key | `noData` → `noData` (guard already there) | (a) `noData_of_fewBase`, `noData_of_fewFlag`, `verdict_empty_base`, `verdict_empty_flag`, `gain_needs_runs` · (b) `verdict_of_usable` | `offscreen.jsonl` 32-33 (added), short: existing `few base runs`, `few flag runs` | `offscreen.mjs`; `offscreen.test.mjs` asserts `fewBase(0)`, `fewFlag(0)` |
| `OffscreenWindows.verdictOn`, `armVerdicts` | `OffscreenWindowsGolden`; TS `offscreen-windows.mjs` `armVerdicts`, `summarizeArm` | `minRuns` = 3 runs per window | `noData` → `noData` | (a) `noData_of_fewBase`, `noData_of_fewFlag`, `verdictOn_gain_needs_runs`, `armVerdicts_gain_needs_runs` · (b) `verdictOn_of_usable`, `armVerdicts_of_usable` | `offscreen-windows.jsonl` 27-29 (no base, no flag, two base runs); existing `two flag runs` | `offscreen-windows.mjs`; new test "an arm with no or too few runs is no data in every window" |
| `OffscreenWebKit.verdict`, `zoneVerdicts` | `OffscreenWebKitGolden`; TS `offscreen-webkit.mjs`, `offscreen-webkit-cli.mjs` | `minRuns` = 3 passes and `minVms` = 3 VMs, on both sides | `noData` → `noData` | (a) `noData_of_fewBase`, `noData_of_fewFlag`, `noData_of_fewVmsBase`, `noData_of_fewVmsFlag`, `gain_needs_evidence`, `zoneVerdicts_gain_needs_evidence`, `verdict_empty_base`, `verdict_empty_flag` · (b) `verdict_of_usable`, `verdict_eq_passVerdict`, `zoneVerdicts_eq_pass` | `offscreen-webkit.jsonl` 21-23 (no base, no flag, flag one pass short), 29 (zones, no flag passes) | `offscreen-webkit.mjs`; new test "an empty or short side is no data", zones count 5 |
| `OffscreenWebKit.passVerdict` | TS `offscreen-webkit-cli.mjs` (report column) | `minRuns` = 3 passes (no VM rule, by design: the pass-only column) | `noData` → `noData` | (a) `passVerdict_gain_needs_runs` · (b) by definition (`passUsable` true → `judged`) | same rows as above (`passVerdict` field) | `offscreen-webkit.mjs`, same test |
| `Faithful.regionPass` (`faithful.verdict`) | `Faithful.Wire.opVerdict`; TS `faithful.mjs` `verdictOf` via fwcore | the zone present in both arms | fail → fail | (a) `not_pass_of_absent`, `VerdictEvidence.faithful_regionPass_empty_a`, `faithful_regionPass_empty_r` · (b) unchanged code | `faithful.verdict.jsonl` 13-14 | `faithful.test.mjs` replays all rows through fwcore |

Not edited (outside this task's writes), audited:

| Function | Empty side | Win on empty? |
|---|---|---|
| `WebKitLag.verdict` | `.overlap` (`verdict_empty_left`, `verdict_empty_right`) | no (`.lower` needs both sides) |
| `WkCost.outcome` over `cell` | cells `.overlap`, outcome `.overlap`; no cells `.empty` | no (`outcome_win` needs every cell `.lower`) |
| `SwapWindow.cell` | `.unresolved .noSamples` on any empty side, `.fewSamples` below `minFaithful` = 3 per faithful arm; the candidate needs 1 value | no |
| `NavFixedCounts.flagVerdict`, `zoneVerdict` | a missing arm gives `.unusable .fewVms`; all unusable gives `.undecided` | no on all-empty; open 3 on partly empty |
| `TrajectoryGpu.painGrade` | `none` | no |
| `Fw.Ops.Golden` ops | no op compares base and candidate samples (registry, ledger, console and land ops) | n/a |

## Open

1. `packages/measure-webkit/src/touchlock.mjs` and `test/touchlock.test.mjs` (outside the writes): add `cmpKnown` and
   `lookKnown` replaying ops `cmpKnown`/`lookKnown` of `touch-lock.jsonl`, and let `summarize` use them; then
   `MorphEndCount.cmpBy` and `throttle/morph-end-report.mjs` can switch to `cmpKnown`.
2. `Fw.Faithful.Wire.opVerdict` (outside the writes): a request with `zones: []` passes with no zone judged, and a
   zone with 0 frames and no cells in both arms passes. The guard belongs in `Fw/Faithful/Zone.lean` or `Wire.lean`.
3. `Fw.Parts.NavFixedCounts.armOf` (outside the writes): a win needs one usable cell; unusable cells next to it do not
   make the arm undecided. Whether a partly measured arm may win is a design question.
