Branch: worktree-wf_c1c23b19-417-1 (ci branch ci/hero-offscreen-pause, not yet pushed). Worktree: .claude/worktrees/wf_c1c23b19-417-1.
Last commit: see `git log -1` on the branch. CI runs: none yet. Gate dispatch (lead): pnpm -s fw run --gate --engines both --preset v2-proved --fw hero.accent:offscreen-pause,hero.cue:offscreen-pause,platform.sweep:offscreen-pause --ref ci/hero-offscreen-pause
Verified: Lean OffscreenPause/HeroAccentPause/HeroCuePause build; goldens hero-accent-pause.jsonl, hero-cue-pause.jsonl --check ok; footprint rows/diff/Bridge regenerated
(hero.cue no longer self-independent: 4 rows, 266 chain pairs); preset decisions goldens regenerated (Gen.run []); site tests for hero.accent and hero.cue pass.
Open: gate run (dispatch item); hero.accent/hero.cue variants are exclusive per part, so no combined steps+pause or draw-one+pause variant (follow-up).
Read first: research/notes/2026/10-31-hero-offscreen-pause.md, lean/Fw/Parts/OffscreenPause.lean, apps/site/src/parts/hero.accent/pause.ts.
Writes outside the task graph: lean/Fw.lean, lean/Fw/Ci/Trigger.lean, lean/scripts/check.sh, lean/scripts/HeroPauseGolden.lean, lean/Fw/Parts/{Footprint*,Bridge,HeroPauseGolden}.lean,
packages/contracts/golden/{ci/triggers.jsonl,parts/footprint*.json,preset/*.decisions.jsonl,parts/hero-*-pause.jsonl}, research/findings/ledger.json (rows 98, 99).
