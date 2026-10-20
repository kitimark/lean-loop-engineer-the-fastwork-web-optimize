# Handoff: trajectory-probe (round 3)

State: branch worktree-wf_b2d9cca1-299-1, CI branch ci/trajectory-probe (measured code f19913eb / e85d995e; round 3 re-reduced
the same raw artifacts, no new CI run). Results: research/notes/2026/10-21-trajectory-probe.md. Tool doc: docs/team/tools/trajectory-probe.md.
Round 3 : the passes of --reps were concatenated, so every morph window was the whole phase (incident
inc-trajectory-pooled-window). Lean: Samp.rep, windowOne, windowOf = union of per-pass windows, theorems windowOf_pass_iff
(pooling never widens a window), windowOf_none_iff, window_concat_whole_phase; Rel.unmeasured; golden 113 rows incl. rep > 0.
reduce.mjs mirrors it; the reps test (ramping original, stuck rewrite, 2 passes) fails on the old window.

Verified (MEASURED, re-reduced from runs 39409003529, 39415671864, 39412301221, 39419128841): bug A WebKit only (Linux 228,
macos-26 187 new in copy/cta/countdown/deck.card); bug B IS in Chromium (waapi: 205 new nav+logo units, 0 in A/A and the other
two); bug C is baseline `both` (18 units Chromium). Linux WebKit push cells are "no verdict: coverage" (1150-1288 of 2208).
Local at the last commit: lean check.sh, gate-breakpoints, ci-paths and apps/runner tests green.

Conventions
- Lean decides (lean/Fw/Gate/Trajectory.lean); reduce.mjs is the twin, checked against packages/contracts/golden/gate/trajectory.jsonl
  (regenerate: `cd lean && lake build Fw.Gate.Trajectory && lake env lean --run scripts/TrajectoryGolden.lean`, never by hand).
- Dispatch: `pnpm -s fw run --trajectory --ref ci/trajectory-probe [--fw ..|--preset ..]`. The Apple job runs only when the search
  contains hero.exit and engines include playwright-webkit (a preset holding hero.exit: dispatch as --fw).
- Re-reduce artifacts offline: copy raw-<engine>.json to a new dir, `node packages/gate-breakpoints/src/trajectory/cli.mjs summary --out <dir>`.

Open items
1. Bug B in Chromium needs a repeat run (each case ran once) and the same on macOS: extend the Apple job to `--paths hero,morph`
   (Linux WebKit cannot cover the push, 150 ms frames).
2. Faithful rewrite is baseline red in the macos-26 hero path (114 units in d, 54 in b and c): investigate.
3. A default-vs-default run is RED from one empty coverage bucket (42 units at one width in runs a, b): consider reps 5.
4. Touch input, WebKit 325900 premise test, stale anchor exclusions, Mobile Safari, trajectory-probe-speed (parallel widths).
5. Not a gate stage and no preset reads it (by task). Writes outside the graph: see the note (adds docs/team/incidents/ledger.json).

Read first: docs/team/tools/trajectory-probe.md, then the note.
