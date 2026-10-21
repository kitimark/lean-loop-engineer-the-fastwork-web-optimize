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

`driver.ts`: `pin()` runs on every scroll frame (`registerScroll`, order 110) and calls `scrollTo({top: pinned, behavior:
'instant'})` while `isActive()` (`target > 0.001 || value > 0.001`, the whole time the morph is open) and `scrollY ≠ pinned`.
The wheel and touchmove listeners prevent every push taken while active, so the fight comes only from a gesture latched to
async scrolling before the morph became active (lag-source note §Input).

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

- **Hover gate.** `scrollLockOf` in `index.tsx` installs `env.lock` only when `lockAllowed(hoverNoneOf(read))`, with
  `read` the `(hover: none)` match read once at mount (`mq.hover-none`), or `null` when `matchMedia` throws. An unreadable
  query counts as matching (Lean `hoverNoneOf`, `engage_unread`), so the arm keeps the original there, as it does on iOS
  (`engage_touch`, `engage_off_writes`); `scroll-lock.gate.test.ts` checks both cases. Touch-only
  Android is excluded with iOS, although `ScrollTree::ScrollBy` likely gates its pan (INFERRED): a possible gain given up.
- **One read per activation.** The driver reads `overlay()` (`innerWidth − documentElement.clientWidth ≤ 0`) only at the
  step that activates the morph (Lean `readsAt`), before that step's style writes, and `syncLock` uses the stored value
  (`stepR`, `runR_eq`). Ticks never read. Round 1 read it on every tick while unlocked, after the tick's style writes;
  `clientWidth` forces style and layout on a classic scrollbar (Blink `element.cc:2622-2633`@f842f52, WebKit
  `Element.cpp:1632-1635`@862f17d). The activating push comes through `takenFor`, whose `isArmed()`
  (`getBoundingClientRect`) has just flushed layout with no style write since, so the read finds layout clean (INFERRED).
- **Classic scrollbars.** The arm reads once per activation and writes nothing (`classic_writes`, `rootWrites_classic`).
- The pin stays as a backstop. TS: `scroll-lock.logic.ts`, `driver.ts` (`readOverlay`, `syncLock`), `index.tsx`.

Golden test `scroll-lock.golden.test.ts`: overlay and engage rows; 4 histories through the driver, checking per event the
activity, the root write and the `overlay()` call count (row `read`: 1 at the activating push, 0 per tick, `open-close` and
`open-close-classic` included), and that the read precedes the first style write; 4 spans through `pin()` (`scrollTo`
calls, stub `scrollY` = `p` after). Whether the engine drops a delta is the model input `Gest.gated`, fed to the stub.

## Lean (MT-L)

- `runL_s`, `runL_locked`: the arm's tween is the original's after every history; the root is locked iff overlay and active.
- `runR_eq`, `reads_iff`: the read-once driver equals `runL`; a step reads iff it activates the morph.
- `engage_touch`, `engage_classic`, `engage_on`, `engage_off_writes`: one theorem per branch of `engage`; where it is false
  the arm never writes the root.
- `engage_unread`, `engage_read_touch`: an unreadable or matching `(hover: none)` read never engages the lock.
- `seen_eq`, `span_seen`: on every frame the position the main thread sees after `pin()` is the pinned `p`, in both arms.
- Two work counters, not added together:
  - `scrollTo` calls (`forced`): `forced_le` (never more), `forced_lt` (strictly fewer once the lock is committed at frame
    `k` and one gated nonzero delta arrives), `forced_still` and `forced_ungated` (equal without a gesture or with ungated
    input). `shown_lock`: under a committed lock a gated frame shows `p`.
  - Root style passes (`stylePasses`, `rootWrites`): `style_passes`, `stylePasses true = stylePasses false + 2` per morph;
    the arm never saves one. `rootWrites` is 2 in each overlay golden history and 0 on classic (`rootWrites_classic`).
  - Round 1's `work_le` added the two as equal units with no cited per-unit cost; it is removed. The net is INFERRED.
- `gutter_same`: the layout width is the original's for every input and scrollbar kind. `lock_vis`: `VisSame E` for a
  scene of the tween, the seen position and the gutter, with the arm engaged by `engage` on the hover and scrollbar kind.

Regenerate the golden (from `lean/`; the copy drops the `include_str` guards, so it elaborates while the golden is stale):

```sh
S=$(mktemp -d) && grep -v include_str Fw/Parts/MorphTweenOpt.lean > "$S/Regen.lean" &&
  printf 'def main : IO Unit := IO.print Fw.Parts.MorphTweenOpt.lockJsonl\n' >> "$S/Regen.lean" &&
  lake env lean --run "$S/Regen.lean" > ../packages/contracts/golden/parts/morph-tween-scroll-lock.jsonl; rm -rf "$S"
```

Then `lake build` checks it through the `#guard ... include_str` line.

Model limits: `Gest.gated` and the commit frame `k` are inputs restated from the engine paths, not derived; `lock_vis`
covers the main-thread view only, and the original's shown position in a fight (`shown ≠ p`) makes the arm class L.

## Breakpoint gate: the new condition `mq.hover-none`

The arm adds `mq.hover-none` to `MEDIA_IDS` (`apps/site/src/parts/morph.tween/media.ts`). The gate's scope reads a part's
rewrite ids from `packages/gate-breakpoints/src/scope.gen.json`, which Lean writes from `pilotParts`
(`lean/Fw/Gate/Scope.lean:311`, emitted by `lean/Fw/Gate/ScopeGen.lean:40-41`, regenerated with
`node packages/gate-breakpoints/scripts/scopegen.mjs`). The original's `morph.tween` does not read `(hover: none)`: the
inventory (`research/kickoff/11-breakpoints/breakpoints.json`, `mq.hover-none`) lists it only for `ui.shared(sb-*)`, and that
file stays unchanged. So the scope has a new field `added` (`Scope.lean:235`): catalogue ids that only the rewrite reads, each with a
reason. `pilot_added_exact` (`Scope.lean:448`) proves that each part's `added` ids are exactly its rewrite ids outside
`orig`. `scope.test.mjs` checks the same thing on the JSON, where it used to require rewrite ⊆ orig. CONFIRMED (local
`node --test test/*.test.mjs`, 425 pass; the land lane's `fw checks --tier remote --leg suites-a` passes locally).

- **Both states are scoped.** The key now holds `(hover: none)`, so the morph.tween scope gains `touch-319`,
  `touch-rm-600`, `touch-rm-860` and `touch-rm-1201`. `scope_hover_none_both` (`Scope.lean:623`) proves that on every port
  the scope has a reachable load where `(hover: none)` matches and one where it does not; `scope_covers` still proves that
  every reachable key class is in the scope.
- **Lanes that emulate `(hover: none)`.** Chromium starts one browser per (hover, pointer) pair with
  `--blink-settings=primaryHoverType=…` (`packages/gate-breakpoints/src/engines.mjs:91-100`). WebKit uses
  `hasTouch: env.hover === 'none'` (`engines.mjs:160`), which sets both `(hover: none)` and `(pointer: coarse)`; the cross pairs are
  unreachable there (`engines.mjs:32-36`, Lean `envReason`). The matrix runs the TOUCH and PHONE environments with no hover
  (`src/spec.mjs:75-76`) and the `hover-pointer-cross` block (`lean/Fw/Site/BreakpointMatrix.lean:92`; both values of
  each hover query, `matrix_neutral_hover_both_sides` :291). The trajectory lane loads 390 and 640 as TOUCH (no hover) and
  641 and 1280 as DESK (`src/trajectory/registry.mjs:93-95`). The gate runs the arm only when `FW_SEARCH` names it
  (`?fw=morph.tween:scroll-lock`, `src/serve.mjs:41-48`).
- **Why the off state is the original.** Under `(hover: none)` (or an unreadable query), `scrollLockOf` returns no lock
  (`apps/site/src/parts/morph.tween/index.tsx:70-74`, Lean `hoverNoneOf`, `engage_unread` and `engage_read_touch`,
  `MorphTweenOpt.lean:2241-2247`). With no lock, `readOverlay` and `syncLock` return before any read or write
  (`driver.ts:58-62`), so the arm runs the original tween with no root write (`engage_touch` :2230, `engage_off_writes`
  :2250). Under `(hover: hover)` the lock writes the root only while the morph is active (`lockWrite`, `driver.ts:63`;
  `runL_locked` :2124). INFERRED (no Lean link from the gate load position to an inactive morph): the gate loads at the top of the page, where the morph is inactive (`js.morph-arm` is dismissed at
  `Scope.lean:316`), so neither hover state writes the root at a gate load, and the gate's equality claim covers both.
  The look change while a gesture is in flight (class L) is outside the gate.

## Known limits

- No rubber-band and no keyboard or scrollbar-drag scrolling while locked (the original pins those back anyway).
- The drawer writes `body.style.overflow` (`overlays.drawer/index.tsx:78-81`); a drawer opened during the morph makes the body
  its own scroll container. No sticky element is on screen at the page end (INFERRED).
- `(hover: none)` is read once at mount; a device whose primary input changes later keeps the first decision.

## CI (trajectory probe)

Whether the lock engaged is not recorded by the probe; per lane it follows from the lane's input and scrollbar kind
(widths 390 and 640 load `(hover: none)`, 641 and 1280 `(hover: hover)`, `packages/gate-breakpoints/src/trajectory/registry.mjs:93-95`):

| lane | scrollbar kind | 390, 640 | 641, 1280 |
|---|---|---|---|
| Chromium (headless, Linux) | none drawn, so `overlayOf` is true (INFERRED, below) | round 1 engaged; round 2 not installed (INFERRED) | engaged in both rounds (INFERRED) |
| Linux WebKit | not read | the lane walks hero only (`walks_linux_webkit`), no push, so the lock never engages (INFERRED) | same |
| macOS WebKit (macos-26) | unknown: not recorded | round 1 engaged iff overlay (unknown); round 2 not installed (`hasTouch`, INFERRED) | engaged iff overlay (unknown) |

Chromium lane: Playwright adds `--hide-scrollbars` in headless mode (playwright-core 1.64.1 `coreBundle.js:44762`), which
sets `hide_scrollbars` (`web_contents_impl.cc:4169-4170`@f842f52), and the root then creates no scrollbars
(`paint_layer_scrollable_area.cc:1765-1772`@f842f52). On a classic macOS runner round 1 also read `clientWidth` per tick.

Lean outcome lines (`Fw.Gate.Trajectory.outcome`): after `gh run download <id> -D <dir>`, save this as `<file>.lean` and
run `lake env lean <file>.lean` in `lean/` (read-only; the A/A's search `''` fails `storedOf`, so `Stored` is built here):

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

Round 1's runs are re-reduced with the current judge (envelope): copy each `raw-<engine>.json` to an empty directory
per artifact, run `node src/trajectory/cli.mjs summary --out <that dir>` in `packages/gate-breakpoints`.

Outcome lines (MEASURED; every artifact's `search` checked: flag runs `?fw=morph.tween:scroll-lock`, A/A runs `''`):

| run | sha | arm | chromium hero, morph | linux-webkit hero | mac-webkit hero | mac-webkit morph |
|---|---|---|---|---|---|---|
| 39496271199, 39498373119 | e01287a | flag | pass, pass | pass | pass | no verdict: coverage |
| 39500347224 | e01287a | A/A | pass, pass | pass | pass | no verdict: coverage (fail under the round-1 judge) |
| 39505188144 | b4b8b37 | flag | pass, pass | pass | pass | fail |
| 39505203727 | b4b8b37 | A/A | pass, pass | pass | pass | fail |

New content units in round 2 (`rel: new`, not coverage):

- A/A: mac 390 `earn.max-width` and `nav.background-color` at close@0, 641 `earn.max-width` at close@0. Its fail is the
  repeat of `earn.max-width` at close@0 across 390 and 641: the floor of the original against itself.
- Flag: Chromium 1280 `nav.background-color` at close@0 and close-hold@0, `nav.rect` at close@0. Mac 390
  `nav.background-color` and 640 `earn.max-width` at close@0, 641 `earn.max-width` at open@10, 1280 `nav.background-color`
  at a0-a2 and close@0, `logo.color` and `nav.cls.is-on-dark` at a0. Its fail is the repeats of `nav.background-color`
  (390, 1280) and `earn.max-width` (640, 641).
- At 390 and 640 the arm is not installed; approach steps precede the first activation, where the arm writes nothing.
  close@0 and approach reads are the in-flight class of `docs/team/tools/trajectory-probe.md` (Transitions in flight).
  Outside them two units remain, each at one width in one run (Chromium 1280 `nav.background-color` at close-hold@0, mac
  641 `earn.max-width` at open@10); neither repeats.
- The flag run's 640/641 `earn.max-width` repeat pairs a close@0 read (640) with an open@10 read (641); excluding the
  in-flight close@0 reads leaves no repeating group.

## Ledger row (for the lead)

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
    "the gain needs a gesture in flight; the trajectory probe pushes with one prevented wheel, so it cannot show it (still_eq, forced_still). MEASURED: no unit repeats beyond the A/A floor outside close@0 and approach steps in either round; at b4b8b37 mac morph fails in both the flag run and the A/A on close@0 repeats",
    "the work is two counters with no cited per-unit engine cost: scrollTo calls saved (forced_lt) against 2 root style passes added per morph (style_passes); the net cost is INFERRED and unmeasured",
    "iPhone: refuted (ungated_eq, forced_ungated); the arm is not installed on (hover: none) (engage_touch), which also excludes touch-only Android, where the gain is unchecked",
    "Gest.gated and the commit frame k are model inputs restated from the engine paths, not derived",
    "the probe does not record whether the lock engaged; the macOS runner's scrollbar kind is unknown, so mac engagement at 641 and 1280 is unknown"
  ],
  "premises": [],
  "v1Evidence": "none",
  "lesson": "overflow: hidden on the root stops only the scrolls that the async scroller gates. On iPhone a pan that UIKit already recognized does not stop, so a scroll lock helps only where the engine checks scrollability per event. A lock also changes the look and, on classic scrollbars, the layout width.",
  "next": "Out of v2-proved (look change, class L). A probe step with a trackpad gesture latched before the armed band (Mac, Chromium) would measure the scrollTo saving and should record whether the lock engaged. The user's visual review decides whether the look change is acceptable.",
  "evidence": "trajectory-probe runs 39496271199, 39498373119 (flag) and 39500347224 (A/A) at e01287a; 39505188144 (flag) and 39505203727 (A/A) at b4b8b37; ci/morph-scroll-lock, both engines; note research/notes/2026/10-21-morph-scroll-lock.md"
}
```
