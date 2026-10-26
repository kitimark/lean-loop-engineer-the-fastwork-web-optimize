# morph-stage handoff (lead, after stopping the first builder near its context limit)
state: work in progress, uncommitted work committed as-is by the lead (WIP commit on branch worktree-wf_f50338a2-351-1); no CI push yet.
on disk: lean/Fw/Parts/MorphStage.lean (348 lines), MorphStageGolden.lean, lean/scripts/MorphStageGolden.lean, golden packages/contracts/golden/parts/morph-stage.jsonl; apps/site/src/parts/morph.stage/ (driver.ts, index.tsx, logic.ts, part.json, track.tsx, stage.module.css, stage.component.test.ts, stage.golden.test.ts); edits to App.tsx, registry/index.ts, Fw.lean, Trigger.lean, check.sh.
last activity: a local Playwright debug script (scratchpad dbg.mjs, not in the repo) showed in Chromium 1280x800 with ?fw=morph.stage:on a sticky track of 696-768 px, --morph reaching 1 and the nav expanded at the end (y 8490); the builder was about to run the same check in WebKit (Playwright) when stopped.
not verified: lake build of MorphStage*, check.sh, site tests, golden replay, gate, Chromium counts, WebKit runs.
read first: the task row in docs/team/work-graph.json, research/notes/2026/10-26-end-scroll-designs.md, then the files above.
