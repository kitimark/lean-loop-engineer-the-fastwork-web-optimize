branch: worktree-wf_ad288bf9-c79-1
worktree: .claude/worktrees/wf_ad288bf9-c79-1
last commit: b6b7017c9 (main merged); this handoff commit follows it
CI runs: none
verified at b6b7017c9: lean/scripts/check.sh green through `fw slot` (212 s), measure-webkit tests 931/931, ci-paths test 56/56, runner land-inputs test 73/73, plan lint without writesClosure errors; dry land runs after this commit (verdict in the task report)
open: tab wait capped to the time left (follow-up); wk-sim-hang note's Lean paragraph outdated (outside writes)

## State
- Lead decision (round 2): the needs are a choice decided in Lean. `lean/Fw/Measure/SimHost.lean`: `Premise`, `pick`, `best_fewest` (no premise-meeting needs refuse fewer), `untabbed_fewest` (same without tab cover), `deployed_premise_unmet`, `best_stop_le`. `lean/Fw/Measure/SimHostGolden.lean`: `jobs`, `best` = (876, 1563, 480) refuses 14 of 98 (`best_refused`), `grid_frontier` (split premise columns; (876, 1563, 0) refuses 9), `pick` keeps the shipped needs (`deployed_is_pick`, `shipped_refused` 1).
- Lead decision (round 3): no tab gate. `deployed` and `shipped` have tab need 0; `navigateTab` in `wip.mjs` has no gate. `SimHost.scrollNeedS` 589, `passNeedS` 436; `runPass`, `tab_started_le`, `tabFits` stay model results for a later wait cap.
- The `jobs` block of `SimHostGolden.lean` is written from `results/sim-retry-needs/pieces.json` by `results/sim-retry-needs/scripts/lean_data.py` (`--check`).
- `sim-host.mjs` reads the needs from `packages/contracts/golden/measure/sim-host.jsonl`.

## Conventions
- Golden: `cd lean && lake build Fw.Measure.SimHostGolden`, then `printf 'import Fw.Measure.SimHostGolden\n#eval Fw.Measure.SimHostGolden.write "../packages/contracts/golden/measure/sim-host.jsonl"\n' | lake env lean --stdin`.
- Data: `python3 -I results/sim-retry-needs/scripts/lean_data.py results/sim-retry-needs/pieces.json lean/Fw/Measure/SimHostGolden.lean [--check]`.
- Replay: `node results/sim-retry-needs/scripts/replay.mjs . results/sim-retry-needs/pieces.json results/sim-retry-needs/replay.json`.

## Read first
`research/notes/2026/10-2x-sim-retry-needs.md` (frontier table), then `SimHost.lean` (`pick`) and `SimHostGolden.lean`.
