branch: worktree-wf_41867f2b-b5a-1 (CI branch ci/morph-real-wheel-followups, pushed at bba5ad159)
worktree: .claude/worktrees/wf_41867f2b-b5a-1 (in the repo checkout)
CI run (smoothness.yml, webkit-mac jobs 1..3, macos-26, Playwright WebKit 27.2): 39989441570, success
State: all five items handled; main merged; checks below green on the merged tree.

Verified
- Lean `check.sh` green (slot); `@fw/measure-webkit` tests 468/468; `scripts/ci-paths.test.mjs` 56/56; apps/runner land-inputs 56/56.
- `fw land --dry` ends `VERDICT dry morph-real-wheel-followups`.
- `plan lint`: 0 errors; the only line naming this task is `longTitle` (graph title, not edited by me).
- Run 39989441570, MEASURED: 36 of 36 scrollin runs accepted (0 of 108 refused); pushY - startY = 300 and 3 trusted scroll wheels in every one; --morph reached 1.
  Open phase, orig, scrollin vs synthetic: RecalculateStyles lower in 3/3 jobs, Layout lower in jobs 1 and 3; rewrite none. Close: none. Per-job verdicts, never pooled.

Done in code
- (1) report.mjs geometry index per run phase offset (Lean geometryIndex), test/lag-morph-followups.test.mjs (marks 13/57).
- (2) macmorph.mjs drive `scrollin` (start maxY-300, trusted wheels, then the push); acceptance in Lean acceptScrollIn.
- (4) Lean jobVerdicts/tally (WebKitLag.lean) + golden; macreport.mjs per job.
- (5) probe.mjs docstring cut by hand.
- (3) Simulator leg: followUp, waits for sim-touch-reliable (not on main).

Conventions: golden is regenerated from Lean (`lake env lean --run scripts/WebkitLagGolden.lean`), never hand-edited. smoothness.yml unchanged.
Read first: research/notes/2026/10-2x-morph-real-wheel.md (follow-up section), lean/Fw/Measure/WebKitLagPhase.lean, packages/measure-webkit/src/lag/macmorph.mjs, macreport.mjs.
