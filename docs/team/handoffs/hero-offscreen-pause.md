Branch: worktree-wf_c1c23b19-417-1 (ci branch ci/hero-offscreen-pause, pushed at 629f0d982). Worktree: .claude/worktrees/wf_c1c23b19-417-1.
Last commit: 629f0d982 is the pushed tip; later local commits carry only this file. CI runs: trajectory-probe 41157675414 failed at the smoke step (my fault:
FW_SEARCH with two flags is not prerendered; build.mjs enumerates single flags and presets only, so a probe takes one flag). lean lane ran on the push (default lane).
Gate dispatch (lead): pnpm -s fw run --gate --engines both --preset v2-proved --fw hero.accent:offscreen-pause,hero.cue:offscreen-pause,platform.sweep:offscreen-pause --ref ci/hero-offscreen-pause
Verified: Lean OffscreenPause/HeroAccentPause/HeroCuePause build; goldens hero-accent-pause.jsonl, hero-cue-pause.jsonl --check ok; footprint rows/diff/Bridge regenerated
(hero.cue no longer self-independent: 4 rows, 266 chain pairs); preset decisions goldens regenerated (Gen.run []); @fw/site 8513 tests, typecheck, runner 3749, ci-paths 56 pass.
Open: gate run (dispatch item); no probe result for the new flags (one flag per probe, not run); hero.accent/hero.cue variants are exclusive per part, so no combined
steps+pause or draw-one+pause variant (follow-up).
Read first: research/notes/2026/10-31-hero-offscreen-pause.md, lean/Fw/Parts/OffscreenPause.lean, apps/site/src/parts/hero.accent/pause.ts.
Writes outside the task graph: lean/Fw.lean, lean/Fw/Ci/Trigger.lean, lean/scripts/check.sh, lean/scripts/HeroOffscreenPauseGolden.lean, lean/Fw/Parts/{Footprint*,Bridge,OffscreenPauseGolden}.lean,
packages/contracts/golden/{ci/triggers.jsonl,parts/footprint*.json,preset/*.decisions.jsonl,parts/hero-*-pause.jsonl}, research/findings/ledger.json (rows 98, 99).
