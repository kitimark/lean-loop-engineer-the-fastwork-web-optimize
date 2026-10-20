---
id: 2026-10-21-morph-scroll-lock
kind: note
title: "morph.tween:scroll-lock (C4): lock the root while the morph runs instead of pinning it every scroll frame"
status: final
created: 2026-10-21
authors: [agent:lean-prover]
topics: [morph.tween, scroll, webkit, chromium, lean]
---

# morph.tween:scroll-lock (Region B candidate C4)

Source of the candidate: `research/notes/2026/10-20-webkit-lag-source.md` §C4. Lean: `lean/Fw/Parts/MorphTweenOpt.lean`,
section MT-L. Golden: `packages/contracts/golden/parts/morph-tween-scroll-lock.jsonl` (`lockJsonl`, pinned by `#guard`).

## Verdict

| platform | premise (the lock stops the fight) | Lean | status |
|---|---|---|---|
| Mac trackpad, WebKit | holds for a gesture in flight, from the first scrolling-tree commit after the lock | `forced_lt`, `shown_lock` | CONFIRMED path, gain INFERRED |
| Chromium (wheel, touch) | holds: the compositor drops the delta of a root that is not user-scrollable | `forced_lt` | CONFIRMED path, gain INFERRED |
| iPhone, WebKit | **fails**: a pan in flight and its deceleration are not stopped by `overflow: hidden` | `ungated_eq`, `work_ungated` | refuted (UIKit part INFERRED) |
| trajectory probe (one prevented wheel) | nothing to stop | `still_eq`, `work_still` | MEASURED, see CI below |

The arm is a look change (class L): in a gated gesture in flight the page no longer jumps by one delta before the pin puts it
back, and the overlay scrollbar hides while the morph runs. It is registered as a `proposal`, not `optimized`.

## The faithful pin (what C4 replaces)

`apps/site/src/parts/morph.tween/driver.ts`: `pin()` runs on every scroll frame (`registerScroll`, order 110) and calls
`scrollTo({top: pinned, behavior: 'instant'})` while `isActive()` and `scrollY ≠ pinned`. `isActive` is `target > 0.001 ||
value > 0.001`, so it holds for the whole time the morph is open, not only for the 680 ms tween. New input during the morph
never scrolls: the wheel and touchmove listeners (capture, non-passive) prevent every taken push, and every delta is taken
while active. The fight comes only from a gesture already latched to async scrolling before the morph became active
(lag-source note §Input).

## Engine paths (CONFIRMED by source)

- **Root `overflow: hidden` → no scrollbars.** WebKit `LocalFrameView::calculateScrollbarModesForLayout` maps `Hidden` to
  `ScrollbarMode::AlwaysOff` on both axes (`Source/WebCore/page/LocalFrameView.cpp:642-668`@862f17d);
  `canHaveScrollbars()` is false when both modes are `AlwaysOff` (`ScrollingTreeScrollingNode.h:131`@862f17d).
- **Mac.** `ScrollingTreeScrollingNode::canHandleWheelEvent` returns false when `!canHaveScrollbars()`
  (`ScrollingTreeScrollingNode.cpp:233-236`@862f17d), so the latched root node leaves the event unhandled
  (`ScrollingTree.cpp:191-199`@862f17d; `ScrollingTreeFrameScrollingNodeMac.mm:146`@862f17d) and the remaining deltas and the
  momentum of the gesture move nothing once the commit that carries the new modes has landed.
- **iPhone.** `hasScrollableOrZoomedMainFrame` is `canHaveScrollbars() || visualViewportIsSmallerThanLayoutViewport`
  (`RemoteScrollingCoordinatorProxy.cpp:475-483`@862f17d). When it is false, `WKWebViewIOS.mm:1100-1104`@862f17d sets
  `panGestureRecognizer.allowedTouchTypes = @[]` (no new touches) but still calls `_setScrollEnabledInternal:YES`, so a pan that
  UIKit already recognized and its deceleration continue (INFERRED: UIKit is closed source). New touches during the morph are
  already prevented by the touchmove listener, so the lock adds nothing there.
- **Chromium.** `ScrollTree::ScrollBy` zeroes the delta on an axis that is not user-scrollable
  (`cc/trees/property_tree.cc:2471-2480`@f842f52), as does `InputHandler::UserScrollableDelta`
  (`cc/input/input_handler.cc:2663-2672`@f842f52); the LayoutView's user-scrollability follows its scrollbar modes
  (`third_party/blink/renderer/core/paint/paint_layer_scrollable_area.cc:850-878`@f842f52).
- **Gutter.** Blink keeps a gutter for `overflow: hidden` only with `scrollbar-gutter: stable` and a classic scrollbar
  (`third_party/blink/renderer/core/layout/layout_box.cc:1474-1494`@f842f52); WebKit likewise
  (`LocalFrameView::scrollbarGutterWidth`, `LocalFrameView.cpp:7322-7333`, `scrollbarGutterStyle` 7197-7203@862f17d;
  pref `CSSScrollbarGutterEnabled` stable, default on, `UnifiedWebPreferences.yaml:1444-1456`@862f17d). So a lock on a classic
  scrollbar without `stable` widens the layout viewport by the scrollbar width (`gutter_shift`); with `stable` the width stays
  but the scrollbar is no longer painted, which is a look change (`gutter_stable`).

## Design

The arm sets `document.documentElement.style.overflow = 'hidden'` at the push that makes the morph active and clears it at
the tick or push that makes it inactive (and at dispose), **only when the root scrollbar is an overlay one**
(`innerWidth − documentElement.clientWidth ≤ 0`, read at the lock, right after `isArmed()` has flushed layout). On classic
scrollbars it writes nothing and is the original (`classic_writes`). The pin stays as a backstop. TS: `scroll-lock.logic.ts`
(`overlayOf`, `lockOn`, `lockWrite`), `driver.ts` (`env.lock`, `syncLock`), `index.tsx`; checked against the Lean golden by
`scroll-lock.golden.test.ts` (overlay rows, 4 replayed histories through the driver, 4 spans through `pin()`).

## Lean (MT-L)

- `runL_s`, `runL_locked`: the arm's tween is the original's after every history; the root is locked iff overlay and active.
- `seen_eq`, `span_seen`: on every frame the position the main thread sees after `pin()` is the pinned `p`, in both arms.
- `forced_le`: from the pinned position the arm calls `scrollTo` at most as often as the original; `forced_lt`: strictly
  fewer once the lock is committed (frame `k`) and one gated nonzero delta arrives; `shown_lock`: under a committed lock a gated
  frame shows `p`.
- `ungated_eq`, `still_eq`: with ungated input (iPhone pan) or no delta (the probe) the spans are identical.
- Work (`spanWork`: `scrollTo` calls + 2 root writes): `work_le` when the lock saves ≥ 2 calls; `work_still`, `work_ungated`:
  the arm costs exactly 2 root writes (each a style recalc and layout of the root) more than the original.
- `gutter_same`: the gutter (layout width) is the original's in every environment; `gutter_shift`, `gutter_stable` as above.
- `lock_vis`: `VisSame E` for a scene built from the tween, the seen position and the gutter.

Model limits: `Gest.gated` and the commit frame `k` are inputs restated from the engine paths above, not derived; the shown
position of the original during a fight (`shown ≠ p`) is why the arm is class L, and `lock_vis` covers the main-thread view only.

## Known limits

- No rubber-band and no keyboard or scrollbar-drag scrolling while locked (the original pins those back anyway).
- The drawer writes `body.style.overflow` (`overlays.drawer/index.tsx:78-81`); a drawer opened during the morph makes the body
  its own scroll container. No sticky element is on screen at the page end (INFERRED).
- Which branch (overlay or classic) the macOS CI runner takes is not known; on a classic runner the arm is the original.

## CI (trajectory probe)

CI_RESULTS

## Ledger row (for the lead)

LEDGER_ROW
