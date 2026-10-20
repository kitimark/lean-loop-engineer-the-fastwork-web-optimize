---
id: 2026-10-20-cmr-margin-typed-om
kind: note
title: "cmr-margin-typed-om: computedStyleMap() margin reads are the computed value in both engines, also in a skipped subtree and under a scaled ancestor"
status: draft
created: 2026-10-20
topics: [gate, commission, margin, typed-om, content-visibility, premise, chromium, webkit]
---

Question: does `el.computedStyleMap().get(k)` return the computed margin (not the used one) for k in margin-left,
margin-right, margin-inline-start, margin-inline-end: a CSSKeywordValue `auto` for an auto margin, a percent
CSSUnitValue for a percentage, a px CSSUnitValue for a fixed length? Asked for the redesign of the commission margin
verdict (task commission-margin-recur, split into cmr-margin-typed-om, cmr-margin-rect-rule, cmr-strut-asym). This task
is the premise only: no gate change, no workaround.

Unit of decision: the premise verdict per engine x case (normal flow, skipped content-visibility:auto subtree, ancestor
`transform: scale(0.916667)`) x value kind (auto, percent, px), each over the four keys. MEASURED on CI.

## Verdict

MEASURED: all 36 cells per engine (3 cases x 3 kinds x 4 keys) hold, in each of 3 runs, on both engines (216 cells in
all). No cell differs. The premise is not refuted.

| engine | case | auto | percent (10% / 20%) | px (30px / 40px) |
|---|---|---|---|---|
| Chromium 156.0.8078.4 | normal flow | keyword `auto` x4 | percent 10, 20, 10, 20 | px 30, 40, 30, 40 |
| Chromium 156.0.8078.4 | skipped cv subtree | keyword `auto` x4 | percent 10, 20, 10, 20 | px 30, 40, 30, 40 |
| Chromium 156.0.8078.4 | scale(0.916667) ancestor | keyword `auto` x4 | percent 10, 20, 10, 20 | px 30, 40, 30, 40 |
| WebKit 27.2 (Playwright) | normal flow | keyword `auto` x4 | percent 10, 20, 10, 20 | px 30, 40, 30, 40 |
| WebKit 27.2 (Playwright) | skipped cv subtree | keyword `auto` x4 | percent 10, 20, 10, 20 | px 30, 40, 30, 40 |
| WebKit 27.2 (Playwright) | scale(0.916667) ancestor | keyword `auto` x4 | percent 10, 20, 10, 20 | px 30, 40, 30, 40 |

The four values of a cell are in key order margin-left, margin-right, margin-inline-start, margin-inline-end (ltr page,
so start = left, end = right). Percent values are `CSSUnitValue` with unit `percent`, px values with unit `px`.

Runs (MEASURED; workflow `premise-tests`, commit 2539f31e, separate runs on separate branches and jobs):

| run | branch | prem.cv.margin-typed-om Chromium | WebKit | run verdict |
|---|---|---|---|---|
| 39354607925 | ci/cmr-margin-typed-om | holds | holds | green |
| 39354637553 | ci/cmr-margin-typed-om-b | holds | holds | green |
| 39354644363 | ci/cmr-margin-typed-om-c | holds | holds | red: `clock.raf-timeline` on WebKit (rAF and timeline time differ by 2 ms) and `anim.list` on WebKit (acked, intermittent); both unrelated to this premise |

Engine lane: the premise-tests workflow (`.github/workflows/premise-tests.yml`): Chrome Headless Shell 156.0.8078.4 and
Playwright WebKit 27.2 on Linux arm. This is not the iOS Simulator WebKit.framework of the counts lane; the premise is
shown for the engine source (WebKit-7625.1.29.10.29 pin) and for Playwright's build, not for the Simulator.

## Precondition and what the read does to the lock (MEASURED)

The page has one `content-visibility:auto` section per (kind, key) read, so no read can unlock the subtree of another.
Before each read the test asserts `checkVisibility({contentVisibilityAuto:true})` is false (skipped) for the skipped case
and true for the other two; the test fails if that precondition is wrong, so a "skipped" cell is never vacuous. All 36
skipped reads per engine per run met it. After the Typed OM read the node was still skipped in every cell, both engines.

Contrast, same pages family: `getComputedStyle(n).marginLeft` in a skipped subtree returns the used `150px`, not `auto`
(the finding `premise.cv.auto-margin`, red in every run above on both engines; `cv.read-forces-lock`). So the Typed OM
read is the way to see the specified kind of a margin (auto, percent, px) in a skipped subtree; it does not give the used
px value, by design.

## Read path (CONFIRMED from source)

Chromium, `third_party/blink/renderer/core/css/cssom/computed_style_property_map.cc@f842f52`:
- `ComputedStylePropertyMap::GetProperty` (line 95) calls `UpdateStyle()` (line 67: `UpdateStyleAndLayoutTreeForElement`,
  style only) and returns `ComputedStyleUtils::ComputedPropertyValue(CSSProperty::Get(id), *style)` (line 118-119).
- `core/css/properties/computed_style_utils.h:512-514@f842f52` declares `ComputedPropertyValue(const CSSProperty&, const
  ComputedStyle&, const LayoutObject* = nullptr)`; `computed_style_utils.cc:5265-5270` forwards to `CSSValueFromComputedStyle(style,
  layout_object, false, kComputedValue)`. So the layout object is null on this path.
- `core/css/properties/longhands/longhands_custom.cc:6933-6944@f842f52`, `MarginLeft::CSSValueFromComputedStyleInternal`: the used value
  `box->MarginOutsets().left` is returned only `if (const LayoutBox* box = DynamicTo<LayoutBox>(layout_object))` and the
  margin is not fixed; with a null layout object it falls through to `ZoomAdjustedPixelValueForLength(style.MarginLeft(),
  style)`, i.e. the specified auto, percent or px length.
- Citation fix: the task text gave `computed_style_property_map.cc:129-130`; those lines are `GetCustomProperty`'s call with
  a null layout object. The built-in property path is lines 118-119 plus the default argument above; same conclusion.

WebKit, pin WebKit-7625.1.29.10.29 (862f17d):
- `Source/WebCore/css/typedom/ComputedStylePropertyMapReadOnly.cpp:56-59`: `propertyValue` calls
  `Style::Extractor::propertyValue(id, UpdateLayout::Yes, PropertyValueType::Computed)`.
- `Source/WebCore/style/StyleExtractor.cpp:473-480`: for `Computed` the renderer passed on is `nullptr` (the `Resolved`
  type passes `computeRenderer()`; line 478).
- `Source/WebCore/style/StyleExtractorCustom.h:484-486`, `MarginEdgeSharedAdaptor::computedValue`: `box =
  dynamicDowncast<RenderBox>(state.renderer); if (!box) return functor(value);` returns the style's margin edge, so auto,
  percent and px stay as specified. (The used-value branches from line 487 on need a renderer and are not reached.)
- WebKit still asks for layout: `StyleExtractor.cpp:356-357` marks margins layout-dependent for a RenderBox, so
  `UpdateLayout::Yes` runs `updateLayoutIgnorePendingStylesheets({TreatContentVisibilityHiddenAsVisible,
  TreatContentVisibilityAutoAsVisible})` (line 452) but the value does not depend on it. The measurement shows the subtree
  is still skipped afterwards in Playwright WebKit (so that treat-as-visible scope is temporary).
- The scaled ancestor changes no computed value in either path: a transform is not an input of the computed length.

## Artifacts

- Page `packages/premise-tests/pages/cv.margin-typed-om.html`; test `prem.cv.margin-typed-om` in
  `packages/premise-tests/src/tests.mjs` (observed: every cell with value, skipped-before, skipped-after).
- Lean premise `cv.margin-typed-om` ($p_{33}$) in `lean/Fw/Ops/Premise.lean`, theorem field `planned:cmr-margin-rect-rule`;
  golden `packages/contracts/golden/ops/premise.jsonl` regenerated (`cd lean && lake env lean --run scripts/PremiseGolden.lean`).
- No circleci fixture change: `scripts/circleci.test.mjs` (45/45) replays the recorded runs unchanged.

## Follow-ups (not decided here)

- The combination skipped + scaled ancestor is not a cell of its own (each factor is shown alone, and neither enters the
  Chromium or WebKit read path above); cmr-margin-rect-rule may add it as a test when it relies on it.
- The Simulator WebKit.framework lane was not measured; the source read path above is for its pinned tag.
- Run `39354644363` shows two WebKit premise findings (`clock.raf-timeline`, 2 ms; `anim.list`, acked) that are
  independent of this task.
- `pnpm fw ci wait` stopped at once with `tooBig` for this branch: the shared poller carries a watched entry (run id
  1000000000838323, created 4.5 h earlier) whose list takes 11 pages. The three runs were read with `gh run list` after
  a sleep and `gh run download`, not with a wait loop.
