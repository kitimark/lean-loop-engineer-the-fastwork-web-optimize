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

Ref `ci/morph-scroll-lock` at e01287a, `--engines both`, reps 5. Lean `outcome` lines (`Fw.Gate.Trajectory.outcome` over
`Fw.Preset.Gen.storedOf`, read from a scratch script without writing the stored file; MEASURED):

| run | arm | chromium hero | chromium morph | linux-webkit hero | mac-webkit hero | mac-webkit morph |
|---|---|---|---|---|---|---|
| 39496271199 | `--fw morph.tween:scroll-lock` | pass | pass | pass | pass | no verdict: coverage |
| 39498373119 | `--fw morph.tween:scroll-lock` | pass | pass | pass | pass | no verdict: coverage |
| 39500347224 | A/A (default config) | pass | pass | pass | pass | fail |

`new` units against the faithful arm (Linux WebKit has no morph path; hero has no `new` unit in any run):

| run | chromium morph content | chromium morph coverage | mac morph content | mac morph coverage (units per width) |
|---|---|---|---|---|
| 39496271199 (flag) | 1, close@0 | 0 | 3, all close@0 | 390: 168, 640: 42, 641: 126, 1280: 126 |
| 39498373119 (flag) | 1, close@0 | 0 | 2, all close@0 | 390: 84, 640: 42, 641: 42, 1280: 42 |
| 39500347224 (A/A) | 0 | 640: 42 | 4: 3 at close@0, 1 at 390 open@9 (`logo.color`) | 390: 84, 641: 42, 1280: 84 |

- **Close@0 units (the known judge gap, task trajectory-close-start): reported, not counted.** Flag run 1: Chromium 640
  `earn.max-width`; mac 390 `earn.opacity` and `earn.max-width`, 640 `nav.background-color`. Flag run 2: Chromium 640
  `earn.max-width`; mac 640 `nav.background-color`, 1280 `earn.max-width`. A/A: mac 390, 641 and 1280 `earn.max-width`. The A/A
  `fail` comes from these units only. Without them its mac morph cell is also "no verdict: coverage".
- **Beyond the A/A floor: none.** No content `new` unit outside close@0 in either flag run. Coverage `new` units (empty sample
  buckets) sit on mac morph at 3 or 4 widths in every run, A/A included. Flag run 1 has more of them at 390, 641 and 1280.
  Run 2 is at the A/A level. The difference is INFERRED to be runner timing, not the flag.
- **As predicted, the probe cannot show the lock's gain.** It opens the morph with one wheel event, which the listener
  prevents (`still_eq`, `work_still`). No gesture is in flight to stop, so both arms see the same frames. Measuring C4 needs a
  probe step with a trackpad gesture latched before the armed band. Which scrollbar kind the macOS runner has, and so whether
  the arm locked there at all, was not recorded.

## Ledger row (for the lead)

`n` is left for the lead to assign.

```json
{
  "id": "morph.tween.scrollLock",
  "part": "morph.tween",
  "candidate": "morph.tween:scroll-lock (C4): hold the root at overflow: hidden while the morph is active, on overlay scrollbars only, instead of relying on the scrollTo pin alone",
  "status": "look-change",
  "flag": "morph.tween:scroll-lock",
  "chromium": "premise-holds",
  "webkit": "premise-holds on Mac (trackpad gesture in flight); premise-false on iPhone (pan in flight not stopped)",
  "visual": "look change (L) during a gated gesture in flight: the page no longer jumps one delta before the pin returns it, and the overlay scrollbar hides while the morph runs; the main-thread position and the layout width are the original's (lock_vis, gutter_same)",
  "mechanism": "CONFIRMED (source): root overflow hidden sets both scrollbar modes AlwaysOff (LocalFrameView.cpp:642-668@862f17d), so canHaveScrollbars() is false (ScrollingTreeScrollingNode.h:131@862f17d). On Mac canHandleWheelEvent then returns false (ScrollingTreeScrollingNode.cpp:233-236@862f17d), which stops a latched gesture and its momentum. On Chromium ScrollTree::ScrollBy zeroes a delta on an axis that is not user-scrollable (cc/trees/property_tree.cc:2471-2480@f842f52). On iPhone WKWebViewIOS.mm:1100-1104@862f17d clears allowedTouchTypes but keeps scrollEnabled, so a recognized pan and its deceleration continue (UIKit part INFERRED). Classic scrollbars: the lock would shift the layout by the scrollbar width without scrollbar-gutter: stable (layout_box.cc:1474-1494@f842f52, LocalFrameView.cpp:7322-7333@862f17d), so the arm locks only on overlay scrollbars.",
  "leanFor": [
    "Fw.Parts.MorphTweenOpt.lock_vis",
    "Fw.Parts.MorphTweenOpt.seen_eq",
    "Fw.Parts.MorphTweenOpt.forced_le",
    "Fw.Parts.MorphTweenOpt.forced_lt",
    "Fw.Parts.MorphTweenOpt.shown_lock",
    "Fw.Parts.MorphTweenOpt.gutter_same",
    "Fw.Parts.MorphTweenOpt.runL_s",
    "Fw.Parts.MorphTweenOpt.runL_locked",
    "Fw.Parts.MorphTweenOpt.classic_writes",
    "Fw.Parts.MorphTweenOpt.work_le"
  ],
  "leanAgainst": [
    "Fw.Parts.MorphTweenOpt.ungated_eq",
    "Fw.Parts.MorphTweenOpt.work_ungated",
    "Fw.Parts.MorphTweenOpt.work_still",
    "Fw.Parts.MorphTweenOpt.gutter_shift"
  ],
  "missingWhy": [
    "the gain needs a gesture in flight; the trajectory probe pushes with one prevented wheel, so it cannot show it (still_eq). MEASURED: no unit beyond the A/A floor outside close@0 in runs 39496271199 and 39498373119 against A/A 39500347224. Mac morph is no verdict: coverage in all three runs once close@0 is excluded",
    "iPhone: refuted (ungated_eq: the arm is the original plus 2 root writes)",
    "Gest.gated and the commit frame k are model inputs restated from the engine paths, not derived"
  ],
  "premises": [],
  "v1Evidence": "none",
  "lesson": "overflow: hidden on the root stops only the scrolls that the async scroller gates. On iPhone a pan that UIKit already recognized does not stop, so a scroll lock helps only where the engine checks scrollability per event. A lock also changes the look and, on classic scrollbars, the layout width.",
  "next": "Out of v2-proved (look change, class L). A probe step with a trackpad gesture latched before the armed band (Mac, Chromium) would measure the scrollTo saving. The user's visual review decides whether the look change is acceptable.",
  "evidence": "trajectory-probe runs 39496271199 and 39498373119 (flag), 39500347224 (A/A), ci/morph-scroll-lock at e01287a, both engines; note research/notes/2026/10-21-morph-scroll-lock.md"
}
```
