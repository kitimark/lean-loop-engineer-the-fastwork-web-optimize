branch: worktree-wf_c0f9c38f-77f-1 (CI branch ci/morph-end-measure)
worktree: .claude/worktrees/wf_c0f9c38f-77f-1
last commit: f7a520d09 (pushed as ci/morph-end-measure)
CI runs (1 of 3 dispatches used): 40105567688 toolbar-throttle, push of f7a520d09 with [ci:toolbar-throttle] [throttle:morph-end]: running

Verified so far: @fw/measure-webkit tests 645 pass (incl. throttle-morph-end, throttle-finish-page); scripts/ci-paths.test.mjs 56 pass; a local debug run (not a result) of two arms in the Simulator showed the recorder reads (r, d, ca) and the table works; the four-flag page is prerendered with `--config` (site build log checked locally).
Open: wait for 40105567688; tables into research/notes/2026/10-2x-morph-end-measure.md and results/morph-end-measure/; runner land-inputs test; fw plan lint; dry land; review ready.

Design
- Lane: toolbar-throttle.yml finish mode, commit token [throttle:morph-end] = six jobs (matrix 1-6), one pass per arm, six arms (rewrite = faithful, clamp, flip, release, all = preset morph-end-all, all-unthrottle = three bricks + engine.scroll:unthrottle), arm order rotated by job number (--offset). The site job adds the four-flag page with `build.mjs --config` (throttle/morph-end-search.mjs).
- Recorder (throttle/finish-page.mjs) now also reads per frame the morph value r, finger direction d, and the instant scrollTo writes (the pin) with the frame index.
- Counts: throttle/morph-end.mjs. Fights, reversals, displaced frames per open stretch come from touchlock.mjs (twin of Lean Fw.Measure.TouchLock); still runs and the verdict from finish.mjs (twin of Lean Fw.Device.FinishRuns). Closes and re-opens by finger direction are a TS STAND-IN (no Lean spec).
- cli.mjs: retry tag carries the attempt (`<arm>-r<round>-a<attempt>`), fixing the -resultBundlePath collision.

Files outside the task writes: .github/workflows/toolbar-throttle.yml, packages/measure-webkit/src/throttle/{cli,finish-page}.mjs, new morph-end.mjs, morph-end-report.mjs, morph-end-search.mjs, tests test/throttle-morph-end.test.mjs and test/throttle-finish-page.test.mjs.
Read first: research/notes/2026/10-2x-morph-end-measure.md (when written), then this file.
