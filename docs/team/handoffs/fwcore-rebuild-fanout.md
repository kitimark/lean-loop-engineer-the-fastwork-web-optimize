# fwcore-rebuild-fanout handoff

State: branch `worktree-wf_e007c264-660-2`; WIP 54d2e618 (Lean + split), 812f2109 (note draft), merge of main 7237be53,
probe results 9fe3f50d, this handoff on top. `sh lean/scripts/check.sh` green at the final commit.

Delivered
- `lean/Fw/Ops/Rebuild.lean`: `rebuildSet?` (cone of `Main` meet importers of the changed modules) with `rebuildSet?_spec`,
  `trace_changes`, `lake_rebuilds_in_changed_cone`, `critical`, `critical_le_makespan`; `#guard`s on a 5-module sample.
- `lean/scripts/RebuildGolden.lean` + check.sh job `rebuild golden check`: golden `packages/contracts/golden/ops/rebuild.jsonl`
  from `rebuild-facts.jsonl` (Lake's own graph via `lake query --json +M:imports`, CI built lists and step times).
  10 rows (8 lands + 2 probe runs); every computed rebuild set equals what CI built.
- Split: `lean/Fw/Wire/SchedJson.lean` holds the six JSON helpers; `Fw.Wire.Obs` imports it instead of `Fw.Wire.Sched`.
- Note `research/notes/2026/10-21-fwcore-rebuild-fanout.md`: per-land table, mechanism (Lake `Module.lean` lines @eb6cafb),
  fan-out root (`Fw`, 208 imports, pulled into `Main` by FwTest/{Lease,Golden,Serve}; critical module `Fw.Wire.Obs`, 173-182 s).

Verified (MEASURED, CI): paired land runs on the same `Fw.Store.Layout` edit, each restoring an entry of its own seed tree:
control 39542326806 `fwcore build` 208-218 s per leg (Obs 173 s), split 39542291992 41-45 s; run wall 493 s vs 305 s.
Probe branches `ci/land-fanout-split`, `ci/land-fanout-ctl` stay on origin as evidence (their edit commits are not for main).

Open
- First land after the split restores a pre-split main entry and rebuilds `Fw.Wire.Obs` once.
- `Fw.Ci.Telemetry` still imports `Fw.Wire.Sched` for three helpers (could import SchedJson).
- `lean/scripts/check-partial.sh` lists `Fw/Wire/Sched.lean` but not `Fw/Wire/SchedJson.lean`.
- lean.yml trigger row (`lean/Fw/Ci/Trigger.lean`) does not list `golden/ops/rebuild*.jsonl`; a facts-only edit runs no lean CI.
- Moving the `Fw.Wire.Obs` round-trip theorems out of `Main`'s closure would remove its 173 s from Obs-cone lands too.

Read first: the note's last section, then `rebuildSet?_spec` in `lean/Fw/Ops/Rebuild.lean`.
Scratch graph dumper (not committed): `lake query --json +M:imports` per module, BFS from `Main`, Init/Lean/Std/Lake dropped.
