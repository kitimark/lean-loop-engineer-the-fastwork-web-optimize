branch: worktree-wf_2ef78aa3-7da-1 (CI branch ci/morph-end-nobounce)
worktree: .claude/worktrees/wf_2ef78aa3-7da-1 (under the repo root)
last commit: 1ccd16b69 (push 1 of at most 2; no second push planned)

CI runs (all at 1ccd16b69):
- toolbar-throttle (Simulator toolbar lane, 8 jobs default + nobounce): 40282634661 running
- lean (push): 40282634743 running
- breakpoint-gate both engines, fw=morph.end.nobounce:on (dispatch): 40282669758 queued
- chromium-counts swipe-touch-v1, rewrite, 3 runs: 40282673015 and 40282681173 (one default, one flag; told apart by fw input) running

Verified: Lean MorphEndNobounce.lean builds (push_at_end_no_write, pin_writes_below, bounce_writes_back, no_write_above_end);
golden morph-end-nobounce.jsonl matches (lean --run scripts/MorphEndNobounceGolden.lean --check); apps/site vitest for the
part and registry green; apps/site typecheck clean; measure-webkit throttle-toolbar test green; triggers.jsonl regenerated.

Built: flag morph.end.nobounce:on (part apps/site/src/parts/morph.end.nobounce, a <style> in App.tsx), look change L, never a preset;
toolbar arm `nobounce` (throttle/toolbar.mjs) and a pin-writes-per-gesture column (toolbar-report.mjs).

Open: read the 3 lanes and write research/notes/2026/10-2x-morph-end-nobounce.md; fill the ledger row (chromium/webkit fields);
run the full package tests, ci-paths and land-inputs tests; merge main, lake build, plan lint, dry land.
Not done by design: push-cycle replay (push-cycle-separate has not landed and the lane has no flag arm on main).

Files outside the task writes: apps/site/src/App.tsx, apps/site/src/registry/index.ts, lean/scripts/MorphEndNobounceGolden.lean
(a root `main` in a Fw module clashes with Main.lean), apps/site footprint (FootprintData.lean, footprint.gen.json, regenerated),
packages/measure-webkit/src/throttle/toolbar.mjs, toolbar-report.mjs and test/throttle-toolbar.test.mjs.
