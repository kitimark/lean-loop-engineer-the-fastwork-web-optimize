---
id: 2026-10-20-nav-oof-root-finding
kind: note
title: "No boundary that leaves the fixed nav's containing block at the view can scope its relayout (negative finding)"
status: final
created: 2026-10-20
topics: [layout, containment, nav, morph, chromium, webkit, negative-finding]
---

**Answer.** Containment that leaves the nav's containing block at the view cannot shrink the layout pass a dirty nav
schedules, in either engine and at any breakpoint. The nav is `position: fixed` and its containing block is the view.
Both engines start the marking walk above the dirty box. For an out-of-flow box the walk jumps to its containing block,
and the boundary test runs only on the objects the walk reaches. The first object reached is the view, so the root is
the view for every choice of boundaries that leaves the nav's containing block at the view, `contain` on the nav
included. Lean: `Fw.Parts.NavOofRoot.Tree.oof_view_full`. `contain: layout` or `paint` (or a transform) on html, body or
#root, or a filter on body or #root, moves the nav's containing block to that element (Chromium
third_party/blink/renderer/core/layout/layout_object.cc:2013-2021,2049-2061@f842f52; WebKit
Source/WebCore/rendering/RenderElementStyleInlines.h:55-79,89-93@862f17d), which re-anchors the fixed nav. That is a
visual change (INFERRED: the document scrolls, so a nav positioned against html, body or #root scrolls with it), outside
this finding. That candidate is ruled out by the visual change, not by the theorem; in the model where each boundary is
also a fixed container, Lean `nav_contained_root` shows its pass is partial. No site change.

## Measurements (MEASURED)

Run 39292323514 (`chromium-counts`, ref `ci/c3-gate`, sha 639f947, profile swipe-touch-v1, Chrome Headless Shell
156.0.8078.4), artifacts `chromium-counts-rewrite-r1..r3`. The nav CSS and the nav's place in `App.tsx` are the same
at 639f947 and at this branch's base.

| frames | run | Layout passes | dirtyObjects | totalObjects | partial | elementCount | FireAnimationFrame |
|---|---|---|---|---|---|---|---|
| 498-530 | r1 | 33 | 1077 | 52470 | 0 | 10619 | 29 |
| 498-530 | r2 | 33 | 1077 | 52470 | 0 | 10496 | 29 |
| 498-530 | r3 | 33 | 1077 | 52470 | 0 | 10623 | 30 |
| 517-530 | r1-r3 each | 14 | 448 | 22260 | 0 | 4452 | 0 |

- One Layout pass per frame, 32 dirty objects per pass (53 in frame 503), totalObjects 1590 per pass, which is the
  whole tree. The layout counters are identical in r1-r3.
- `partial` 0 means no subtree root was scheduled. Chromium's Layout trace event writes `partialLayout` from
  `CountObjectsNeedingLayout` (third_party/blink/renderer/core/inspector/inspector_trace_events.cc:637-643@f842f52),
  which is `HasSubtreeLayoutRoots()` and otherwise counts from the LayoutView
  (third_party/blink/renderer/core/frame/local_frame_view.cc:690,695-696@f842f52). CONFIRMED.
- Attributing these 32 objects per frame to the nav morph is INFERRED: the nav's top, width and height are functions
  of `--morph`, but the trace names no object.
- WebKit was not measured. The WebKit half of the finding rests on source alone.

## Mechanism (CONFIRMED, source)

Chromium, `LayoutObject::MarkContainerChainForLayout`
(third_party/blink/renderer/core/layout/layout_object.cc@f842f52):
- The walk starts at `Container()` with `last = this` (:1671-1672).
- When `last` is out of flow, the next object is `last->ContainingBlock()` (:1699-1703).
- After an object is marked it becomes `last`, and only then is `ObjectIsRelayoutBoundary(last)` tested (:1722-1723).
  The dirty object itself is never tested.
- With no boundary the walk ends at the LayoutView and calls `ScheduleRelayout()` (:1731-1732), a full pass.
- The out-of-flow jump also sets `simplified_normal_flow_layout = true` (:1699-1703), so the view is marked for
  simplified layout, not `ChildNeedsFullLayout`. "Full pass" in this note means only that the root is the LayoutView,
  not that every object is laid out in full; totalObjects (1590 per pass) counts the whole tree, not the objects laid
  out.
- A fixed box's container is the nearest ancestor that `CanContainFixedPositionObjects` (:1883-1889).
- `ComputeIsFixedContainer` is true for filter and backdrop-filter except on the document element (:2012-2021), for a
  transform on a box (:2049-2054), and for paint or layout containment (:2055-2061). So a containment boundary on an
  ancestor of the nav is also its containing block.

WebKit, `RenderObject::markContainingBlocksForLayout`
(Source/WebCore/rendering/RenderObject.cpp@862f17d):
- The walk starts at `container()` (:599); `this` is never tested.
- When the previous object is out of flow, the walk skips to the enclosing non-anonymous `RenderBlock` (:619-629).
- `isLayoutBoundary(*ancestor)` is tested on ancestors only (:645-646), and it is true for the RenderView (:519-520).
  `scheduleLayout` with a RenderView root schedules a full layout (:586-587).
- A fixed box's container is the nearest ancestor that `canContainFixedPositionObjects` (:1698-1706).
- `canContainFixedPositionObjects` (Source/WebCore/rendering/RenderElementStyleInlines.h:89-93@862f17d) calls
  `mayContainOutOfFlowPositionedObjects` (:55-79), which is true for a transform (:70), for filter and backdrop-filter
  except on the document element (:71-72), and for layout or paint containment (:64-65, :77). The containment part
  was read in source here; no WebKit run checked it.

The nav, per apps/site/src/parts/nav/nav.module.css (CONFIRMED):
- `position: fixed` (:36) at every breakpoint. No media rule changes `position`, and the phone band (:251-258) changes
  only `top` and the size variables.
- `top` (:14), `width` (:17-20) and `height` (:21) are functions of `--morph`; `left` is the constant 50% (:37).
- The nav is a child of the React root, a sibling of `page-root` (apps/site/src/App.tsx:55). The site CSS sets no
  transform, filter or containment on `html`, `body` or `#root` (apps/site/src/styles/reset.css:59-68). So its
  containing block is the view. INFERRED from source; no engine dump checked it.

## Proofs

`lean/Fw/Parts/NavOofRoot.lean`. Model: a tree numbered so that every container and containing block is smaller
than its object; object 0 is the view. `next` picks the containing block for an out-of-flow object and the container
otherwise. `climb` returns the first boundary on the way up, or the top. `layoutRoot` starts `climb` at `next x`, so
`x` is never tested. `pass` is `full` when the root is the view, else `subtree root`.

| theorem | statement |
|---|---|
| `next_oof`, `next_flow` | one theorem per branch of `next` |
| `climb_stop`, `climb_top`, `climb_step` | one theorem per branch of `climb` |
| `layoutRoot_skips_self` | the root does not change when `x`'s own boundary bit changes |
| `oof_root_indep` | for out-of-flow `x` with containing block `c`, `layoutRoot B x = climb B c` |
| `oof_view_root` | if that `c` is the view, `layoutRoot B x = view` for every `B` |
| `oof_view_full` | under the same hypotheses, `pass B x = full` for every `B` |
| `flow_boundary_subtree` | contrast: an in-flow `x` whose container `c` is a boundary other than the view gets `subtree c` |
| `nav_pass_full` | the nav row of the example tree: `pass B nav = full` for every `B` |
| `nearest_top`, `nearest_hit`, `nearest_step` | one theorem per branch of `nearest`, the first ancestor passing a test |
| `fixedCb_oof`, `fixedCb_flow` | one theorem per branch of `fixedCb`, the tree whose out-of-flow containing blocks are the nearest fixed container |
| `fixedCb_partial_moved` | in `fixedCb fc`, a partial pass from an out-of-flow `x` implies `nearest fc x ≠ view` |
| `fixedCb_boundary_root` | if that containing block is a boundary other than the view, the pass is `subtree` of it |
| `nav_contained_partial_moved` | for the nav with every boundary a fixed container: partial pass implies its containing block is not the view |
| `nav_contained_root` | with that rule, a boundary on #root gives `subtree #root`: partial, with the nav re-anchored to #root |

The brief stated `oof_root_indep` as `layoutRoot B x = layoutRoot B (containingBlock x)`. That form is false when the
containing block is itself a boundary, since `layoutRoot` of the containing block skips the containing block. The
proved form uses `climb B c`, which tests `c` first, as both engines do. `#guard` rows cover the nav, its bar,
an in-flow `main` and the boundary choices all, none, nav only and the React root only.

Model limits: `containingBlock` is independent of `boundary` in `Tree`; in the engines a layout-containment boundary is
also a fixed containing block, which `fixedCb` with `fc = boundary` models. The early returns on an already-dirty
ancestor, display locks, the `allow_subtree_layout_root` gate and WebKit's skip of anonymous blocks are not modelled.
Each of them stops the walk earlier or leaves the root unchanged; none adds a boundary test below the containing block.

## What this changes in the plan

- No containment candidate for the nav morph tail. A `contain` on the nav, or on any element that is not an ancestor
  of the nav, cannot make these passes partial; containment on an ancestor changes the nav's containing block (visual
  change).
- Lesson: containment cannot scope a dirty out-of-flow box whose containing block is the view. Work on such a box
  shrinks only by dirtying fewer objects, for example by animating `transform` instead of `top`, `width` and `height`,
  which is a visual change and needs its own proof.
- Open, handed to task tween-platform-scope: frames 517-530 lay out 32 objects and resolve 318 elements every frame
  with no `FireAnimationFrame` (MEASURED). The WAAPI tween runs without rAF, so that task owns the cause.
- The platform bands (frames 337-388 and 415-460) are INFERRED to be partial already. Their root is unidentified, and
  this note makes no claim about them.
