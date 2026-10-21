# hero-pause-rule handoff

## State
- Branch `worktree-wf_27d7c8bb-7e0-2` (CI `ci/hero-pause-rule`), round 3, main 8b209077 merged; this commit is final.
- Flag `hero:scene-pause` (part.json variant `scene-pause`: optimized, T0, visClass E): the hero track gets
  `data-fw-hero-scene` from `watchActive` (rootMargin `100% 0px`); the paused track sets `will-change: auto` and
  `animation-play-state: paused`, as the original does for every scene. Same look as the original
  (`visSame_original`); it differs from the faithful arm, which lacks the pause rule.
- Preset decisions line: `hero:scene-pause` registered, member false, verdict `pending: trajectory`, why `no-link`.

## Verified
- Lean `lean/Fw/Parts/HeroScenePause.lean`: `heroScene_eq_original`, `paused_frame_same`, `visSame_original`,
  `hero_paused_drop` (85 to 0, WebKit Normal), `hero_wc_paint_same`, `stage_fits`, `kMax_pos`, `kCopy_ge`,
  `hero_paused_hidden` (paused hero boxes off-screen at all 124 probes within `kMax`). Standard axioms only.
- `sh lean/scripts/check.sh` exit 0 (92 s). Node 24.22.0: site typecheck passes; site vitest 5583 pass, 4 skipped,
  0 fail after the merge; port tests, ci-paths (54) and runner land-inputs (55) pass.
- MEASURED: census 39548856639 (will-change reason 91 to 6), gate 39549161028 pass on both engines.
- Trajectory, Chromium 390 morph: flag runs 39548822269 RED, 39553952680 RED, 39556935431 CLEAN (42 open@1 both);
  no-flag control 39557718020 CLEAN. Flag arm never samples open@1 (0/15 reps), default rewrite 9/25, original 0/20:
  a flag effect on first-frame timing (matches the original), so the flag stays out of v2-proved on this evidence.

## Open
- Probe follow-up: open@1 coverage against the original's first frame; timing mechanism not determined.
- kCopy INFERRED (`hero_paused_hidden_copy`); census y 5267 n = 1; `deferRendering` not ported; Safari frame time
  INFERRED, no device run.
- Accepted writes outside the graph list: `lean/Fw/Parts/Bridge.lean`, `lean/Fw/Parts/FootprintData.lean`,
  `lean/Fw/Parts/FootprintRows.lean`, `footprint.gen.json`, `footprint-diff.gen.json` (hero reads the hero.exit rect).

## Read first
- `research/notes/2026/10-20-hero-pause-rule.md` (Limits, CI), `results/hero-pause-rule/summary.json`
