# hero-pause-rule handoff

## State
- Branch `worktree-wf_27d7c8bb-7e0-2`; the commit that adds this file is the final state. CI branch `ci/hero-pause-rule`.
- Flag `hero:scene-pause` (part.json variant `scene-pause`, optimized, T0): the hero track gets `data-fw-hero-scene`
  from `watchActive` (rootMargin `100% 0px`); the CSS sets `will-change: auto` and `animation-play-state: paused` on
  the paused track and its descendants, as the original does for every scene.

## Verified
- Lean `lean/Fw/Parts/HeroScenePause.lean`: `heroScene_eq_original` (rfl), `paused_iff`, `stale_off`,
  `paused_frame_same`, `visSame_original`, `phase_gap`, `establishes_wc_irrelevant`, `layers_le`,
  `hero_paused_drop` (85 → 0 on WebKit Normal). Standard axioms only.
- Golden `packages/contracts/golden/parts/hero-scene-pause.jsonl`, checked by `scene.golden.test.ts`.
- `sh lean/scripts/check.sh` green; site typecheck and tests green.
- MEASURED, webkit-sim 39548856639: layers 58/51 (y 3000), 65/56 (4500), 45/39 (max), against faithful 136-145 /
  124-128 and original 42-47 / 30. Gate 39549161028 passes on both engines. Trajectory 39548822269: WebKit clean;
  Chromium has 43 one-rep units at 390 morph, nav only (INFERRED flake).

## Open
- Look change against the faithful arm (loops resume at the original's phase): user's visual review.
- `deferRendering` (`content-visibility`) of the original's hero scene is not ported.
- Bridge regenerated: hero now reads the hero.exit rect (3 edges, 318 chain pairs).

## Read first
- `research/notes/2026/10-20-hero-pause-rule.md`
- `results/hero-pause-rule/summary.json`
