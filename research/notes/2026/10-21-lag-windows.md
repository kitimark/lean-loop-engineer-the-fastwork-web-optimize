---
id: 2026-10-21-lag-windows
kind: note
title: "The two windows the user feels as laggy: hero to people, and the end of the page"
status: final
created: 2026-10-21
authors: [agent:researcher, agent:reviewer, lead]
topics: [lag, hero.exit, people.card, morph, platform, webkit, chromium, smoothness]
---

# The two lag windows (2026-10-21)

User: the hero-to-people transition (hero card moves out, people section fades in) and the end of the page feel laggy in
the original. Workflow lag-windows (researcher per window, reviewer check per window); this note keeps the corrected
findings. Ledger rows are named by `id`/`part`, not by index.

## Hero to people
- Range: hero exit runs over one viewport (track 200vh, exitRange = vh, `apps/site/src/parts/hero.exit/logic.ts`); the
  people card reveals at scrollY 0.72 vh (`people.card/logic.ts` REVEAL_AT); its blur tail (1.6 s) runs on time. CONFIRMED.
- Not optimized: every v2-proved decision row for this window has member=false (`v2-proved.decisions.jsonl`). CONFIRMED.
- Chromium (swipe-touch-v1, BeginFrameControl): before the reveal about 3.9 UpdateLayoutTree and 138 elements per frame
  (y00000, original/faithful 204/205 ULT, 7187/6818 elements, run 39253177864). The reveal is one spike frame (n80, y675:
  Raster 21, invalidation 5.05M px). From y929 to y1179 raster rises with image decodes; from y1279 to y1479, while the blur
  still runs, invalidation is 25-26k px per 5 frames with 0 decodes: the blur adds no measurable Chromium invalidation.
  MEASURED (run 39050423094 store). So the images, not the blur, are the Chromium cost after the reveal (INFERRED from it).
- WebKit Simulator (430x775, run 39511908073): region A, original Layout 179,323 us and FunctionCall 152,789 us per step,
  faithful 6,472 and 26,438; Composite 105,495 / 116,864. MEASURED. The CA render-server blur cost is invisible to the
  Simulator counters; v1 phone data: frame 2 after the reveal 74 ms with the CA blur, 42 ms off CA (v1, MEASURED there).
- Images: people as shipped decode to 51.8 MiB (WebKit) / 46.3 MiB (Chromium) at 430 (10-20-image-audit.md). MEASURED.

## End of page
- WebKit morph pushes: the per-frame `--morph-fade` write (`morph.tween/driver.ts` updateFade :68-73) forces style, a
  filter-outset change and a repaint of the platform backing (83% of the close-push paint area) and the panel (26% of the
  faithful open-push paint area) (10-21-webkit-lag-probe.md). MEASURED shares; mechanism CONFIRMED from source.
- Chromium swipe-touch tail: Layout 1.0 per frame in both arms, Layout.totalObjects 718 (original) vs 1554 (rewrite);
  invalidation identical (1,118,511 px/frame). MEASURED (runs 39050423094 / 39184646781).

## Ranked next candidates
1. Unblock the macOS WebKit morph trajectory cell (mac-webkit FAIL 39453181962 and coverage no-verdicts): it blocks
   hero.exit:scoped (inline candidate, -19.2% style elements on the swipe, runs 39461009752/39462188464), people.card:mq,
   morph.countdown:hidden-pause (win/win) and morph.mount:shift (trade). Path: close-start-identity-rule (accepted
   2026-10-21) then close-start-later-samples. Look E.
2. People images at drawn size (decode and raster after the reveal). Look E if the drawn pixels match.
3. people.card pre-paint g0.0m (ledger, touch only; trade, about +22 MB; CI WebKit Paint is stable only as a total, so
   the move is not visible there).
4. Platform and panel fade as real-property animations: largely the proved trade "own layer during the blur fade"
   (about 13 MB layer per tween; RenderLayerCompositor.cpp:3842-3867@862f17d). Look E.
5. people.card blur tail cut or instant reveal: look change (L), the user's review.
6. Nav morph via transform scale + clip instead of top/width/height (C1b): look change (L).
Not ranked here, already in the graph: filter:none at rest (panel-rest tasks), the earn transition (nav:earn-no-transition).
Corrections from the checks: hero.exit scroll-driven real properties are a trade under WktrStyleRate.Holds
(HeroExitOpt.lean wk_trade), not a main-thread removal; hero:scene-pause evidence belongs to the end of the page.

## Missing
No frame-time or smoothness metric exists for the rewrite: the Chromium lane uses virtual time and WebKit RenderingFrame
is 0 on the iOS 27 Simulator (CONFIRMED). Tasks smoothness-probe (motion continuity + real-time cadence lane) and
device-lag-recorder (the user's own scroll on the phone, replayed on CI) measure it.
