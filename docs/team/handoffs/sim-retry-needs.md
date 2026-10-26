branch: worktree-wf_ad288bf9-c79-1
worktree: .claude/worktrees/wf_ad288bf9-c79-1 (under the main checkout)
last commit: 042fc7850 (main merged at 400007d01); this handoff commit follows it
CI runs: none (the replay used job logs only)
verified at 042fc7850: lean/scripts/check.sh green through `fw slot` (533 s), measure-webkit tests 924/924, ci-paths test, runner land-inputs test, plan lint without writesClosure errors; dry land runs after this commit (verdict in the task report, not here)
open: tab gate at 480 s refuses 9 green jobs (deployed 10 of 98, 1 without it), lead decision; wk-sim-hang note's Lean paragraph outdated (outside writes)

## State
- Lead decision (round 2): the needs are a choice decided in Lean. `lean/Fw/Measure/SimHost.lean`: `Premise`, `pick`, `best_fewest` (no premise-meeting needs refuse fewer), `deployed_premise_unmet`, `best_stop_le`. `lean/Fw/Measure/SimHostGolden.lean`: `jobs`, `best` = (876, 1563, 480) refuses 14 of 98 (`best_refused`), `grid_fewest`, `pick` keeps the shipped needs (`deployed_is_pick`, `shipped_refused` 10).
- `SimHost.scrollNeedS` 589, `passNeedS` 436 (shipped, deployed); `ci_tab_need` states 436 < 480 (model limit); `runPass` keeps the tab gate.
- The `jobs` block of `SimHostGolden.lean` is written from `results/sim-retry-needs/pieces.json` by `results/sim-retry-needs/scripts/lean_data.py` (`--check`); Lean files stay inside the task's writes.
- `sim-host.mjs` reads the needs from `packages/contracts/golden/measure/sim-host.jsonl`.

## Conventions
- Golden: `cd lean && lake build Fw.Measure.SimHostGolden`, then `printf 'import Fw.Measure.SimHostGolden\n#eval Fw.Measure.SimHostGolden.write "../packages/contracts/golden/measure/sim-host.jsonl"\n' | lake env lean --stdin`.
- Data: `python3 -I results/sim-retry-needs/scripts/lean_data.py results/sim-retry-needs/pieces.json lean/Fw/Measure/SimHostGolden.lean [--check]`.
- Replay: `node results/sim-retry-needs/scripts/replay.mjs . results/sim-retry-needs/pieces.json results/sim-retry-needs/replay.json`.

## Read first
`research/notes/2026/10-2x-sim-retry-needs.md` (frontier table), then `SimHost.lean` (`pick`) and `SimHostGolden.lean`.
