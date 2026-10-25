branch: worktree-wf_8a0bfbaa-969-1 (CI branch ci/toolbar-wktr-gate)
worktree: .claude/worktrees/wf_8a0bfbaa-969-1 (inside the repo checkout)
last commit: 5896907d1 (CI branch tip d844b58ce); main merged locally, not pushed
CI runs: push 1 of 3 (d844b58ce) -> wktr run 40223882394 still queued after 30 min (j1 waiting for a macos-26 runner; max-parallel 1); lean run 40223882417 running
verified: Lean module builds, check.sh green, ci-paths test 56/56, land-inputs 73/73, measure-wktr toolbar tests 13/13 (local, not a result)
open: CI hook-presence verdict with run id, per-flag gate verdict over 3 jobs x 2 passes, research note, main merge, plan lint, dry land, review ready

State
- Fixture page packages/measure-wktr/src/toolbar-page.mjs, driver toolbar-cli.mjs, verdict gate.mjs, symbol check scripts/hook-check.sh.
- Lean: Fw.Parts.MorphMountToolbar "The WKTR forced-inset gate" (Flag, per-flag theorems, gate runs, liftedBelowMs = throttleMs/2).
- Golden: packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl (221 rows, from MorphMountToolbarGolden.runGolden --gate). A separate file, because gesture.test.ts conformance needs a TS impl for every fn in morph-mount-toolbar.jsonl.
- wktr.yml: `[toolbar]` marker (or dispatch input toolbar) runs 3 jobs x 2 passes, no class counts.
- land.ts PACKAGE_EXTRA_READS for packages/measure-wktr declares the golden, morph.mount/**, unthrottle.ts.

Conventions
- Local debug run (one, released lock) showed lifted wait ~32 ms vs throttled ~80 ms, bound 50 ms. Never a result.
- If CI waits straddle 50 ms: change liftedBelowMs in Lean, regenerate the gate golden (runGolden --gate), push 2.
- Limits: setObscuredInsets is step-wise; lvh/svh not overridden in WKTR; WKTR is not Safari.

Read first: packages/measure-wktr/README.md "Toolbar forced-inset gate", then gate.mjs header.
