Branch: worktree-wf_c1c23b19-417-1 at 0949cf26b (ci branch ci/hero-offscreen-pause; site code last changed in 9a55ed63e, the pending-play guard). Worktree: .claude/worktrees/wf_c1c23b19-417-1.
Gate: breakpoint gate both engines, each flag alone, at 9a55ed6: run 41162953722 (hero.accent:offscreen-pause) success, run 41168068169 (hero.cue:offscreen-pause) success; 41162980513 cancelled (one WebKit job hung). A multi-flag gate cannot run (single flags and presets are prerendered only). Trajectory probe 41157675414 failed at smoke for the same reason.
Verified: Lean OffscreenPause/HeroAccentPause/HeroCuePause build; goldens hero-accent-pause.jsonl, hero-cue-pause.jsonl --check ok; footprint rows/diff/Bridge regenerated
(hero.cue no longer self-independent: 4 rows, 266 chain pairs); preset decisions goldens regenerated (Gen.run []); @fw/site 8513 tests, typecheck, runner 3749, ci-paths 56 pass.
Open: multi-flag gate (tooling follow-up); no probe result for the new flags (one flag per probe, not run); hero.accent/hero.cue variants are exclusive per part, so no combined
steps+pause or draw-one+pause variant (follow-up).
Read first: research/notes/2026/10-31-hero-offscreen-pause.md, lean/Fw/Parts/OffscreenPause.lean, apps/site/src/parts/hero.accent/pause.ts.
Writes outside the task graph: lean/Fw.lean, lean/Fw/Ci/Trigger.lean, lean/scripts/check.sh, lean/scripts/HeroOffscreenPauseGolden.lean, lean/Fw/Parts/{Footprint*,Bridge,OffscreenPauseGolden}.lean,
packages/contracts/golden/{ci/triggers.jsonl,parts/footprint*.json,preset/*.decisions.jsonl,parts/hero-*-pause.jsonl}, research/findings/ledger.json (rows 98, 99).
