# nav.hitTest:elements-skip: same class, no toggle restyle (task hittest-elements-proof)

## Result
- PROVED in Lean (`lean/Fw/Parts/NavHitTestElements.lean`): under the engine premises named below, `elements-skip`
  decides the same hit, so the same `is-on-dark` class, as the faithful probe on every frame (`same_class`,
  `same_onDark`, `same_onDark_run`). It adds no style-dirtying access to a frame, while the faithful probe adds
  exactly two (`elements_frame_no_style_dirt`, `faithful_frame_style_dirt`). Neither probe dirties layout
  (`probes_no_layout_dirt`). Axioms: propext, Classical.choice, Quot.sound only.
- MEASURED on Chromium (CI, swipe-v1, 3 runs per arm, sha d7b257a): 2 fewer RecalculateStyles (`UpdateLayoutTree`)
  on each of the 535 swipe frames, in every approach zone. Layout is unchanged. Elements restyled fall by 32.6 %.
- Not measured: WKTR (no lane runs a flag on the rewrite, see Open) and the iPhone (accepted limit).

## Model
A box under the probe point has a `src` for its used `pointer-events`: fixed by a declaration (hit or not), or
inherited from the nav root. The faithful probe sets the root to `none`, takes the first box with a used hit
(`elementFromPoint`), then restores the root. `elements-skip` leaves the root alone, takes the whole penetrating list
plus the document element (`elementsFromPoint`), and picks the first box that is outside the nav or matches
`ALLOW_SELECTOR`.

Engine premises, CONFIRMED from source and kept as named premises in the model, not proved:

| premise | Chromium @f842f52 | WebKit @862f17d |
|---|---|---|
| `pointer-events` is inherited | `css/css_properties.json5:5316-5320` | `css/CSSProperties.json:7872-7874` |
| a box with used `none` is skipped, its descendants are still tested | `paint/box_fragment_painter.cc:139-143,2373-2377`, `layout/layout_object.h:2738-2743` | `rendering/RenderElementStyleInlines.h:162-168`, `RenderBlock.cpp:2084-2086`, `RenderBox.cpp:1721` |
| `inert` makes used `pointer-events` none | `style/computed_style.h:1858-1863` | `RenderObject.cpp:2409-2414`, `StyleComputedStyle+GettersInlines.h:130-133` |
| `elementFromPoint` is the first box of the same walk | `dom/tree_scope.cc:268-302` | `dom/TreeScope.cpp:402-434` |
| `elementsFromPoint` lists every hit box top-most first, dedups, appends the document element | `dom/tree_scope.cc:396-437` (415-418 append) | `dom/TreeScope.cpp:436-490` (486-489 append), `rendering/HitTestResult.cpp:846-847` |
| neither request ignores `pointer-events` | `layout/hit_test_request.h:69` (kIgnorePointerEventsNone unset) | `dom/TreeScope.cpp:410,449-453` (default types; ReadOnly, Active, CollectMultipleElements, IncludeAllElementsUnderPoint) |

Site premises (`Premises`, decidable): outside the nav no box inherits from the nav root (inheritance follows the
DOM, and `nav.contains` is the DOM subtree); inside the nav an allow-listed box never inherits from the root, and
every box whose own declaration is `auto` is allow-listed. Sources: `apps/site/src/parts/nav/nav.module.css:63-66,
128-132,167-177,186-200`, `morph.panel/morph.module.css:12,19-20`, `nav/index.tsx:133-140`,
`nav.hitTest/logic.ts:87-88`. INFERRED for the shipped CSS: no generator checks the allow-list against the
stylesheet yet (ledger n=4, `missingWhy` 1).

Each site premise is necessary: `needs_allow_not_root`, `needs_allow_reEnabled` and `needs_outside_fixed` give a
stack where dropping it makes the answers differ.

## Toggle invalidation
The faithful probe's two inline writes are its only style-dirtying accesses. In Chromium,
`InlineCSSStyleDeclaration::DidMutate` calls `Element::InvalidateStyleAttribute`, which calls `SetNeedsStyleRecalc`
(`css/inline_css_style_declaration.cc:36-53`, `dom/element.cc:13299-13308`). The hit test's
`UpdateStyleAndLayout(kHitTest)` (`dom/tree_scope.cc:232`) pays the first, the next read or frame the second. In WebKit,
`InlineCSSStyleProperties::didMutate` calls `StyledElement::invalidateStyleAttribute` (`css/CSSStyleProperties.cpp:622-643`,
`dom/StyledElement.cpp:190-204`), and `Document::hitTest` pays it in `updateLayout` (`dom/Document.cpp:11545-11546`).
`elements-skip` has reads only (`NavHitTestOpt.probeElements`), so the frame's dirtying list equals the frame without
the probe.

## Golden and replay
`packages/contracts/golden/parts/nav.hitTest.elements.jsonl`: 555 lines (9 named scenes, 3 of them violating a
premise, then every stack of at most two of 9 box kinds, both root states, morph 0, 1/5, 1/4). Each line carries the
premise verdict, both hits and both classes; `stacks_premises` proves the premise for every generated stack.
`apps/site/src/parts/nav.hitTest/elements.golden.test.ts` replays every line through the shipped `probeFaithful` and
`probeElements` on a fake document that filters by used `pointer-events` (it reads the nav's inline value, so the
faithful toggle takes effect) and checks the restore. Lean check: `NavHitTestElements.gen ["--check"]`.

## Chromium counts
Runs: faithful rewrite 40081984397, rewrite `?fw=nav.hitTest:elements-skip` 40081975943. Values are the median of
3 runs per zone (`Fw.Measure.zoneSums`, 500 px zones); frames per zone are equal in all 6 runs.

| zone | frames | UpdateLayoutTree | elements restyled | Layout | HitTest |
|---|---|---|---|---|---|
| rest | 10 | 10 → 10 | 210 → 210 | 3 → 3 | 0 → 0 |
| y00000 | 49 | 199 → 101 | 7094 → 5624 | 50 → 50 | 98 → 98 |
| y00500 | 50 | 205 → 105 | 6838 → 5338 | 67 → 67 | 101 → 101 |
| y01000 | 50 | 159 → 59 | 2782 → 1284 | 46 → 46 | 100 → 100 |
| y01500 | 50 | 226 → 126 | 7187 → 5612 | 57 → 57 | 100 → 100 |
| y02000 | 50 | 165 → 65 | 3676 → 2076 | 53 → 53 | 100 → 100 |
| y02500 | 50 | 190 → 90 | 4016 → 2416 | 14 → 14 | 100 → 100 |
| y03000 | 50 | 207 → 107 | 4616 → 3028 | 24 → 24 | 100 → 100 |
| y03500 | 50 | 257 → 157 | 5455 → 3854 | 37 → 37 | 100 → 100 |
| y04000 | 50 | 216 → 116 | 3967 → 2367 | 39 → 39 | 100 → 100 |
| y04500 | 50 | 205 → 105 | 2956 → 1355 | 16 → 16 | 100 → 100 |
| y05000 | 36 | 123 → 51 | 2027 → 877 | 12 → 12 | 72 → 72 |
| tail | 30 | 30 → 30 | 599 → 599 | 0 → 0 | 1 → 1 |
| total | 595 | 2192 → 1122 | 51423 → 34640 | 418 → 418 | 1072 → 1072 |

Per-run totals: UpdateLayoutTree is 2192, 2189 and 2192 faithful, 1119, 1122 and 1122 with the flag; Layout is 418,
417 and 418 faithful, 417, 418 and 418 with the flag.
The drop is 2 per swipe frame in every zone (98 for 49 frames, 72 for 36), which is the Lean count
(`NavHitTestOpt.elements_style_two`, `faithful_frame_style_dirt`); the rest and tail zones are
unchanged. Layout equal matches `NavHitTestOpt.elements_layout_eq`. HitTest events are equal, so the list
hit test adds no event; its per-call cost (uncached, penetrating: ledger n=4) is not resolved by these counters.
About 28 fewer elements are restyled per swipe frame: INFERRED to be the nav subtree that inherits the toggled
`pointer-events`.

## Open
- WKTR per approach zone: `.github/workflows/wktr.yml:190-191` runs `--site snapshot/site` only, with no target or
  flag input, and `fw run` has no WKTR lane (`docs/team/tools/fw-run.md`). Needs a rewrite+flag input on that
  workflow. A WebKit Simulator pair (`fw run --target rewrite --engines webkit`, with and without the flag) would
  give WebKit counts meanwhile; not run (dispatch budget used).
- Allow-list generated from the stylesheet (ledger n=4 `missingWhy` 1) would turn the site premise from INFERRED
  into a check.
