---
id: 2026-10-25-hero-exit-q6
kind: note
title: "hero.exit:threaded q6: which scroll offset each arm shows, and whether the 25/40/40 new units are an offset difference"
status: draft
created: 2026-10-25
topics: [hero.exit, scroll-driven, trajectory-probe, webkit, chromium, v2-proved]
---

# hero.exit:threaded q6: same scroll offset

## Answer

- **The threaded arm is never older than the original, except in one frame kind.** That kind is a WebKit frame on
  the main-thread path in which script scrolls after the animation update. Lean `threaded_never_older` and
  `threaded_older_iff` (lean/Fw/Parts/HeroExitScrollOffset.lean). CONFIRMED from engine source (table below). Whether the
  site ever produces that frame is INFERRED: no: neither arm scrolls from a rAF callback, and the probe scrolls from
  `page.evaluate`, outside the rendering update.
- **On the first frame after a scroll change, the threaded arm is strictly newer** on the accelerated path
  (`accelerated_first_newer`). The original's scroll event only requests a rAF, its hero callback requests another one,
  and the body that reads the offset runs a frame later (snapshot `2.DyWL8TcE.js` 2667-2669, 4155-4175, 4239, as cited
  in lean/Fw/Parts/EngineScroll.lean). CONFIRMED.
- **At a probe rest row, both arms show the same offset** when the offset has been still for the probe's 8 frames and
  both ages fit in that window (`arms_equal_at_rest`, `stillFrames` = 8 from kit.mjs:206). Whether ages fit in 8 frames
  is INFERRED: `lag + since + 1 ≤ 8` is a hypothesis.
- **Unequal offsets do not explain the 25/40/40 new units of run 40156078840.** MEASURED: all 105 units are on rest rows
  where the original's `scrollY`, the candidate's `scrollY` and the step target are equal. Every unit is on a node with an
  empty rect in both arms. Lean `measured_judgedEqual` and `measured_hidden` hold over the table `measured`, and the
  golden `hero-exit-offset.jsonl` replays them. The answer is a named counterexample, not an offset theorem. The cause
  is `hidden` (a consumer in a `display: none` subtree), not `offset`.
- **The probe can compare at unequal offsets, but did not here.** The reducer judges every rest row
  (reduce.mjs:643,656-657) and does not check `y` against `target`. A rest that stays short after the two instant retries
  (kit.mjs:255-262) would be judged anyway (`judgedNow_unequal`). The Lean decision `judgedEqual` (rest and equal
  `scrollY`) is the probe change. It is a follow-up and not made here.
- **Gen.entry now says:** `not yet`, blockers `proofs`, `gate chromium`, `gate webkit`. `q6` and `look` are met.
  `proofs`: `hero.exit:threaded` now links to ledger row n 6, which is `partly-proved`. `threaded_proofs_iff` makes the
  requirement met exactly when that row is proved and not falsified. CONFIRMED
  (packages/contracts/golden/preset/v2-proved.decisions.jsonl, `Gen.run`).

## Per-frame model (Lean `threadedAge`, `origAge`)

`lag` is how many frames the main-thread offset trails the drawn one. Age is how many frames the shown offset trails
the offset drawn in that frame.

| path / frame kind | first after change | steady | in-frame script scroll |
|---|---|---|---|
| threaded, accelerated (both engines) | 0 | 0 | 0 |
| threaded, Chromium main thread | lag | lag | lag |
| threaded, WebKit main thread | lag | lag | lag + 1 |
| original (rAF writer) | lag + since | lag | lag |

## Engine source (CONFIRMED)

| claim | source |
|---|---|
| WebKit UI process updates progress timelines on every scrolling-tree scroll | Source/WebKit/UIProcess/RemoteLayerTree/ios/RemoteScrollingTreeIOS.cpp:56-64@862f17d; RemoteScrollingTree.cpp:345-350; RemoteProgressBasedTimelineRegistry.cpp:149-161 |
| the UI-process timeline reads the node's own offset | RemoteProgressBasedTimeline.cpp:61-75@862f17d |
| WebKit main-thread view timeline is cached at the animation update and read from that cache | Source/WebCore/animation/ViewTimeline.cpp:296-329, 444-450, 503-518@862f17d |
| after rAF and style, the stale check re-resolves animations only when the maximum scroll offset changed | Source/WebCore/animation/ScrollTimeline.cpp:300-327@862f17d (:312-315) |
| threaded animations are Cocoa only, so Linux WebKit runs the main-thread path | Source/WTF/wtf/PlatformEnableCocoa.h:904-905; PlatformEnable.h:566-567@862f17d |
| Chromium compositor timeline reads the scroll tree's offset, ticked right after a scroll update | cc/animation/scroll_timeline.cc:85-131, 175-193; cc/input/input_handler.cc:512-513@f842f52 |
| Chromium falls back to the main-committed offset when a delta cannot be realized | cc/trees/property_tree.cc:2067-2083@f842f52 |
| Blink main-thread snapshot at frame start, validated after layout | third_party/blink/renderer/core/frame/local_frame.cc:4410-4425; core/animation/scroll_snapshot_timeline.cc:211-290@f842f52 |
| CSS animations are cancelled in a `display: none` subtree | Source/WebCore/style/Styleable.cpp:392-402@862f17d; third_party/blink/renderer/core/animation/css/css_animations.cc:1943-1950@f842f52 |

## Run 40156078840 (at fbca417), hero path (MEASURED)

| lane | new units | widths × node.prop | steps | equal offsets | painted elements (orig/cand) |
|---|---|---|---|---|---|
| Chromium | 25 | 390 orbit.card opacity+translate; 640, 641, 1280 deck.card opacity | s25 s50 s90 b25 b0 | 25/25 | 0/0 |
| Linux WebKit | 40 | same 5 cells | s25 s50 s90 s200 mid hold b50 b25 | 40/40 | 0/0 |
| macOS WebKit | 40 | same 5 cells | same 8 steps | 40/40 | 0/0 |

- 120/120 rest rows (3 lanes, 4 widths, 10 steps) have the same `scrollY` in all three arms, equal to the target. MEASURED.
- At the failing steps, each card element that paints a box has the same opacity in all three arms (60/60). Only the
  elements with an empty rect differ (60). MEASURED.
- Move rows differ in `scrollY` only on Linux WebKit (8, 6, 15 and 17 tags at 390, 640, 641, 1280). The hero path does
  not judge move rows. MEASURED.
- Hidden nodes: `.orbit` is `display: none` at width ≤ 600 (apps/site/src/parts/hero.orbit/orbit.module.css:56-60).
  `.deck` is `display: none` except at ≤ 600 (apps/site/src/parts/hero.deck/deck.module.css:8-16). CONFIRMED.
- Cause of the difference: the original keeps writing the inherited `--exit-opacity`, so the computed value of an
  unpainted box changes. The candidate's animations are cancelled there, so its value stays at the last one before the
  box left rendering. INFERRED (values 1.000 and 0.825 against the original's 0.913 at 390 s25).

## Open

- The probe change `judgedEqual`: skip a rest row whose arms read different `scrollY`. Lean decision written; the reducer
  is not changed here.
- The gate blockers stay until a probe re-run. The hidden-consumer units need the lead's rule ("a node that paints no
  box is not a consumer", proposed in 10-2x-hero-exit-threaded.md) or a probe that skips such nodes.
- `proofs`: ledger row n 6 stays `partly-proved` (missingWhy: R2 inherited fan-out units, WebKit edge-frame cost).
  `RG11` stays a hypothesis of `consumer_eq_s`.
