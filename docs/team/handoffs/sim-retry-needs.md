branch: worktree-wf_ad288bf9-c79-1
worktree: .claude/worktrees/wf_ad288bf9-c79-1 (under the main checkout)
last commit: see `git log -1` on the branch (Lean cleanup at 2811d44f0, note and replay at 434ed3c99)
CI runs: none (the replay used job logs only)
verified: Lean SimHost/SimHostGolden build, golden regenerated and checked; lean/scripts/check.sh and the measure-webkit tests through `fw slot`; ci-paths test; runner land-inputs test; plan lint 0 errors; dry land (see `fw land --dry` output in the report)
open: lead decision on the price (14 of 98 green jobs refused by the derived gates against 1 with the shipped needs); wk-sim-hang note's Lean paragraph outdated (outside writes)

## State
- `lean/Fw/Measure/SimHost.lean`: `Seen.headS` 687, `Seen.tryS` 876 (from the green job logs); `scrollNeedS` 876, `passNeedS` 1563; `runPass` has the tab gate (`PassTry.nav`, `tabS`, need `tab`); theorems `runPass_stop_le`, `needs_meet_premise`, `deployed_stop_le`, `shipped_needs_missed`, `runPass_tab_refused`, `tab_refused_no_pass_retry`, `ci_tab_need`, `last_admitted`, `retry_after_warm`.
- `sim-host.mjs` reads all constants from `packages/contracts/golden/measure/sim-host.jsonl`; `navigateTab` refuses a wait that does not fit (`tabFits`, default gate `stepGate()`).
- Replay: `results/sim-retry-needs/replay.json` (arms derived, derivedNoTab, shipped, derivedFromServing), pieces in `pieces.json`.

## Conventions
- Golden: `cd lean && lake build Fw.Measure.SimHostGolden`, then `printf 'import Fw.Measure.SimHostGolden\n#eval Fw.Measure.SimHostGolden.write "../packages/contracts/golden/measure/sim-host.jsonl"\n' | lake env lean --stdin`.
- Replay: `python3 -I scripts/fetch.py <jobs.json> <dir>`, `pieces.py <dir>/logs <jobs.json> pieces.json`, `node scripts/replay.mjs <repo> pieces.json replay.json`.

## Read first
`research/notes/2026/10-2x-sim-retry-needs.md`, then `SimHost.lean` (`runPass`, `deployed_stop_le`).
