# Which element WebKit restyles every frame with nothing changing (WKTR, pref OFF)

Question (task geom-recalc-bisect, graph r564): geom-recalc-source found 93-100 style recalcs per 100 frames that update 0 elements, before the first rAF callback, with every Web Animation paused or cancelled (`engine-internal`). Which element carries them, and which style feature? Investigation only: no site edit, no phone run. WKTR is the iOS 26.5 simulator build on GitHub Actions, not iOS Safari, and its frame clock is slow; hiding changes layout, so the arms find the carrier, not a fix.

## Answer
- The carrier is the SMIL timeline of the two secure-network glint dashes (MEASURED, 3 jobs, run 40812007953): pausing only the 2 `[data-fw-dash]` svgs (4 `<animate>` elements, x1 and x2 of each dash gradient) takes idle from 90-100 to 0 recalcs per 100 frames (0/121, 0/120, 0/121); pausing the other 34 svgs leaves 96-100 (44/44, 79/79, 114/118). Lean `pauser` (Fw.Device.RecalcBisect, decided before the data) says `named pause/dash` in 3 of 3 jobs; `overall2` says `named pause/dash`.
- Pausing all SMIL timelines (`kill/smil`) drops the rate to 11 per 100 in 3 of 3 jobs (14/120 each; run 40812007953) and to 0 in run 40808745010 (3 of 3); no other of 15 features removed (content-visibility, container queries, sticky, fixed, will-change, scroll snap, contain, CSS animation, transition, filter, svg, img, overflow, overflow-anchor) dropped it (kept 93-100). Lean `carrier`: `named kill/smil` in 3 of 3 jobs in both runs.
- Why the dash and not "the platform": the dashes live in the platform part, which has 10 of the 36 svgs. The unit of decision is the svg group, so the part-level hide arms are weaker evidence (below).
- Style feature: the SVG animated attribute `x1`/`x2` on a `<linearGradient>` (`gradientUnits=userSpaceOnUse`, in `<defs>`, referenced by `stroke`), written by the SMIL timer at about 60 Hz. The gradient has no layout box, so a restyle finds 0 elements to update (matches geom-recalc-source: `lastStyleUpdateSize` 0).

## WebKit path (CONFIRMED read, the last link INFERRED), WebKit-7625.1.29.10.29 @862f17d
1. `SMILTimeContainer.cpp:42,86-92` the container timer delay is 1/60 s (1/30 s in low power or thermal mitigation); `:196-216` `startTimer`/`timerFired`, `:261-316` `updateAnimations` runs every active animation and re-arms with `animationFrameDelay()`. The timer is not tied to rendering, so `display:none` on the body does not stop it by itself.
2. `SVGAnimateElementBase.cpp:174-182` `applyResultsToTarget` calls the animator's `apply`; `properties/SVGAnimatedPropertyAnimator.h:77-82` `apply` calls `applyAnimatedPropertyChange` (`SVGAttributeAnimator.cpp:105-125`), which calls `svgAttributeChanged(x1)` on the gradient.
3. `SVGLinearGradientElement.cpp:94-104` `svgAttributeChanged` for a known attribute calls `invalidateGradientResource()`.
4. `rendering/svg/legacy/LegacyRenderSVGResourceContainer.cpp:112-146,148-170` `markAllClientsForInvalidation` then `markAllClientLayersForInvalidation` calls `enclosingElement->invalidateStyleAndLayerComposition()` and repaints. INFERRED: this is the style invalidation that Document.cpp:2914-2936 counts (a recalc that changes no element). Not shown: the body of `invalidateGradientResource` (SVGGradientElement.h is not in the pinned sparse clone) and which SVG engine WKTR runs (legacy vs layer-based; the legacy path is read here).
5. The `<set>` pieces of the existing `platform.glint:hold-freeze` stop timers: `SVGSMILElement.cpp:1074-1088` `calculateNextProgressTime` returns unresolved for a frozen, non-repeating piece (cited in 10-2x-glint-hold-freeze.md).
Not a style feature the page writes: `setPresentationalHintStyleIsDirty` is reached only for class animators (`SVGAnimatedPropertyAnimatorImpl.h:355-375`, `SVGAttributeAnimator.cpp:44-48`), not for x1/x2.

## Runs (CI branch ci/geom-recalc-bisect, WKTR accel lane, mode `bisect-thr-off`, main code, pref OFF, 3 jobs each)
| run | push | arms | Lean level | result |
| --- | --- | --- | --- | --- |
| 40805577147 | 5f37a54e | stage 1: floor (all hidden), full, hide one part (body children, `[data-fw]` parts, then inside) | `overall` | named div#root > page-root; no single child dropped the rate (children kept 66-117, hide page-root 18-20, hide root 0) |
| 40808745010 | 5cc39310 | stage 2: 15 features removed one at a time (`kill`), show-only one child (`only`) | `carrier`, `holder` | carrier `named kill/smil` 3 of 3; holder `several` 2, `incomplete` 1 |
| 40812007953 | da281b56 | stage 3: pause SMIL of svg group `dash` and `other` (`pause`), `kill/smil` kept as control | `pauser` | `named pause/dash` 3 of 3 |

Stages 2 and 3 were added after the data of the stage before; the stage 1 decision was written before any data. Results `results/geom-recalc-bisect/r1..r3` (`j<n>-accel-bisect-thr-off-1.json`, `tally.txt`, `verdict.txt`). Decision `lean/Fw/Device/RecalcBisect.lean` (thresholds `minFrames 40`, `minSpread 50`, band = spread/4 of the job's own `hi` and `lo`), golden `packages/contracts/golden/device/recalc-bisect.jsonl` (71 lines), TS stand-in `packages/measure-wktr/src/recalc-bisect.mjs` that replays it (`reportToJob` and `bisectTally` are glue, not replayed).

## Table: recalcs per 100 frames (run 40812007953; floor = all hidden; frames in the arm in brackets)
| job | full (hi) | floor (lo) | pause dash | pause other | pause all svgs | Lean pauser |
| --- | --- | --- | --- | --- | --- | --- |
| j1 | 90 | 0 | 0 (121) | 100 (44) | 11 (120) | named pause/dash |
| j2 | 100 | 0 | 0 (120) | 100 (79) | 11 (120) | named pause/dash |
| j3 | 95 | 0 | 0 (121) | 96 (118) | 11 (120) | named pause/dash |

## Limits
- Part hide arms are weak here: hiding `platform` left 76 per 100 in r1 j1, and show-only of hero, people or commission read 50-63 with the platform hidden (run 40808745010). INFERRED: the glint mounts its `<animate>` pair from an observer report and a 1 s timer, so after `display:none` the pair is still ticking for part of the window. `smilNow` reads 4 in every pause arm and 0 in the `kill` arm start (the pair was not mounted yet there); the rate in that arm is read over the window, so the 11 per 100 is the part of the window with the pair mounted and unpaused. The `pause/dash` result does not depend on this: both groups were read with the pair mounted.
- The glint is legitimately visible and playing at the bottom of the page, so this carrier is real work, not waste. The probe scrolls to the page bottom (`toBottom`, mid-page.mjs) before its arms, where the platform section is in view; per `faithful_no_ticks_away` (platform.glint part.json) the faithful page unmounts the pair when the ratio is below 0.35, so away from it there are no ticks.
- The 4 `<animate>` elements are the only SMIL in the dash group; the count of other SMIL elements in the other 34 svgs is 0 (`smilNow` 4 = all SMIL in the document).
- WKTR is not iOS Safari; no phone run; the engine path above is read from source and not stepped in a debugger.

## One next step (same-look fix task, not done here)
Task `glint-hold-wktr`: measure the existing flag `platform.glint:hold-freeze` in this lane (probe arms `bs-pause` dash and the floor, flag off against on, 3 jobs, pref OFF).
- What changes: each dash's two repeating 5 s `<animate>` become a ring of five pieces per attribute with `fill=freeze`; in 3 of 5 key-time segments only `<set>` pieces are active, so the SMIL container has no non-`<set>` animation to progress.
- Why the look is identical: the hold sample equals the original at every elapsed time (class E, gate pass both engines, 10-2x-glint-hold-freeze.md).
- Lean statement: `Fw.Parts.PlatformGlintHold.hold_eq_faithful` (same look), `ticking_hold` and `ticking_le` (0 ticking animations in the hold segments, never more than the original). Expected, INFERRED: recalcs per 100 frames about 40 or less while the glint plays (ramp segments are 2 of 5), 0 when paused off-screen; the task must add a Lean statement that maps ticking animations to recalcs and decides before the data.
- Follow-up if the ramp segments stay costly: no compositor path exists for a gradient `x1`/`x2`, so only fewer or slower ticks can help; a new variant would need its own look proof.
