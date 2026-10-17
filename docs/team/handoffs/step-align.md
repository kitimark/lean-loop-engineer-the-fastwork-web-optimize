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

Open items
- webkit-quiet also edits webkit-sim.yml / session.mjs: expect a merge conflict in the workflow (jobs `plan`, `sim`).
- Preset/fw on the rewrite arm are still refused by `plan` (default config only).
- `align-classes` step in the workflow has not run on CI yet (only locally on run 39053799594 artifacts); `merge` fails on 3 original VMs
  (census label y=5268 vs 5267, webkit-quiet's area).
- The note's counts come from CI run ids listed there; re-run `gh workflow run webkit-sim.yml -f target=both -f vms=3`.

Read first: the note, then StepAlign.lean doc header, then `align.mjs`.
