# scene-pause-kcopy handoff

- Branch: worktree-wf_6617cda3-14e-1; worktree .claude/worktrees/wf_6617cda3-14e-1
- Last commit: 4e2471228 (pushed as ci/scene-pause-kcopy, push 1 of 3)
- CI runs: trajectory-probe push on ci/scene-pause-kcopy at 4e2471228 (fw=hero:scene-pause, verdict run): running
- Verified: `lake build Fw.Parts.HeroScenePause Fw.Parts.HeroScenePauseOpen Fw.Preset.Gen` OK; standard axioms only;
  golden hero-scene-pause.jsonl regenerated (--check up to date); site test scene.golden.test.ts 56 passed;
  Gen.run --check up to date (hero:scene-pause linked, verdict not-proved: status partly-proved, cells pending).
- Open: y 5267 census to n=3 (webkit-sim dispatch, lead); macOS WebKit morph cell (trajectory dispatch, lead);
  ledger row and note; check.sh; dry land.

## What is where
- `lean/Fw/Parts/HeroScenePause.lean` section 7: `heroAnims` (CSS-read table, replayed by the site test against every
  @keyframes of the hero subtree), `after_splash_copy`, `card_stops`, `threaded_card_after_splash`,
  `hero_paused_hidden_copy`, `hero_paused_same_after_splash`, `kMax_le_kCopy`.
- `lean/Fw/Parts/HeroScenePauseOpen.lean`: the 3 recorded flag runs under the current open@1 rule (`byMFirst`):
  `recorded_open_late`, `recorded_clean`, `red_needs_original`.
- `lean/Fw/Preset/Gen.lean`: link `hero:scene-pause` -> ledger key (hero, candidate text).

## Conventions
- Census dispatch: `pnpm -s fw run --target rewrite --engines webkit --fw hero:scene-pause --ref <ci branch>`; a
  repeated sha is a cache hit, so the two runs need two shas.
- Read first: ledger row hero.scenePause, research/notes/2026/10-20-hero-pause-rule.md.
