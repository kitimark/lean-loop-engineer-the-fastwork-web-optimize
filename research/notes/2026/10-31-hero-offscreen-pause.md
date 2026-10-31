# hero-offscreen-pause: pause the accent idle loops and the cue float while off screen

Task `hero-offscreen-pause` (plan r607), follow-up of `10-31-sim-floor-attrib.md`: on the CI iOS Simulator every arm reads 2 style recalcs per
frame at the end of the page while document animations run. Two of the running ones sit in the hero: the accent idle loops
(`accent-module_idle0..2`, `0.6s step-end infinite` on the three svg boxes) and the cue float (`cue-module_scrollFloat`, `2.2s
ease-in-out infinite` on `span.float`, `apps/site/src/parts/hero.cue/cue.module.css`). The platform sweeps already have
`platform.sweep:offscreen-pause`. This task adds the same pause for the two hero loops. No Simulator or device claim here (`sim-end-cut` measures).

## Mechanism (CONFIRMED in code, not measured)

- `watchLoopPause` (`apps/site/src/parts/hero.accent/pause.ts`, shared with hero.cue) observes one element per part with the engine.scene
  observer (`watchHidden`, kind `rect`, threshold 0). A hidden report pauses the element's running infinite-iteration animations and saves each
  `startTime`; the first visible report resumes them with `play()` then `startTime = saved`, so the animation sits on the document timeline phase
  it would have had. The pure model is the sweep's (`platform.sweep/pause.ts`: `init`, `seek`, `tick`, `step`, `ticks`, `orig`, `reportAction`), reused, not copied.
- Loops are read when the element is reported, not at mount (the cue's float starts after the splash). Only `iterations === Infinity` counts, so
  the finite draw animations are left alone. A paused animation the page cancelled meanwhile (`playState` no longer `paused`, the accent's class
  change to a draw state) is not resumed.
- Variants are exclusive per part (`resolve.ts`), so `hero.accent:offscreen-pause` runs the faithful CSS boil and the unchanged timer chain
  (`driver.ts`); `steps` has no CSS loop (its finite zero-duration steps are re-begun by `boil.ts`) and `draw-one` only sets a data attribute.
  The pause reads no chain state, so a combined variant is possible; not built (follow-up).

## Lean

- `lean/Fw/Parts/OffscreenPause.lean`: `look_same` (any function `g` of the local time shows the original's value on every visible frame, from
  `PlatformSweepPause.visible_same`), `look_same_unreported`, `look_same_all` (animations that start together).
- `lean/Fw/Parts/HeroAccentPause.lean`: `shown j t = HeroAccentOpt.origVal j (600 * frac (t / 600))`; `accent_visible_same`,
  `accent_visible_same_all` (the three boxes), `accent_reported_no_tick`, `accent_offscreen_ticks_le_one`.
- `lean/Fw/Parts/HeroCuePause.lean`: `cueY e t` for every easing `e`; `cue_visible_same`, `cue_reported_no_tick`, `cue_offscreen_ticks_le_one`.
  The easing is a parameter, so no fact about the engine's cubic-bezier is assumed.
- Goldens `packages/contracts/golden/parts/hero-accent-pause.jsonl`, `hero-cue-pause.jsonl` (generator `lean/Fw/Parts/HeroPauseGolden.lean`,
  check.sh jobs, trigger rows); replayed by `pause.test.ts` in both parts.

Named premises (not proved about the engine): `Lag` (the observer reports an element after the frame it leaves, so that frame still ticks),
`Ok` (an element reported offscreen is offscreen), and that setting `startTime` on a paused CSS animation after `play()` keeps the CSS play state
(INFERRED, both engines, as in `platform:faded-pause`). Not covered: a loop created while the element is offscreen is not tracked.

## Class and limits

Same look (class E), no `visClass`. No preset change. Footprint: the extractor reads `pause()`/`play()`/`startTime` as a write of the element's style
(`part-footprint.mjs`, `ANIM_CALLS`), so `hero.accent` and `hero.cue` gained a write; the footprint rows, diff and `Bridge.lean` tables were
regenerated (hero.cue is no longer independent of itself: 4 not 5 such rows; 266 chain pairs, was 285). The breakpoint gate for
`v2-proved` plus the two flags plus `platform.sweep:offscreen-pause` is a dispatch item for the lead.

## Which end-of-page animations remain

After these three variants, the document animations still running at the end of the page are the other platform loops (glint dashes, marquee,
entries, covered by their own flags or none) and anything else the faithful page keeps running; `sim-end-cut` measures the stack. Whether pausing
lowers the 2 recalcs per frame on the Simulator is not known here (INFERRED only from `10-31-sim-floor-attrib.md` section 3).
