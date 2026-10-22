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
| layer budget 0 (no `will-change`, the card is already a layer) | `layer_budget_zero` |

## Measured

- Breakpoint gate, both engines, flag `people.o:preview-translate`: run 39850908365 at dce0985, success. Config 08b2ef03265b7880
  (the flagged page, read from the loaded page), chromium and playwright-webkit, row `people.o`: all cells pass except the two WebKit cells
  that cannot be built on that engine (UNREACHABLE: primary-pair, whole-width), no FAIL. MEASURED. The gate cells do not hover, so
  the card is closed in them: this shows the closed page is unchanged, not the open card (the open card is the Lean theorem above).
- Chromium counts, profile `people-o-hover` (1280 x 800, synthetic mouseover): see below.
