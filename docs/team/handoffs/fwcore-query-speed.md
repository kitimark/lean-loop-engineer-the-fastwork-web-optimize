# fwcore-query-speed handoff

State: branch worktree-wf_ae566a3d-aed-1 (commit in the report). `console.query` at 4x: 33.3 s -> 0.23 s, output byte-identical.
- `lean/Fw/Plan/FastView.lean`: `fastCriticalPath`, `groupsF`, `fastView` (`fastView_eq`). `lean/Fw/Plan/FastBound.lean`: `boundF`
  (`boundF_eq`). `Fw.Serve` query uses `fastView`. The old `view`, `criticalPath`, `groups`, `bound` stay as the spec.
- Scripts: `lean/scripts/{scale-log,synth-log,query-time}.mjs`, `query-golden.sh <old> <new> <logs>`, `QueryProfile.lean`
  (compiled use is in its header; the temporary lakefile entry is not committed).
- Note: research/notes/2026/10-20-fwcore-query-speed.md (cause, table, proofs). docs/team/tools/console.md updated.
Lead after landing: rebuild fwcore (`sh scripts/fwcore-build.sh`), restart console, DROP FW_CORE_CALL_MS=60000.
Open: replay of a deep dependency chain is slow (checkFast follows all ancestors per define); `groupsF` and `cleared` stay
quadratic (small at 4x). Writes outside the task graph: none known.
Convention: keep indexes in a data structure passed to a `@[noinline]` function, never in `let`s inside lambdas.
