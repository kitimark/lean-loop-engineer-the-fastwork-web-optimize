branch: worktree-wf_8a0bfbaa-969-1 (CI branch ci/toolbar-wktr-gate, tip d844b58ce)
worktree: .claude/worktrees/wf_8a0bfbaa-969-1 (inside the repo checkout)
last commit: see `git log -1` (main merged after the CI push; the measured files are unchanged by the merge)
CI runs: wktr run 40223882394 complete, success (j1 121261187478, j2 121270271999, j3 121273069630, each VERDICT toolbar-gate pass); lean run 40223882417 success. Pushes used: 1 of 3.
verified: hooks CONFIRMED (nm count 1 each, typeof function in 24 of 24 reports); per flag arms, takes and exemption equal the Lean gate golden in 3 jobs x 2 passes
open: none. After merging main (r493): check.sh green, @fw/runner test 113 files green, ci-paths test 56 pass, dry VERDICT dry toolbar-wktr-gate, review ready VERDICT review-ready toolbar-wktr-gate review. Report: scratchpad/twg/report.json

State
- Fixture page packages/measure-wktr/src/toolbar-page.mjs, driver toolbar-cli.mjs, verdict gate.mjs, symbol check scripts/hook-check.sh.
- Lean: Fw.Parts.MorphMountToolbar "The WKTR forced-inset gate" (Flag, per-flag theorems, gate runs, liftedBelowMs = throttleMs/2).
- Golden: packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl (221 rows, from MorphMountToolbarGolden.runGolden --gate). A separate file, because gesture.test.ts conformance needs a TS impl for every fn in morph-mount-toolbar.jsonl.
- wktr.yml: `[toolbar]` marker (or dispatch input toolbar) runs 3 jobs x 2 passes, no class counts.
- apps/runner/src/land.ts PACKAGE_EXTRA_READS for packages/measure-wktr declares the golden, morph.mount/**, unthrottle.ts (outside the task writes).

Conventions
- Measured waits: throttled flags 81-83 ms, unthrottle 32-33 ms, bound 50 ms. Limits: step-wise sets, lvh/svh not overridden, WKTR is not Safari.
- The macos-26 queue took 30 min before j1 started; the three jobs run serially (max-parallel 1), about 40 min in all.

Read first: research/notes/2026/10-2x-toolbar-wktr-gate.md, then packages/measure-wktr/README.md "Toolbar forced-inset gate".
