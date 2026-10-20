---
id: 2026-10-21-scoped-close-start-cause
kind: note
title: "Why hero.exit:scoped starts the close nav background at 226.5 on macOS WebKit: frame cadence, not the part"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, webkit, hero.exit, nav]
---

# Close-start colour of `nav.background-color` under `hero.exit:scoped`

Task `scoped-close-start-cause`. Question: on macOS WebKit morph, the flag-alone candidate (run 39466179818) starts the
close `nav.background-color` at `[226.5, 227.1, 228.5]` 29 ms into the close at 390, while every original pass starts
between 249.3 and 252.3 (also 640, 641). Which mechanism, and which of (a) a part fix, (b) a timing-only rule, (c) a
look change?

## Answer

Decision (b): a timing-only difference. The start colour is the colour of the last frame that still carried
`is-morphing`. How late that last frame lands is frame cadence at the end of the close. It does not depend on the arm,
and `hero.exit:scoped` cannot reach the nav. The same low tail occurs in the original arm and in the A/A candidate.

## Mechanism

1. The close tween is `m = (1 - e/680)^3` (`lean/Fw/Parts/MorphTween.lean`, `closeAt_cube` in
   `lean/Fw/Parts/HeroExitCloseStart.lean`). The nav drops `is-morphing` once `m <= 0.001`
   (`MORPHING_CUT` in `apps/site/src/parts/nav/logic.ts`), which is `e >= 612`, 68 ms before the tween ends
   (`morphing_of_lt`, `not_morphing_of_ge`).
2. `is-morphing` is the class that gives the nav its mixed background (`apps/site/src/parts/nav/nav.module.css:22-26,
   32-47, 56-60, 81-90`): while it is on, the background is `color-mix(in srgb, #ffffff1a, #131922)` driven by
   `--morph`, i.e. alpha `26/255*(1-m) + m` (`bgAlpha`, strictly increasing: `bgAlpha_lt`, `bgAlpha_inj`).
3. When the class is removed, the style change starts a `background-color` transition. The before-change style is the
   style of the previous style-change event, so the start colour is `bgAlpha(m_prev)`, `m_prev` the morph value of the
   last frame that saw `is-morphing` (WebKit `Source/WebCore/style/Styleable.cpp:606-617, 646-676, 683-691, 694-757`;
   `StyleTreeResolver.cpp:926` runs `updateTransitionsAndTimelines()` before `applyAnimations()` at :940, so the
   running tween has not yet moved the style @862f17d). CONFIRMED against the pinned clone; the CI Playwright WebKit
   build (27.2) is a different build, so applying it to CI is INFERRED.
4. If the next frame comes `g` ms after the last morphing frame, `m_prev <= ((68 + g)/680)^3` (`prev_le_bound`,
   `prevBound`). A 29 ms frame leaves `m_prev` near 0.001 (start 251, the original's range). A 114 ms frame allows
   0.019 (start ~226). `startAccepts_tween` proves every start the tween can make is accepted at its own gap
   (`startAccepts`); `startAccepts_above` rejects a start above the bound.
5. `hero.exit:scoped` writes only `--exit-opacity` and `--exit-scatter` on hero elements, on scroll frames
   (`apps/site/src/parts/hero.exit/driver.ts`, `hero.module.css`; `Fw.Parts.HeroExitOpt.frameWrites`). The nav
   background reads only `--morph`. `scoped_writes_miss_nav_bg` and `scoped_writes_miss_nav_elements` prove the
   writes miss both, so the part cannot move the removal or the colour except by changing frame cadence.

## Measurements (stored runs, not fresh)

Fresh flag-alone and A/A runs need a lead dispatch (see handoff `open`). The two stored runs below are the same
shape: 5 reps x 4 widths, mac-webkit morph (`playwright-webkit`), SHA 45a40e7b.

Identity, read from the raw files per arm: run 39466179818 `?fw=hero.exit:scoped` hash 8d213de6fbdd52fd, base arm
ede2c7641aacf2d2, original arm no config, `refused: false`, morph and hero arm hashes equal the arm's expectation. Run
39472217441 A/A `?fw=hero.exit:faithful`: candidate and base arm both ede2c7641aacf2d2, original arm none.

Start colour (red channel, 0-255) of the last `is-morphing` sample before removal, with its `m` and the gap `g` in ms
to the first frame without the class. Cells are reps 0-4.

Flag-alone, run 39466179818:

| width | arm | rep 0 | rep 1 | rep 2 | rep 3 | rep 4 |
|---|---|---|---|---|---|---|
| 390 | orig | 249.0 (g 36) | 250.7 (68) | 252.4 (29) | 251.3 (23) | 249.0 (46) |
| 390 | base | 251.1 (33) | 251.8 (37) | 248.6 (45) | 251.8 (33) | 251.4 (26) |
| 390 | scoped | 226.6 (114) | 247.8 (51) | 248.6 (37) | 206.3 (158) | 250.4 (45) |
| 640 | orig | 246.5 (113) | 250.1 (47) | 252.7 (47) | 249.0 (30) | 251.3 (57) |
| 640 | base | 251.3 (44) | 249.4 (32) | 247.4 (142) | 250.1 (66) | 244.0 (62) |
| 640 | scoped | 239.4 (62) | 249.4 (62) | 244.5 (46) | 227.5 (105) | 252.2 (68) |
| 641 | orig | 247.0 (36) | 224.2 (98) | 251.7 (64) | 248.0 (49) | 249.4 (38) |
| 641 | base | 245.1 (56) | 249.2 (32) | 250.6 (31) | 251.1 (53) | 250.4 (34) |
| 641 | scoped | 250.2 (37) | 251.0 (47) | 248.0 (42) | 251.9 (72) | 242.0 (83) |
| 1280 | orig | 247.0 (49) | 243.4 (57) | 252.6 (37) | 248.6 (55) | 216.5 (120) |
| 1280 | base | 248.8 (100) | 247.0 (42) | 248.3 (85) | 249.4 (54) | 233.5 (86) |
| 1280 | scoped | 248.0 (51) | 247.8 (147) | 249.9 (94) | 249.0 (49) | 244.8 (45) |

A/A, run 39472217441 (candidate `?fw=hero.exit:faithful`, the same code as base):

| width | arm | rep 0 | rep 1 | rep 2 | rep 3 | rep 4 |
|---|---|---|---|---|---|---|
| 390 | orig | 252.7 (45) | 249.9 (53) | 245.8 (80) | 240.1 (87) | 252.2 (50) |
| 390 | base | 250.6 (50) | 250.2 (61) | 252.1 (45) | 250.6 (37) | 244.0 (83) |
| 390 | faithful | 248.6 (39) | 252.4 (41) | 237.0 (69) | 249.6 (39) | 202.7 (203) |
| 641 | orig | 223.2 (146) | 243.4 (58) | 248.0 (41) | 250.4 (23) | 247.4 (115) |
| 641 | base | 247.0 (58) | 246.0 (51) | 250.1 (36) | 225.2 (142) | 245.6 (41) |
| 641 | faithful | 251.8 (60) | 249.0 (29) | 250.7 (44) | 251.7 (29) | 252.5 (35) |
| 640 | orig | 249.9 (21) | 248.8 (25) | 251.1 (19) | 248.4 (27) | 251.0 (19) |
| 640 | base | 251.3 (27) | 247.8 (24) | 251.3 (18) | 251.3 (18) | 251.8 (15) |
| 640 | faithful | 251.1 (22) | 250.7 (22) | 252.1 (22) | 251.4 (18) | 251.8 (13) |
| 1280 | orig | 251.1 (16) | 249.6 (25) | 248.4 (68) | 252.5 (24) | 252.2 (45) |
| 1280 | base | 250.9 (23) | 251.1 (29) | 252.7 (29) | 252.4 (31) | 247.6 (31) |
| 1280 | faithful | 251.8 (32) | 251.3 (26) | 251.1 (27) | 247.8 (28) | 252.6 (23) |

Reading:
- The start colour falls with `g`: 226.6 at g 114, 206.3 at g 158 (scoped), 202.7 at g 203 (A/A candidate), 224.2 at g
  98 and 216.5 at g 120 (original), 225.2 at g 142 (base). Cell for cell the arms share one curve.
- Cells below 245, of 20 per arm (4 widths x 5 reps). Flag-alone run: scoped 7 (226.6, 206.3, 239.4, 244.5, 227.5,
  242.0, 244.8), original 3 (243.4, 224.2, 216.5), base 2 (244.0, 233.5). A/A run: original 3 (240.1, 223.2, 243.4),
  base 2 (244.0, 225.2), faithful candidate 2 (237.0, 202.7). The tail exists in every arm, including the A/A
  candidate, which runs the same code as base.
- The scoped arm has the most low cells in its run (7 of 20 against 3 and 2). At n = 20 per arm that does not separate
  from frame-cadence noise (the A/A run alone spreads 2 to 3), but it does not prove equality either. Whether the
  scoped arm lengthens the last frames of the close is the open question for the fresh run; the Lean proof says the
  part writes nothing the nav reads, so a cost route would be through frame time, not through the nav style.
- `bound.mjs` (local scratch, not committed) checked `m_prev <= ((68+g)/680)^3` on every close of both runs: no
  violation beyond 8 ms of slack. Cells in the table are consistent with `prevBound`.
- Colour is a function of `m` alone while `is-morphing` is on, across arms (`fn.mjs`, local scratch): component
  spreads stay within 2 levels, so the nav does not draw a different mix per arm.

Lean outcome lines (existing re-reduction, `docs/team/tools/trajectory-probe.md`): 39466179818 mac-webkit morph
`fail -> fail` (bg `new` at 390, 640, 641; 1280 cleared); 39472217441 mac-webkit morph `no verdict: coverage`.

## Decision

(b). No part change, no look change. The cause lies in the judge's reading of one frame-phase value:
the close start is a draw from `bgAlpha(m_prev)`, `m_prev` in `(0.001, prevBound(g)]`, and the envelope built from
five original passes cannot cover a draw whose `g` the original passes did not hit.

Proposed rule for `trajectory-envelope-scope` (stated, judge unchanged here): at `close@0` (the first sample after
`is-morphing` is removed), the background reading is accepted when it lies in `(bgAlpha(morphingCut),
bgAlpha(prevBound g)]`, with `g` the observed gap between the last morphing sample and the first sample without the
class, instead of inside the original passes' hull. In Lean: `Fw.Parts.HeroExitCloseStart.startAccepts`, with
`startAccepts_tween` (soundness: every start the tween makes is accepted), `startAccepts_above` (a reading above the
bound is rejected). The rule is a function of the sample's own timing, so it stays a per-unit decision. It can only
pass readings a faithful implementation produces; it does not widen the envelope for later samples of the transition.

## Limits

- Stored runs, not fresh: 39466179818 and 39472217441 predate this task. The fresh flag-alone and A/A runs were not
  dispatched by the lead (see handoff `open`).
- WebKit source reading is on the pinned clone @862f17d; CI runs a Playwright WebKit build (27.2). INFERRED to match.
- A 5-rep sample cannot bound the rate of long gaps per arm.
- The `bgAlpha` formula is the alpha channel only; the colour channels use the mix of `#ffffff1a` and `#131922`
  (post-removal values are oklab-shaped in the raw data and converted by `colourFromV1`).
