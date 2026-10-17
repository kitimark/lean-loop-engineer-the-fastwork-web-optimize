# Handoff: step-align (WebKit original vs rewrite by scroll position)

State: branch worktree-agent-a916f9841bd5d6301, commit e0fa48c (+ follow-ups); CI branch ci/step-align. Results: see
`research/notes/2026/10-18-step-align.md`.

Cause of 74 vs 107 steps: page height only (original docH 6042 / 107 steps; placeholder rewrite docH 4378 / 74 steps;
same 50 px step, each run scrolls to its own maxY). Not a harness bug, so the schedule was not changed.

What was built
- `lean/Fw/Measure/StepAlign.lean`: steps keyed by (prev y, y, next y); `pairedSteps`; `align` zones (500 px) with
  A and B sums over paired steps, delta A-B, `full` flag (zone comparable as a whole). Proved: partition of the paired
  sums over zones, delta total, swap symmetry, self-alignment (all zones full, delta 0).
- Wire op `measure.webkit.align` (Wire.lean), 7 goldens in `packages/contracts/golden/measure/measure.webkit.align.jsonl`.
- `packages/measure-webkit/src/align.mjs` (glue) + `cli.mjs align <a.json> <r.json>` + `test/align.test.mjs`.
- `.github/workflows/webkit-sim.yml`: target original|rewrite|both. Rewrite arm = jobs r1..rN (site job builds
  apps/site default config, `--site` flag); original keeps v1..vN and file names; `merge` takes only v*; `align`
  job (ubuntu, fwcore artifact) pairs vN/rN per session. Default push still runs original only.

Conventions: Lean first (decisions in Lean, JS prints), goldens regenerate with `lake env lean --run
scripts/MeasureGolden.lean` from `lean/`; mathview lint 0 failing.

Merge across VMs (second round): rows are paired by key, in Lean (`StepAlign.pairedRows`/`unpairedRows`, op
`measure.webkit.pairRows`, 6 goldens, proofs `mem_pairedRows`, `pair_cover`, `unpairedRows_count`, `pair_self`).
`src/mergerows.mjs` + `cli.mjs merge` print paired rows (worst class) then unpaired rows ("k of n sessions" + reason);
`--out` has `unpaired`. Test `test/mergerows.test.mjs` (VM2 y=5268 fixture). The `merge` job needs the fwcore artifact
(fwcore job now runs when original is built). webkit-quiet conflict in webkit-sim.yml resolved as a union (quiet is
original-only: plan refuses quiet with another target).

Open items
- Preset/fw on the rewrite arm are still refused by `plan` (default config only).
- With one VM 1 px taller the end-of-page census state rows are excluded from the merged table (by design, reported).
- CI result of ci/step-align after the merge fix: see the note and the lead's report.

Read first: the note, then StepAlign.lean doc header, then `align.mjs`.
