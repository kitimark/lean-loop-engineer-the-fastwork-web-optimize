# hero-pause-rule handoff

## State
- Branch `worktree-wf_27d7c8bb-7e0-2`, round 2; the commit that adds this file is the final state.
  CI branch `ci/hero-pause-rule`.
- Flag `hero:scene-pause` (part.json variant `scene-pause`, optimized, T0): the hero track gets `data-fw-hero-scene`
  from `watchActive` (rootMargin `100% 0px`); the paused track sets `will-change: auto` and
  `animation-play-state: paused`, as the original does for every scene.

## Verified
- Lean `lean/Fw/Parts/HeroScenePause.lean`: `heroScene_eq_original`, `paused_frame_same`, `visSame_original`,
  `hero_paused_drop` (85 to 0, WebKit Normal), `hero_wc_paint_same`, `stage_fits`, `kMax_pos`, `kCopy_ge`,
  `hero_paused_hidden` (every paused hero box off-screen at all 124 probes within `kMax`). Standard axioms only.
- `sh lean/scripts/check.sh` exit 0 (54 s); site typecheck and tests green.
- MEASURED: census 39548856639 (will-change reason 91 to 6 against the morph.mount:shift baseline 39309416016),
  gate 39549161028 pass on both engines, trajectory 39548822269 and rerun 39553952680 (WebKit clean; Chromium red
  only on the nav morph at 390, open@1 coverage).

## Open
- Look change (all hero CSS animations, listed in part.json `limit`): user's visual review; lead may set visClass L.
- Chromium nav morph trajectory red at 390: own task. Census rerun for y 5267 (n = 1): lead dispatch.
- `deferRendering` (`content-visibility`) not ported. Safari frame time INFERRED.
- Accepted writes outside the graph list: `lean/Fw/Parts/Bridge.lean`, `lean/Fw/Parts/FootprintData.lean`,
  `lean/Fw/Parts/FootprintRows.lean`, `footprint.gen.json`, `footprint-diff.gen.json` (hero reads the hero.exit rect).

## Read first
- `research/notes/2026/10-20-hero-pause-rule.md`, `results/hero-pause-rule/summary.json`
