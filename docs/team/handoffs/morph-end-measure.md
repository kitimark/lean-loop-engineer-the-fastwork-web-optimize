branch: worktree-wf_c0f9c38f-77f-1 (CI branch ci/morph-end-measure)
worktree: .claude/worktrees/wf_c0f9c38f-77f-1
last commit: CI ran 450596c9a as ci/morph-end-measure; later commits only add the note, results and this handoff
CI runs (3 of 3 dispatches used, all complete):
- 40105567688 (f7a520d09; 4 cycles, 300 s touch limit) failure overall: jobs 1 and 6 gave partial json (rewrite 2, all-unthrottle 1 usable); 12 of 18 attempts timed out; job 5 lost, job 2 cancelled at 80 min.
- 40112979355 (fcb8edf2c; 2 cycles, 480 s) failure: 0 usable passes; 4 runners frozen 60 to 80 min.
- 40126807029 (450596c9a; 4 arms per job, --reset before a retry, 720 s stall limit, max-parallel 3) failure overall: jobs 2, 4, 6 gave data (5 usable passes), jobs 1, 3, 5 lost or cancelled.

Verified: @fw/measure-webkit tests (incl. throttle-morph-end, throttle-finish-page); scripts/ci-paths.test.mjs; runner overflow-widths test. Results: research/notes/2026/10-2x-morph-end-measure.md, results/morph-end-measure/ (per run tables, pooled table, attempts.md).
Answer: no brick measurably cut reversals or fights per open start (n 1 to 10 open starts per arm); engine.scroll:unthrottle alone removes the still runs; release has no data; flip's wobble fix not exercised; clamp not a differentiator (pin below max, INFERRED).
Open: release unmeasured (a fourth dispatch would be a new decision of the lead); phone review step with composer links (lead posts); close/re-open counting is a TS stand-in (no Lean spec).

Design
- Lane: toolbar-throttle.yml finish mode, commit token [throttle:morph-end]: matrix 1-6, 4 arms per job (rewrite plus three of clamp, flip, release, all, all-unthrottle rotated by job), 1 round, 2 cycles, 480 s touch limit, --reset. The site job adds the four-flag page with `build.mjs --config` (throttle/morph-end-search.mjs).
- Recorder (throttle/finish-page.mjs) reads per frame the morph value r, finger direction d, and the instant scrollTo writes (the pin).
- Counts: throttle/morph-end.mjs. Fights, reversals, displaced frames from touchlock.mjs (twin of Lean Fw.Measure.TouchLock); still runs and verdict from finish.mjs (twin of Fw.Device.FinishRuns). Closes and re-opens by finger direction are a TS STAND-IN.
- cli.mjs: retry tag carries the attempt; --timeout; --reset (shutdown of the Simulator before a retry).

Files outside the task writes: .github/workflows/toolbar-throttle.yml, packages/measure-webkit/src/throttle/{cli,finish-page}.mjs, new morph-end.mjs, morph-end-report.mjs, morph-end-search.mjs, tests test/throttle-morph-end.test.mjs and test/throttle-finish-page.test.mjs, apps/runner/test/land-overflow-widths.test.ts (dynamicMax toolbar-throttle/sim 6). lean/Fw/Ci/Overflow.lean is net zero against main.
Read first: research/notes/2026/10-2x-morph-end-measure.md, then this file.
