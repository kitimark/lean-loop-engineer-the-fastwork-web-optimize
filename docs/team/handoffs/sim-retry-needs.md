branch: worktree-wf_ad288bf9-c79-1
worktree: .claude/worktrees/wf_ad288bf9-c79-1 (under the main checkout)
last commit: see `git log -1` on the branch (Lean choice at 1322fd5dc, note at 1cc49e174)
CI runs: none (the replay used job logs only)
verified: see the task report for check.sh, measure-webkit tests and the dry land at the final commit
open: tab gate at 480 s refuses 9 green jobs (deployed 10 of 98, 1 without it), lead decision; wk-sim-hang note's Lean paragraph outdated (outside writes)

## State
- Lead decision (round 2): the needs are a choice decided in Lean. `lean/Fw/Measure/SimRetryChoice.lean`: `Premise`, `best` = (876, 1563, 480) refuses 14 of 98 (`best_refused`), no premise-meeting needs refuse fewer (`best_fewest`, `grid_fewest`), `pick` keeps the shipped needs (`deployed_is_pick`), `deployed_premise_unmet`, `best_stop_le`.
- `SimHost.scrollNeedS` 589, `passNeedS` 436 (shipped, deployed); `ci_tab_need` states 436 < 480 (model limit); `runPass` keeps the tab gate.
- `lean/Fw/Measure/SimRetryData.lean` is generated from `results/sim-retry-needs/pieces.json` by `results/sim-retry-needs/scripts/lean_data.py` (`--check`).
- `sim-host.mjs` reads the needs from `packages/contracts/golden/measure/sim-host.jsonl`.

## Conventions
- Golden: `cd lean && lake build Fw.Measure.SimHostGolden`, then `printf 'import Fw.Measure.SimHostGolden\n#eval Fw.Measure.SimHostGolden.write "../packages/contracts/golden/measure/sim-host.jsonl"\n' | lake env lean --stdin`.
- Data: `python3 -I results/sim-retry-needs/scripts/lean_data.py results/sim-retry-needs/pieces.json lean/Fw/Measure/SimRetryData.lean [--check]`.
- Replay: `node results/sim-retry-needs/scripts/replay.mjs . results/sim-retry-needs/pieces.json results/sim-retry-needs/replay.json`.

## Read first
`research/notes/2026/10-2x-sim-retry-needs.md` (frontier table), then `SimRetryChoice.lean`.
