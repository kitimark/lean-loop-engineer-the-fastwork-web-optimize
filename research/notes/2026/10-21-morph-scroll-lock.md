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
| iPhone, WebKit | **fails**: a pan in flight and its deceleration are not stopped by `overflow: hidden` | `ungated_eq`, `forced_ungated` | refuted (UIKit part INFERRED); the arm is not installed on `(hover: none)` (`engage_touch`) |
| trajectory probe (one prevented wheel) | nothing to stop | `still_eq`, `forced_still` | MEASURED, see CI below |

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

The arm sets `document.documentElement.style.overflow = 'hidden'` at the step that makes the morph active and clears it at
the step that makes it inactive (and at dispose). It engages only where Lean `engage` holds: the primary input can hover
and the root scrollbar is an overlay one.

- **Hover gate.** `index.tsx` installs `env.lock` only when `lockAllowed(matchMedia('(hover: none)').matches)`, read once
  at mount (`mq.hover-none`). On `(hover: none)` the driver has no lock and is the original: no read, no write
  (`engage_touch`, `engage_off_writes`). Touch-only Android is excluded with iOS: whether its pan in flight is gated is not
  checked (INFERRED gated by `ScrollTree::ScrollBy`), so the arm gives up a possible gain there.
- **One read per activation.** The driver reads `overlay()` (`innerWidth − documentElement.clientWidth ≤ 0`) only at the
  step that takes the morph from inactive to active (Lean `readsAt`), before any style write of that step, stores it, and
  `syncLock` uses the stored value (Lean `stepR`; `runR_eq`: the same tween and lock as `runL` with the kind fixed). Ticks
  never read. Round 1 read it on every tick while the lock was off, right after the tick's style writes, which forces a
  style and layout pass per frame on a classic scrollbar (Blink `Element::clientWidth`, `element.cc:2622-2633`@f842f52;
  WebKit `Element::clientWidth`, `Element.cpp:1632-1635`@862f17d). The activating push reaches `push_` only through
  `takenFor`, which calls `isArmed()` (`getBoundingClientRect`) on an inactive morph with no style write before the read, so
  the read finds layout clean (INFERRED).
- **Classic scrollbars.** The arm reads once per activation and writes nothing (`classic_writes`, `rootWrites_classic`).
- The pin stays as a backstop. TS: `scroll-lock.logic.ts` (`overlayOf`, `lockOn`, `lockWrite`, `readsAt`, `lockAllowed`,
  `engage`), `driver.ts` (`env.lock`, `readOverlay`, `syncLock`), `index.tsx`.

Golden test `scroll-lock.golden.test.ts`: the overlay and engage rows; 4 replayed histories through the driver, checking
per event the activity, the root write and the number of `overlay()` calls (row field `read`: 1 at the activating push, 0
on every tick, in `open-close` and `open-close-classic` too); the activating push reads before its first style write; 4
spans through `pin()`, checking the `scrollTo` calls and that the stub's `scrollY` is `p` afterwards. The span rows check
`pin()` only: whether the engine drops a delta is the model input `Gest.gated`, fed to the stub as the shown position.

## Lean (MT-L)

- `runL_s`, `runL_locked`: the arm's tween is the original's after every history; the root is locked iff overlay and active.
- `runR_eq`, `reads_iff`: the read-once driver equals `runL`; a step reads iff it activates the morph.
- `engage_touch`, `engage_classic`, `engage_on`, `engage_off_writes`: one theorem per branch of `engage`; where it is false
  the arm never writes the root.
- `seen_eq`, `span_seen`: on every frame the position the main thread sees after `pin()` is the pinned `p`, in both arms.
- Two work counters, not added together:
  - `scrollTo` calls (`forced`): `forced_le` (never more), `forced_lt` (strictly fewer once the lock is committed at frame
    `k` and one gated nonzero delta arrives), `forced_still` and `forced_ungated` (equal without a gesture or with ungated
    input). `shown_lock`: under a committed lock a gated frame shows `p`.
  - Root style passes (`stylePasses`, `rootWrites`): `style_passes`, `stylePasses true = stylePasses false + 2` per morph;
    the arm never saves one. `rootWrites` is 2 in each overlay golden history and 0 on classic (`rootWrites_classic`).
  - Round 1's `work_le` added the two counters as equal units; no engine source gives a per-unit cost, so it is removed.
    Whether 2 root style passes cost less than the saved `scrollTo` calls is INFERRED and unmeasured.
- `gutter_same`: the gutter (layout width) is the original's for every input and scrollbar kind; `gutter_shift`,
  `gutter_stable` as in Engine paths.
- `lock_vis`: `VisSame E` for a scene built from the tween, the seen position and the gutter, with the arm engaged by
  `engage` on the environment's hover and scrollbar kind.

Model limits: `Gest.gated` and the commit frame `k` are inputs restated from the engine paths above, not derived; the shown
position of the original during a fight (`shown ≠ p`) is why the arm is class L, and `lock_vis` covers the main-thread view only.

## Known limits

- No rubber-band and no keyboard or scrollbar-drag scrolling while locked (the original pins those back anyway).
- The drawer writes `body.style.overflow` (`overlays.drawer/index.tsx:78-81`); a drawer opened during the morph makes the body
  its own scroll container. No sticky element is on screen at the page end (INFERRED).
- `(hover: none)` is read once at mount; a device whose primary input changes later keeps the first decision.
- Where it engages, the arm costs 2 root style passes per morph (`style_passes`) and saves `scrollTo` calls only during a
  gated gesture in flight.

## CI (trajectory probe)

Whether the lock engaged is not recorded by the probe; per lane it follows from the lane's input and scrollbar kind
(widths 390 and 640 load `(hover: none)`, 641 and 1280 `(hover: hover)`, `packages/gate-breakpoints/src/trajectory/registry.mjs:93-95`):

| lane | scrollbar kind | 390, 640 | 641, 1280 |
|---|---|---|---|
| Chromium (Chrome Headless Shell, Linux) | none drawn: Playwright adds `--hide-scrollbars` in headless mode (playwright-core 1.64.1 `coreBundle.js:44762`), which sets `hide_scrollbars` (`web_contents_impl.cc:4169-4170`@f842f52) and removes the root scrollbars (`paint_layer_scrollable_area.cc:1765-1772`@f842f52), so `overlayOf` is true (INFERRED) | round 1 engaged; round 2 not installed (INFERRED) | engaged in both rounds (INFERRED) |
| Linux WebKit | not read | the lane walks hero only (`walks_linux_webkit`), no push, so the lock never engages (INFERRED) | same |
| macOS WebKit (macos-26) | unknown: not recorded | round 1 engaged iff overlay (unknown); round 2 not installed (`hasTouch`, INFERRED) | engaged iff overlay (unknown) |

Lean outcome lines (`Fw.Gate.Trajectory.outcome`). Reproduce them read-only from `lean/` after `gh run download <id> -D <dir>`
(the A/A has search `''`, which `storedOf` rejects, so `Stored` is built directly with flags `[]`; nothing is written):

```lean
import Fw.Preset.Gen
open Lean Fw.Preset.Gen Fw.Gate.Trajectory
def outcomes (dirs : List String) : IO Unit := do
  for d in dirs do
    let dir : System.FilePath := d
    let e ← IO.ofExcept (engineOfArtifact (dir.fileName.getD ""))
    let j ← readJson (dir / unitsName e)
    let us ← IO.ofExcept do (← (← j.getObjVal? "units").getArr?).toList.mapM parseUnit
    for w in [Walk.hero, .morph] do
      if us.any (·.walk == walkWord w) then
        let s : Stored := ⟨"", "", "", [], e, w, widthsOf (walkWord w) us, groupsOf (walkWord w) us⟩
        IO.println s!"{engineWord e} {walkWord w}: {outcomeWord (outcome s)}"
#eval outcomes ["<dir>/trajectory-chromium", "<dir>/trajectory-playwright-webkit", "<dir>/trajectory-apple"]
```

Saved as `<file>.lean`, run `lake env lean <file>.lean`. Round 1's runs are re-reduced with the current judge (envelope,
task trajectory-close-start) by copying each `raw-<engine>.json` to an empty directory per artifact and running
`node src/trajectory/cli.mjs summary --out <that dir>` in `packages/gate-breakpoints`.

ROUND2_CI

## Ledger row (for the lead)

`n` is left for the lead to assign.

```json
{
  "id": "morph.tween.scrollLock",
  "part": "morph.tween",
  "candidate": "morph.tween:scroll-lock (C4): hold the root at overflow: hidden while the morph is active, only where the primary input hovers and the scrollbar is an overlay one, instead of relying on the scrollTo pin alone",
  "status": "look-change",
  "flag": "morph.tween:scroll-lock",
  "chromium": "premise-holds",
  "webkit": "premise-holds on Mac (trackpad gesture in flight); premise-false on iPhone (pan in flight not stopped), where the arm is not installed",
  "visual": "look change (L) during a gated gesture in flight: the page no longer jumps one delta before the pin returns it, and the overlay scrollbar hides while the morph runs; the main-thread position and the layout width are the original's (lock_vis, gutter_same)",
  "mechanism": "CONFIRMED (source): root overflow hidden sets both scrollbar modes AlwaysOff (LocalFrameView.cpp:642-668@862f17d), so canHaveScrollbars() is false (ScrollingTreeScrollingNode.h:131@862f17d). On Mac canHandleWheelEvent then returns false (ScrollingTreeScrollingNode.cpp:233-236@862f17d), which stops a latched gesture and its momentum. On Chromium ScrollTree::ScrollBy zeroes a delta on an axis that is not user-scrollable (cc/trees/property_tree.cc:2471-2480@f842f52). On iPhone WKWebViewIOS.mm:1100-1104@862f17d clears allowedTouchTypes but keeps scrollEnabled, so a recognized pan and its deceleration continue (UIKit part INFERRED). Classic scrollbars: the lock would shift the layout by the scrollbar width without scrollbar-gutter: stable (layout_box.cc:1474-1494@f842f52, LocalFrameView.cpp:7322-7333@862f17d), so the arm locks only on overlay scrollbars. The arm reads the scrollbar kind once per activation, before its first style write, because clientWidth forces style and layout (element.cc:2622-2633@f842f52, Element.cpp:1632-1635@862f17d).",
  "leanFor": [
    "Fw.Parts.MorphTweenOpt.lock_vis", "Fw.Parts.MorphTweenOpt.seen_eq", "Fw.Parts.MorphTweenOpt.forced_le", "Fw.Parts.MorphTweenOpt.forced_lt", "Fw.Parts.MorphTweenOpt.shown_lock", "Fw.Parts.MorphTweenOpt.gutter_same", "Fw.Parts.MorphTweenOpt.runL_s", "Fw.Parts.MorphTweenOpt.runL_locked", "Fw.Parts.MorphTweenOpt.runR_eq", "Fw.Parts.MorphTweenOpt.reads_iff", "Fw.Parts.MorphTweenOpt.engage_on", "Fw.Parts.MorphTweenOpt.engage_touch", "Fw.Parts.MorphTweenOpt.engage_classic", "Fw.Parts.MorphTweenOpt.engage_off_writes", "Fw.Parts.MorphTweenOpt.classic_writes", "Fw.Parts.MorphTweenOpt.rootWrites_classic"
  ],
  "leanAgainst": [
    "Fw.Parts.MorphTweenOpt.ungated_eq", "Fw.Parts.MorphTweenOpt.forced_ungated", "Fw.Parts.MorphTweenOpt.still_eq", "Fw.Parts.MorphTweenOpt.forced_still", "Fw.Parts.MorphTweenOpt.style_passes", "Fw.Parts.MorphTweenOpt.gutter_shift"
  ],
  "missingWhy": [
    "the gain needs a gesture in flight; the trajectory probe pushes with one prevented wheel, so it cannot show it (still_eq, forced_still). MEASURED: see the CI section; no run shows a unit beyond the A/A floor outside close@0",
    "the work is two counters with no cited per-unit engine cost: scrollTo calls saved (forced_lt) against 2 root style passes added per morph (style_passes); the net cost is INFERRED and unmeasured",
    "iPhone: refuted (ungated_eq, forced_ungated); the arm is not installed on (hover: none) (engage_touch), which also excludes touch-only Android, where the gain is unchecked",
    "Gest.gated and the commit frame k are model inputs restated from the engine paths, not derived",
    "the probe does not record whether the lock engaged; the macOS runner's scrollbar kind is unknown, so mac engagement at 641 and 1280 is unknown"
  ],
  "premises": [],
  "v1Evidence": "none",
  "lesson": "overflow: hidden on the root stops only the scrolls that the async scroller gates. On iPhone a pan that UIKit already recognized does not stop, so a scroll lock helps only where the engine checks scrollability per event. A lock also changes the look and, on classic scrollbars, the layout width.",
  "next": "Out of v2-proved (look change, class L). A probe step with a trackpad gesture latched before the armed band (Mac, Chromium) would measure the scrollTo saving and should record whether the lock engaged. The user's visual review decides whether the look change is acceptable.",
  "evidence": "EVIDENCE_TBD"
}
```
