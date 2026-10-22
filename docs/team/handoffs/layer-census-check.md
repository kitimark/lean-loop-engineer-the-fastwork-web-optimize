branch: worktree-wf_0892365c-afa-1 (CI branch ci/layer-census-check, not pushed yet)
worktree: .claude/worktrees/wf_0892365c-afa-1
last commit: see `git log -1` (Lean part committed; JS part in progress)
CI runs: none yet

State
- Lean done: lean/Fw/Measure/Census.lean (identity, undeclared multiset, refusals, grid, declared rows; theorems), lean/scripts/CensusGolden.lean,
  golden packages/contracts/golden/measure/census.jsonl (generated, never hand-edit), wired in lean/Fw.lean, lean/scripts/check.sh, lean/Fw/Ci/Trigger.lean (+ regenerated triggers.jsonl).
- Next: JS twin packages/measure-webkit/src/census-check.mjs, WebKit census.mjs fields (fw, layer, origin, rendered), Chromium packages/measure-chromium/src/census.mjs
  (CDP LayerTree), hooks in cli.mjs `determinism` and measure-chromium run.mjs (post-trace, meta.layerCensus), tests in packages/measure-webkit/test/census*.test.mjs.

Conventions
- Identity: data-fw-layer wins over data-fw; empty attr = none; part-only (data-fw) layers are neither undeclared nor box.
- Origins are micro CSS px read in-page (WebKit layer bounds are integer CSS px, InspectorLayerTreeAgent.cpp:189-191@862f17d); dpr in thousandths.
- Refusal order: viewport, samples, undeclared (per sample), then A arm, then B arm.

Open
- CI census runs (WebKit sim original + rewrite, Chromium both) not started.
- Out-of-list edits: lean/Fw.lean, lean/scripts/check.sh, lean/Fw/Ci/Trigger.lean, packages/contracts/golden/ci/triggers.jsonl, cli.mjs, run.mjs.
