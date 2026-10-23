# people.o:preview-translate (desktop hover, above 860 px)

Task people-o-preview-translate. Flag: the fixed 320 x 440 seller preview follows its face by the `translate` property instead of
a `top` write in every scroll frame. Proof: `lean/Fw/Parts/PeopleOPreview.lean`. Code: `apps/site/src/parts/people.o/preview.ts`,
`index.tsx` (`place`). Golden: `packages/contracts/golden/parts/people-o-preview.jsonl`.

## Mechanism

- CONFIRMED: the card is `position: fixed` (`o.module.css` `.preview`), and the original writes `left`, `top` and `width` in every call of
  `place` (JS 6190-6213), which the scroll engine makes in every scroll frame (JS 6251).
- CONFIRMED (source): a position change is movement-only layout only for `position: absolute`
  (`StyleDifference.cpp:557-565`@862f17d, `changeRequiresOutOfFlowMovementLayoutOnly`), so a `top` change of a fixed box is a Layout
  change in WebKit. The engine tables give the same on Chromium: `top` of an own-layer box is `layoutMove` (style, layout, props, commit),
  `translate` of an own-layer box is `ppFull` (style, props, commit; `Fw.Engine.Chromium`).
- INFERRED: the card has its own layer, so `translate` leaves layout. WebKit: a fixed box with a stacking context is composited when the page
  scrolls (`RenderLayerCompositor.cpp:4097-4150`@862f17d, `requiresCompositingForPosition`). The WebKit table files `transform` on a
  non-composited layer under Layout, so the win needs this premise.

## Are WebKit scroll offsets integral? (the look question)

CONFIRMED (source), @862f17d: `using ScrollPosition = IntPoint; using ScrollOffset = IntPoint;` (`Source/WebCore/platform/ScrollTypes.h:47-49`);
`ScrollView::contentsScrollPosition()` returns `IntPoint` (`platform/ScrollView.cpp:210-217`); `LocalDOMWindow::scrollY()` returns `int`
(`page/LocalDOMWindow.cpp:1466`). So the main-frame scroll delta between two frames is a whole number of CSS px, and the translate is a
whole number of device pixels at integer device ratios. The look is then the faithful look (E-s). Chromium may hold fractional scroll
offsets (fractional zoom); there the variant does not rely on it: `keep` requires the device-pixel delta to be an integer and writes
`left`/`top` otherwise, so the shown position is the faithful one in every case (Lean `step_faithful`). The look class stays E-s.

## Lean (check.sh green)

| statement | theorem |
|---|---|
| no flip, whole scroll positions, integer device ratio: `snapDev(cardTop(rect y)) = snapDev(cardTop(rect y0)) - (y - y0) d`, same phase | `snap_noFlip`, `phase_add`, `snapDev_add` |
| a fractional shift breaks the pixel (100.3 moved by -1/2 at d = 1) | `frac_counter` |
| flip, viewport and clamp: the shown top and left equal the faithful ones from any held state | `step_faithful` |
| kept frame: no write; translate `y0 - y` (clamped regime: 0), whole device pixels | `keep_no_write`, `keep_translate`, `keep_clamped`, `keep_whole`, `keep_pixel` |
| layout passes: faithful 1 per scroll frame; variant 0 on a kept frame, 1 on a flip frame; both engines, own layer | `faithful_layout`, `translate_layout_kept`, `translate_layout_flip`, `translate_work_lt` |
| layer budget 0 by definition (`residentOf` is the same for both variants; INFERRED: the variant adds no `will-change` and no 3D transform) | `layer_budget_zero` records it |

## Measured

- Breakpoint gate, both engines, flag `people.o:preview-translate`: run 39850908365 at dce0985, success. Config 08b2ef03265b7880, chromium and playwright-webkit, row `people.o`: all cells pass except the two WebKit cells that cannot be built (UNREACHABLE: primary-pair, whole-width), no FAIL. MEASURED. The gate cells do not hover, so
  the card is closed in them: this shows the closed page is unchanged, not the open card (the open card is the Lean theorem above).
- Earlier (before task chromium-desktop-crash): the counts were blocked. Every desktop-width run, base and flag alike, failed at the first
  load frame: the renderer died with SIGSEGV (SEGV_MAPERR 0x84, a recursive tree walk; chrome.log of run 39862057861) about 0.5 s after the
  first frame of any rewrite page wider than 860 px. Runs: 39850913549, 39850930778, 39852501132, 39854385797, 39855096795, 39855102093,
  39855917125, 39856570778, 39857307732, 39857312848, 39857318162, 39859911878, 39860551961, 39861279374, 39862057861.
- Chromium counts, profile `people-o-hover` v2, desktop 1280 x 800, base vs flag `people.o:preview-translate`, 3 runs per arm on separate
  CI jobs (base run 39881189724, flag run 39881193403): MEASURED. Premise: the profile sets `text-wrap: wrap !important` (the desktop-1280
  workaround, no text balancing), so these counts hold for that page only; desktop only, so no iPhone felt gain; Safari on a Mac is task
  gpu-safari-lane. Scenario v2: rest 10, approach (anchor 250), open 110, hover 60, scroll 40 frames at 3 px per frame, tail 10.

  | scroll phase, 40 frames | base | flag |
  |---|---|---|
  | trace.Layout | 67 | 28 |
  | trace.Layout.dirtyObjects | 2139 | 969 |
  | frames with a Layout | 40 | 26 |
  | trace.UpdateLayoutTree | 191 | 191 |
  | trace.Paint | 149 | 150 |
  | trace.PrePaint | 120 | 120 |
  | trace.UpdateLayer | 1070 | 1070 |
  | raster.invalidationAreaPx | 308551 | 308551 |

  Layout per scroll frame, base: 1 for frames 0-14, 2 for frames 15-39, 3 at frames 26 and 28. Flag: 1 at frame 0, 0 for frames 1-14, 1 for
  frames 15-39, 2 at frames 26 and 28. The card is the 1 Layout per frame removed; the second Layout source that starts at frame 15 is not
  the card (not diagnosed, follow-up). The series is identical across the 3 runs of each arm. Classes (fwcore, kMax 4, tMax 24): base
  trace.Layout, dirtyObjects and UpdateLayoutTree deterministic, Paint quarantined; flag trace.Layout, dirtyObjects, UpdateLayoutTree and
  Paint stable (k2 to k4). The phase sums are equal across the flag runs, so the flag classes come from small differences of UpdateLayer and
  invalidation area in the open and hover phases, not from the scroll phase. Data: results/people-o-preview-translate/followups.json.
- Scenario v1 (hover 12 frames, 10 px per frame, anchor 140; runs 39879309834 base, 39879313255 flag) counted 55 Layout in the scroll phase
  in both arms: a no-win by non-engagement, not a result for the flag. The flag never took its keep path (0 translate frames, `top`
  rewritten every frame). INFERRED cause: the face still slid in x after the hover (card left 380.906, .734, .594 ..., decay about 0.8 per
  frame) and keep needs an equal x; the card also closed after 10 scroll frames (the heading under 35 percent visible, `logic.ts`).
  Lesson: a count of a "keep" path needs a probe that shows the path was taken; v2 settles the face (hover 60 frames), scrolls 3 px per
  frame, and the probe shows translate on 49 frames. Runs 39878167282 and 39878174234 failed because the profile key `probe` is the crash
  probe of host.mjs (renamed `cardProbe`).
- Open-card probe (run.mjs, profile key `cardProbe`): after the counted pass it replays the plan and records per frame the card rect, the
  rect of its face, the inline top, left and translate, a PNG hash of the viewport and a PNG hash of the card rect grown by 60 px
  (`HeadlessExperimental.beginFrame` screenshot, decoded by png-region.mjs). Compare: results/people-o-preview-translate/probe-compare.mjs.
  Base r1 vs flag r1 and r2 vs r2: 40 scroll frames with the card in both, 0 rect differences (max 0 px), 0 card-pixel differences, translate
  on 49 frames of the flag. Pair 3: rect equal in all 40 scroll frames, but the card pixels differ in all 40: flag run 3 is the one run of
  six that differs from the other five (identical in the scroll phase); its card left is 0.92 px off from the first hover frame on, before
  any scroll frame, where the flag does nothing (INFERRED: a start-phase difference of the card animation, not the flag; 3 runs per arm
  cannot show it). So the look claim: rect identical in 3 of 3 pairs, pixels identical in 2 of 3 pairs, the third unexplained. The viewport
  PNG hash is noise (50 differing frames base vs flag and 49 base vs base); the card-region hash is deterministic
  (base r1 = r2 = r3).
- The base card rect moves 6 px per frame in the scroll phase while the face moves 3 px and the inline `top` moves 3 px: the card sits at an
  offset from `top` that itself changes with the scroll. The `containing` list (ancestors with transform, filter, contain) holds only the
  card with `will-change`; the cause is not diagnosed (follow-up). It is the same in both arms.
- Load diagnostics of run.mjs (Target.setDiscoverTargets, lifecycle, console, exception, dialog and target listeners) are behind
  `FW_LOAD_TRACE` (host.mjs passes it through); the crash exit (`Inspector.targetCrashed`, exit 76) and the hang watchdog stay on. Test:
  packages/measure-chromium/test/profile.test.mjs.
- The `snapDev rows` case of preview.golden.test.ts called no site code (snapDev is the browser's device-pixel rounding); the case is
  dropped and the file says snapDev is proved in Lean (`snapDev_add`, `snap_noFlip`).
