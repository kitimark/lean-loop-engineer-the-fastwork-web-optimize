# morph-panel-threaded (part-builder)

Branch `worktree-wf_65d039ea-8f9-1`, worktree `.claude/worktrees/wf_65d039ea-8f9-1`, CI branch `ci/morph-panel-threaded`, code sha f0273f680.

CI runs (all on ci/morph-panel-threaded @ f0273f680):
- breakpoint-gate 39846842455 (`--gate --engines both --fw morph.panel:threaded`): running
- trajectory-probe 39846814254 (push run, `fw=morph.panel:threaded`, all four widths): running
- lean 39846814246 (push): running
- webkit-sim cost lane (`lag=true cost=on vms=3`): 39846909558 threaded alone, 39846941236 const-bounds, 39846948148 bundle
  (threaded + platform:fade-threaded): running; ids from creation order, confirm with the run's inputs
- chromium-counts (swipe-wheel-v1, 3 runs) const-bounds and threaded: dispatched by `fw run`, logs in the scratchpad, ids pending

Verified: `sh lean/scripts/check.sh` not yet run at this sha; Lean files compile alone (`lake env lean`), site tests of
morph.panel, morph.tween and platform pass, `tsc --noEmit` clean, golden `morph-panel-threaded.jsonl` equals the Lean output.

Open: results of the runs above; ledger row, note, results/morph-panel-threaded/**; full check.sh, site package test,
ci-paths and land-inputs tests; dry land.

Conventions:
- Lean: `MorphPanelThreaded.lean` (keyframes, interp_eq, bands, work, layer budget, writes), `MorphPanelThreadedRun.lean`
  (state machine, ca_accepts, retarget_from_shown, ease_err), `MorphPanelThreadedGolden.lean` (golden by `#guard`).
  Golden regen: copy the Golden file without the `include_str` line to the scratchpad, add `def main : IO Unit :=
  IO.print (Fw.Parts.MorphPanelThreaded.jsonl)`, `lake env lean --run`.
- Site: keyframes in `morph.panel/threaded.logic.ts`; the tween owns the animate calls (`createPanelEffects` in
  `morph.tween/driver.ts`) so the footprint writes sit with the tween that already targets other parts. Flag is read from
  `window.__fw.config.variants['morph.panel']` in `morph.tween/index.tsx`.
- The footprint now shows the tween writing morph.panel, so morph.panel is no longer isolated: `Bridge.lean` literals
  (codeAdj, isolated 13 to 12, chain counts) were regenerated with a `#eval` of the same defs. Run `part-footprint.mjs
  --write`, rebuild `Fw.Parts.Contract`, then `ContractsGolden --rows` and `--diff` (rebuild between each) after any source edit.

Read first: `research/notes/2026/10-2x-morph-panel-threaded.md`, `lean/Fw/Parts/MorphPanelThreadedRun.lean`.
