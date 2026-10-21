# waapi-tail-webkit handoff (phase 1 of 2: source and instrument)

State: branch worktree-wf_79c0837e-67c-1, pushed as ci/waapi-tail-webkit (commit in the report). No measurement claim yet.
Read first: research/notes/2026/10-21-waapi-tail-webkit.md (WebKit mechanism table @862f17d, candidates C1-C4 and
C-probe with the rows each predicts, the recorder, the plumbing gap).

What exists:
- Recorder: apps/site/src/debug/nav-transition.ts, wired in apps/site/src/parts/nav/index.tsx (import + one call + cleanup).
  Off unless the URL has `fw-debug=nav-transition`; never reads layout or style. Tests: nav-transition.test.ts (21).
- Probe: packages/gate-breakpoints/src/trajectory/{debug.mjs,debug.requests.json,run.mjs,plan.mjs}. Rows land in
  `runs[].morph.debugReps` of raw-<engine>.json (leg artifact out/trajectory). Tests: test/debug.test.mjs.
- Footprint regenerated (`node apps/site/scripts/part-footprint.mjs --write`): footprint.gen.json and FootprintData.lean,
  line numbers only. The debug module sits outside src/parts/ on purpose (a file inside nav/ adds clock reads).

LANDING HAZARD: the row in debug.requests.json makes every dispatched run of `?fw=morph.tween:waapi` record rows. Remove
it with the phase 2 report (the row's `remove` field says so). The request commit must stay at the worktree HEAD
(`fw run` compares the run's head SHA to HEAD).

TS stand-ins (no Lean spec, debug only): navDebugOn, installNavTransitionDebug, debugFor, withDebug, readDebug.
Writes outside the graph's list: apps/site/src/debug/**, apps/site/src/parts/nav/index.tsx, the four probe files above,
footprint.gen.json, FootprintData.lean, packages/gate-breakpoints/test/debug.test.mjs.

Verified at the commit: site test + typecheck, gate-breakpoints test (441), ci-paths test, runner land-inputs test,
part-footprint --check, lean/scripts/check.sh.

Open: phase 2 = dispatch (below), read the rows around each `cls` row (order of data/cls/base, `tr` rows, size/raf between),
match to the candidate table, then class counts over >= 3 runs on separate jobs. Remove the request row in that report.
Dispatch: pnpm -s fw run --trajectory --engines playwright-webkit --fw morph.tween:waapi --widths 1280 --ref ci/waapi-tail-webkit
