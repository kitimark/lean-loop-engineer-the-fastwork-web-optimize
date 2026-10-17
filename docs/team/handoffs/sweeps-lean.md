# sweeps-lean handoff

Task sweeps-lean (docs/team/work-graph.json): the gate speed-ups from research/notes/2026/10-18-sweeps-speed.md,
proved in Lean first. State: committed on the worktree branch (see `git log -1`), `sh lean/scripts/check.sh` green.

## What exists
- `lean/Fw/Gate/SweepReduce.lean`: `dropStutter` over the combined key `sweepKey` (30 catalogue + 4 neutral
  queries, x every pilot part key); `reduceSweep_part_history` (same collapsed history for every part key),
  `reduced_scopedVerdict`, `reduced_scope_sound`, `sweepCell_verdict_reduce`; `reducedDeskWidths_eq` (35 stops, from
  57; the 320 turn is dropped), `reducedDesk_ends`, `deskSweep_has_probes`, `reduceSweep_short` (the other 3 sweeps
  keep 5 stops). Caveat: `reduced_desk_tally_ne` (verdict cells equal, counts not: `FAIL 57/57` -> `FAIL 35/35`).
- `lean/Fw/Gate/Merge.lean`: `mergeById` (JS-faithful), `mergeGate` (merge-gate.mjs@2ccc158 today),
  `mergeGateById` (proposed: whole sweeps in any file), `*_eq_unsharded`, `sweeps_ids_nodup`,
  `sharded_verdict_eq`, `split_sweep_changes_verdict` (counterexample: shards hold whole sweeps only).
- `lean/Fw/Gate/Mount.lean`: `mount`, `mount_idem`, `mountOnce_eq_mountEvery` (premise: resizes never unmount;
  page.mjs:184-205@6626359, run.mjs:87-99@7ceb81c).
- `lean/Fw/Wire/GateDeclared.lean`: `partRawOf_setPartDeclared`, `partsOf_setPartsDeclared`,
  `stale_setPartsDeclared`, `armOf_setPartsDeclared` (premise: role maps WF).
- Generator `lean/Fw/Gate/SweepsGen.lean`, dispatched from `lean/BreakgenMain.lean`:
  `lake exe breakgen --sweeps [--check f]`, `--sweeps-golden [--check f]`. Outputs: `lean/Fw/Site/sweeps.gen.json`,
  `apps/site/src/sweeps.gen.json`, `packages/contracts/golden/gate/sweeps.jsonl`; check.sh checks all three.

## Conventions
- Scope.lean untouched (no hook needed). packages/gate-breakpoints untouched: the JS still runs 57 stops.
- `condKey` (not `truthKey`: that name exists in State.lean).

## Open items
- Wire the reduced stops into spec.mjs/run.mjs (gate-speed-impl); update summary text for the new FAIL k/n.
- Mount-once and the `declared` skip are proved but not implemented in page.mjs/run.mjs.
- merge-gate.mjs still needs all sweeps in one file; `mergeGateById` is the target model.

Read first: the module docstrings of SweepReduce.lean and Merge.lean.
