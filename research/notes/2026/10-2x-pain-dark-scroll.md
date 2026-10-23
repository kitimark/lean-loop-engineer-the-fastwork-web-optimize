# pain:dark-scroll (GPU route rank 4): the Pain dark flip as a scroll-driven opacity layer

Task `pain-dark-scroll`. Branch `worktree-wf_5c56f74c-ecb-1`, CI branch `ci/pain-dark-scroll`. Context: ledger n=21 (solid
layer for the `is-pain-dark` flip), `10-2x-toolbar-throttle.md` (throttle-lift rule).

## Verdict

- PROVED (Lean `Fw.Parts.PainDarkScroll`): for every width, header document top and scroll offset, under Reveal and Cont
  the variant shows the original's pixel (`pixel_eq`); the layer's opacity is exactly 0 before the flip offset and
  exactly 1 from it on (`opacity_eq`, `layer_flip`); the written range start is the encoded one at any scroll offset and
  reveal state (`measure_eq`); above 860 px both arms are dark (`wide_eq`).
- CONFIRMED (CI): breakpoint gate, both engines, all breakpoints, final design: run `39828600078` pass (the pain and
  people.card rows pass in every cell; the `UNREACHABLE` cells are the standing excused ones). The gate compares the pre-flip state only (anchors.json excludes is-pain-dark and the people flip; cells are read at scroll 0); the post-flip look is the trajectory pain-dark cell below (E, run `39852164349`).
- MEASURED, Chromium (counts, 430x932 dpr 3, swipe-v1, 3 runs, identical across runs): in the toggle frame the
  invalidated paint area falls by one viewport (400,760 px) and the raster tasks fall 26 to 20; over the whole swipe the
  invalidated area falls 4.0 % and tiles 6.6 %; the price is +3 layers in every frame (solid, no tiles) and +14 style
  recalcs.
- MEASURED, WebKit Simulator: the two pseudo-element layers exist with reason `animation` and no backing; the painted
  area of a whole scroll pass is 28 % and 34 % lower than the base. The price is +12.0 MB backing at the two scroll
  states that show the Pain stage (the stage's text block is promoted above the animated layer).
- Not a clean win. WebKit pays 12 MB of backing and Chromium +3 layers for the paint saving. The toggle-step
  cell in WebKit is not separable from noise (the paint spike moves between steps). Hold for the user's Safari lane
  (`gpu-safari-lane`) before a preset.
- Look: E-s for the pixel, Q for the flip frame (below). Trajectory pain-dark cell: E on both engines (follow-ups below).

## Design and the three designs that failed on CI

The flag is `pain:dark-scroll` (part `pain`, variant `dark-scroll`, `visClass: "E-s"`). At most 860 px, in an engine with
the root scroll timeline and `animation-range-start` (`CSS.supports`, the same text in CSS `@supports`), two empty
`#131922` pseudo-elements lie over the white hold and over the stage's own background, behind the content, and their
opacity runs on `scroll(root block)`. `people.card` then neither reads the header nor writes `is-pain-dark`. Other
engines keep the class flip.

| design | what | CI | why it failed |
|---|---|---|---|
| 1 | an empty child `div` in the section | gate run `39817106098` cancelled | the gate selects the sticky as `[data-fw="pain"] > div:first-child` (`anchors.json`); a first child shifts it |
| 2 | one `::before`, sticky and hold made transparent | gate `39818716087` fail, pain cells at every width | the gate compares the computed `background-color` of sticky and hold (white against transparent) |
| 3 | two `::before` over the unchanged white surfaces, range 1 px long | gate `39822433333` pass, webkit-sim `39822439200` | WebKit accelerates only the active phase: with a 1 px range the layers were never in the layer census, so the flip there is a main-thread style change |
| 4 (shipped) | as 3, range starts 256 px before the flip and is 32768 px long, the flip is a keyframe at 1/128 with `steps(1, jump-start)` | gate `39828600078` pass, webkit-sim `39828605244`, counts `39828614430` | none; costs below |

Lesson: a steps animation that is idle before its flip is not accelerated before it. The flip must lie inside
the active phase, so the range starts earlier and the step is a keyframe, not the range start.

## Lean

`lean/Fw/Parts/PainDarkScroll.lean`, 240 golden rows (`packages/contracts/golden/parts/pain-dark-scroll.jsonl`, `#guard`).
Pixels are exact `Rat` triples; opacity is 0 or 1, so source-over is exact (`over_zero`, `over_one`).

| theorem | statement |
|---|---|
| `opacity_eq` | for range start `s`, length `len > 0`, keyframe offset `0 < x < 1`: opacity = if `s + x len <= y` then 1 else 0, from the CSS Easing `steps(1, jump-start)` algorithm (`stepsStart1`, `TimingFunction.cpp:100-139@862f17d`) |
| `layer_flip`, `flip_of_range` | with `rangeStart h = h - 1/2 - 256`, `rangeLen = 32768`, `offsetX = 256/32768`: opacity flips at `flipAt h = h - 1/2` |
| `measure_eq` | the range start the layout effect writes from one measurement (viewport top, scroll offset, card translation) equals `rangeStart h` at any scroll offset and reveal state |
| `pixel_eq` | `Reveal tr` and `Cont lastY y` give `varPixel w h y = origPixel w h tr lastY` for all `w`, `h`, `y` |
| `wide_eq` | above 860 px both arms are dark in every state |
| `reveal_needed`, `cont_needed` | each premise is needed: a counterexample (card 48 px low; original one frame behind) |
| `drift_window` | with `0 <= tr <= 48` and Cont, the arms differ only in the band and only for `flipAt h <= y < flipAt h + 48` |
| `no_lift` (`dark_accelerated`) | the only effect animates opacity, in WebKit's `always` list, so `AnimationTimelinesController.cpp:267-279@862f17d` (`hasProgressBasedScrollDrivenAnimation`) does not hold and the throttle is not lifted |
| `toggle_free`, `toggle_cost` | the toggle adds no main-thread style or paint in the variant (INFERRED: UI-process flip); the original pays both |
| `ride_exceeds` | WebKit restyles the animation target in every updating scroll frame (`scroll_comp_ride`): a trade once frames exceed the original's restyled elements |
| `solid_layers_le`, `layer_backing_zero`, `promoted_cost` | 2 solid layers plus 1 host layer at most 3; they hold no backing; the promoted block costs its whole area (2,999 kpx) |

TS stand-ins (listed): the test-only twin of `layerOpacity` in `darkScroll.test.ts` (checked against the 216 pixel
rows); `rangeStart` and `translateY` in `darkScroll.ts` (the first against the 24 flip rows). The DOM glue
(`installRangeStart`: ResizeObserver, media change, load) holds no decision logic.

## Premises

| premise | status |
|---|---|
| Cont: the original's class is current at the offset | INFERRED. It is written in a rAF after the scroll callback (`driver.ts`), so it can be one frame behind a UI-process flip. Reported as Q, not gated |
| Reveal: the card's reveal translation has finished at the flip | MEASURED for the offset, INFERRED for the timing. The Chromium swipe flips first in frame 106 (scroll 970 at height 932; header document top 965, so flip 964.5). Reveal starts at 0.72 of the 100vh exit range (`REVEAL_AT`) and runs 0.9 s; the residual is under 0.5 px after 0.554 s (cubic-bezier(.16,1,.3,1), computed here). The flip is `0.28 vh + 32.5` px of scroll after the reveal (293 px at 932): a swipe averaging over about 530 px/s between the two beats the transition. Then the original is the later arm by at most 48 px of scroll (`drift_window`), under about 1.5 frames at 2000 px/s |

## Measured

All counts are deterministic across the three runs unless stated. Base: counts `39818749535`, webkit-sim `39818734599`;
final design: counts `39828614430`, webkit-sim `39828605244`. Viewport 430x932 dpr 3 (Chromium), 430x775 dpr 3 (WebKit).

Chromium counts (swipe-v1, 503 frames):

| metric | base | variant | cell |
|---|---|---|---|
| toggle frame (scroll 970) invalidation area, px | 3,413,963 | 3,013,203 | MEASURED |
| toggle frame raster tasks | 26 | 20 | MEASURED |
| toggle frame invalidated layers | 8 | 7 | MEASURED |
| toggle frame style recalcs | 4 | 5 | MEASURED |
| whole swipe invalidation area, px | 94,503,701 | 90,741,721 (-4.0 %) | MEASURED |
| whole swipe tiles | 50,268 | 46,972 (-6.6 %) | MEASURED |
| whole swipe style recalcs | 1,832 | 1,846 (+14, frames 106 to 119) | MEASURED |
| whole swipe layout count | 318 | 318 | MEASURED |
| layers per frame | 19 at rest | 22 (+3) | MEASURED |
| drawing area, px (not backing) | 4,289,868 | 5,892,908 | MEASURED |

The second drop of 400,760 px at scroll 1220 is the stage's own background (the base repaints it when the sticky enters
the viewport). Duration is not recorded by the counts lane: no duration claim.

WebKit Simulator (iOS 27, 2 passes each, `scroll.records` Paint quads, `census`):

| metric | base | variant | cell |
|---|---|---|---|
| painted area of one scroll pass, css px squared | 69.1 M, 73.7 M | 49.6 M, 49.0 M | MEASURED (base spread 6.7 %) |
| backing at scroll 1500 and 3000 | 102.9 / 101.3 MB (pass 1) | 114.9 / 113.3 MB (+12.0) | MEASURED, both passes |
| backing at scroll 0, 4500, max | - | no change (state 0 is quarantined, spread up to 10 MB) | MEASURED |
| pseudo-element layers | none | 2, reason `animation`, backing 0 | MEASURED |
| promoted content layer | none | the text block, 11,997,000 bytes, reason `overlap` | MEASURED, cause INFERRED |
| paint of the flip step | no separable difference | the spike moves between steps | MEASURED, no claim |
| style records per pass | 674, 655 | 676, 680 | MEASURED, overlaps the spread (19) |

Gate: run `39828600078`, both engines (Chrome Headless Shell 156 and Playwright WebKit on Linux, not Mobile Safari).

## Accepted limits and open items

- Running the flip in the UI process is INFERRED (UIProcess sources are not in the clone). The census shows the layers
  with reason `animation` in WebKit, which is the precondition, not the proof.
- Flip-frame timing may differ by one frame (Q); reported, not gated.
- Safari-on-Mac numbers: `gpu-safari-lane`.
- Chromium shows +3 layers where the Lean count is 2 solid plus 1 host (the host is INFERRED).
- Open: a toggle-frame duration lane.

## Follow-ups (task pain-dark-followups)

### 1. Post-flip look, both engines

Trajectory probe run `39852164349` (push of `ci/pain-dark-followups`, `fw=pain:dark-scroll`, verdict run, inputs read from the
artifact `trajectory-inputs`). The pain-dark cell scrolls the page in 4 px steps down and back up and reads the pseudo-element's
computed opacity (the class where the layer is absent), after two frames per step.

| engine | width | layer engaged | cell grade (down, up) | flip step |
|---|---|---|---|---|
| Chromium 156 | 390, 640 | yes | E, E | 873 to 877 in both arms |
| Linux WebKit 27.2 (Playwright) | 390, 640 | yes | E, E | 873 to 877 in both arms |

MEASURED. No row between 0 and 1 (steps), none one step early or late, so there is no Q at this resolution; one-frame lag
inside a 4 px step stays reported, not gated. Linux WebKit is not Safari (Safari-on-Mac: `gpu-safari-lane`). The scan code is
`painScan` in `cells-gpu-run.mjs` (reads `getComputedStyle(section, '::before')`), the workflow step passes the push search and walks
Linux WebKit legs 390 and 640 (`--only pain`).

### 2. toggle_free and ride_exceeds

`toggle_free` is the model assumption ToggleUi (the flip runs in the UI process,
INFERRED) and `ride_exceeds` the assumption RideEveryFrame (`Engine.WebKit.scroll_comp_ride`, proved for the WebKit model).
Chromium's toggle frame refutes `toggle_free` for style: Lean `chromium_style_gt` (4 to 5 recalcs, runs `39818749535` and
`39828614430`), `chromium_paint_lt` and `chromium_paint_drop` (3,413,963 minus 3,013,203 is 430 x 932, one viewport). Both labels are in
`part.json` provenance and the ledger row.

### 3. A backing-free arrangement

Source (WebKit `862f17d`, `Source/WebCore/rendering/RenderLayerCompositor.cpp`): a layer that is not composited by itself composites with
reason `Overlap` iff overlap testing is on, the overlap map is not empty and its extent meets a layer composited earlier in paint order
(lines 1331-1336, `layerOverlaps` 2798-2804); `requiresCompositingForAnimation` makes an opacity animation composite its layer
(3842-3850); backing sharing applies only to scroller providers (416-490). So content painted above an animated layer that it meets is
promoted, with its own backing. Census of the HOLD run (`39828605244`): the base sticky is one backed layer (14.3 MB, reason
`positionSticky`); HOLD makes the sticky a solid layer (0 MB) and the notes canvas (14.3 MB) and `.inner` (12.0 MB) overlap-promote above the
animated `.sticky::before`. `.inner` is 430 x 775 because the flex row stretches it to the stage.

Lean layer budget (`PainDarkScroll.lean`, before any CSS):

| theorem | statement |
|---|---|
| `animated_meets_costs`, `hold_backing` | an animated span that meets a content layer gives it its own backing; the stage content then costs `promotedKpx` (2,999 kpx, 12.0 MB) more than the base |
| `cover_meets`, `below_promotes` | a layer that paints the stage's pixels under the content covers the stage, so it meets every content layer in it, and the content is promoted |
| `above_hides` | the other order (layer above content) shows the layer's colour over a coloured note while opaque: a look change |
| `static_eq_base` | with no animated layer the backing equals the base |
| `static_pixel_eq`, `hidden_needed` | a static dark pseudo-element pair has the original's pixel if the white state is never in view (`static_pixel_eq`); without it some seen state differs (`hidden_needed`) (Hidden: Pain top at least one viewport and 47.5 px below the flip offset) |
| `hidden_fails_390`, `hidden_fails_640` | Hidden fails on the measured geometry |

Arrangement tried: `pain:dark-static` (kept as a look-change proposal): the same two pseudo-elements, `#131922` from the start, nothing animated,
`people.card` never writes `is-pain-dark`. Lean golden rows `owns` (`ownsFlip`) for the hand-over.

| metric (same ref `9597ea656`, WebKit sim runs `39856782689` base, `39856789295` HOLD, `39852256714` static) | base | HOLD | static |
|---|---|---|---|
| backing at scroll 1500 / 3000, pass 1 (MB) | 87.0 / 101.3 | 99.0 / 113.3 | 87.0 / 101.3 |
| promoted content layers | none | canvas 14.3 MB, inner 12.0 MB (overlap) | none |
| animated layers | none | 2 (`animation`, 0 MB) | none |
| paint in the pinned band, document y 1500 to 3000, pass 1 / 2 (M px squared) | 26.9 / 24.8 | 10.1 / 9.9 | 26.5 / 25.2 |
| full-stage (430 x 775) repaints in the band, pass 1 / 2 | 54 / 49 | 5 / 5 | 53 / 50 |
| paint of one whole pass, pass 1 / 2 (M px squared) | 81.5 / 85.2 | 51.0 / 68.8 | 72.4 / 70.1 |

MEASURED. The whole-pass totals spread 20 percent between the two passes of one arm (outside the band), so the band columns decide. Chromium
counts (`swipe-v1` x 3, run `39852245766`, base `39818749535`, HOLD `39828614430`): static keeps the toggle-frame saving (invalidated area
3,413,963 to 3,013,203 px, raster tasks 26 to 20, style recalcs 4 to 3, layers +0), but not the whole-swipe saving (area -0.4 percent, tiles
unchanged; HOLD -4.0 and -6.6 percent). Breakpoint gate on `pain:dark-static`, both engines: run `39852250962` pass.

Result: no-win. The only arrangement that removes the backing (no animated layer under the content) also removes the
WebKit paint saving, and it changes the look because the white state is in view at 390 and 640 (Pain top 370 and 843 px below the flip offset
873, 891.5 needed (Lean hidden_fails_390, hidden_fails_640); probe run `39852164349`, the premise measured in the base arm). The other order (layer above the content) hides the
coloured notes until the flip. The saving and the backing appear together in all three arms; the base repaints the full stage every 50 px
step in the pinned band and HOLD does not, and why is not identified (INFERRED: the split-off content layers are not dirtied by what dirties the
sticky backing). Flag stays HOLD; `pain:dark-static` is a look-change proposal for the user's visual review, not a v2-proved candidate.
