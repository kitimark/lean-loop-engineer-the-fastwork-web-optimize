# Do the end-of-page column pictures cause the phone lag? Probe on the real iPhone (n = 4 per arm)

Question (from `research/notes/2026/10-27-end-columns-probe.md`): does painting the 21 pictures of morph.columns cause the WebKit lag at the end of
the page, with and without the morph.geom flip? Same real iPhone (WebKit), same fixed XCUITest push pattern as `phone-morph-push-r2`, end segment,
one induced thermal state (Serious). Every number below is in `results/phone/2026-10-27-cols-probe/{summary.json,tables.md}` (raw lanes in
`.local/phone/2026-10-27-cols/`, gitignored, not copied).

## Answer (MEASURED, 2026-10-27)
- Undecided for both contrasts. Hiding the pictures does not move any of the 8 metrics beyond the reference spread: base vs base+off and
  flip vs flip+off are `same` in every column, cause `overlap` (the two ranges overlap, so the Lean rule cannot call a direction).
- The base spread is wide: max 78 to 297 ms (spread 219 ms), paint 9600 to 13104 (spread 3504). A difference smaller than that cannot show at n = 4.
- The paint count does not fall when the pictures are hidden (base 12716, base+off 11751; flip 4700, flip+off 4703). The frame metrics
  (p95, p99, frames over 50 ms) do not fall either (table below).
- The flip arms were taken on every push: 40 of 40 pushes in each lane, so the flip arms measure the flip and not a fall-back.

## The probe (CONFIRMED in code, premise from source)
`morph.columns:probe-off` (kind `probe`, never in a preset; `apps/site/src/parts/morph.columns/{part.json,morph.module.css}`,
`apps/site/src/registry/probes.test.ts`, golden `packages/contracts/golden/preset/probes.jsonl`) sets `visibility: hidden` on the pictures.
Layout and the track layers with their animations stay.
- WebKit@862f17d: a replaced element does not paint when `style().usedVisibility() != Visible` (`Source/WebCore/rendering/RenderReplaced.cpp:411`,
  reached from `RenderReplaced::paint` at `:267`); the layer's `hasVisibleContent` follows `usedVisibility()` (`RenderLayer.cpp:401`) and feeds
  `setContentsVisible` on its graphics layer (`RenderLayerBacking.cpp:1918`). Backing store is allocated by `containsPaintedContent`
  (`RenderLayerBacking.cpp:2142`), so a track layer with only hidden pictures may lose its backing (INFERRED; not checked on the phone). The probe
  therefore removes the pictures' paint and raster and possibly the track layers' backing, nothing in layout.
- chromium@f842f52: `ReplacedPainter` returns early when `style.Visibility() != EVisibility::kVisible`
  (`third_party/blink/renderer/core/paint/replaced_painter.cc:423`). Whether `visibility: hidden` also skips image decode
  is not checked here (the painters above only gate painting); the probe is read as "no picture paint", not "no decode".

## Session (MEASURED)
16 visits, 4 per arm, in the Latin order of the Lean `PhoneArms` columns section (`colsOrder`; each arm takes each position once), all `done`,
none lost. Cells are the upper median (3rd of 4 sorted values) [min-max]; frame intervals in ms; counts are Timeline records between each push and
its morph end, summed over the 10 pushes of a visit. Label = Lean `pushLabel` against base.

| arm | n | p95 | p99 | max | frames over 50 ms | style | layout | paint | rAF | label |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 4 | 61 [55-67] | 98 [67-105] | 127 [78-297] | 47 [38-60] | 1249 [1057-1265] | 1047 [888-1069] | 12716 [9600-13104] | 264 [194-275] | base |
| base + probe-off | 4 | 67 [52-77] | 84 [64-98] | 382 [83-734] | 52 [32-57] | 1222 [976-1275] | 1021 [852-1072] | 11751 [10355-13053] | 259 [181-290] | same |
| flip (geom + geom-timed) | 4 | 70 [68-88] | 106 [99-124] | 119 [115-151] | 54 [51-87] | 1143 [993-1180] | 890 [797-909] | 4700 [4211-4724] | 121 [95-139] | better |
| flip + probe-off | 4 | 67 [63-73] | 127 [83-134] | 202 [97-324] | 53 [44-56] | 1144 [866-1207] | 898 [733-927] | 4703 [3805-4713] | 109 [30-136] | better |

- The `better` label of both flip arms rests on one cell, paint (the Lean cell verdicts are `same` for the other seven, and `beats` for paint).
  The flip lowers the paint records to 37 percent of base but does not lower p95, p99 or frames over 50 ms in this session.
- Two max values stand out: 734 ms (one base+off visit) and 324 ms (one flip+off visit). Single visits, not repeated in the same arm.

### The two contrasts (Lean `pushLabel`, arm with pictures hidden against its reference)
| reference | arm | n | label | every metric | reference spread (p95 / p99 / max / over50 / paint) |
|---|---|---|---|---|---|
| base | base + probe-off | 4/4 | same | same, cause overlap | 12 ms / 38 ms / 219 ms / 22 / 3504 |
| flip | flip + probe-off | 4/4 | same | same, cause overlap | 20 ms / 25 ms / 36 ms / 36 / 513 |

Per the pinned unit of decision both contrasts are undecided, not "no effect": the ranges overlap and, for base, the spread is wide. The
flip reference spread is narrower for paint (513) and the +off arm still sits inside it (4703 against 4700), so for paint the flip contrast says the
pictures add no paint records in the flip look (MEASURED for this count only).

### Take share (driver trace `window.__fwTakeTrace`)
| arm | visits | frames lane: driver pushes / taken | counts lane: driver pushes / taken | touches with a take |
|---|---|---|---|---|
| base | 4 | no trace | no trace | 0 of 40 |
| base + probe-off | 4 | no trace | no trace | 0 of 40 |
| flip | 4 | 40 / 40 | 40 / 40 | 40 of 40 |
| flip + probe-off | 4 | 40 / 40 | 40 / 40 | 40 of 40 |

The non-flip arms install no tween driver, so they have no trace (expected, not a miss).

## Thermal and checks (MEASURED)
- Pin: before Fair (14:47:25 UTC), not Nominal, because the first attempt (below) had warmed the phone; 36 readings (block starts, between lanes,
  visit ends) all Serious, Lean gate `go`, lock `unlocked` throughout. After: Critical (15:28:58 UTC), our condition owner cleared and the phone
  reported Critical from its own heat (`end heatRemains`). Battery temperature reads 0 on this phone (proxy unavailable), so no rise gate applied.
- All 16 visits navigated and reached morph 1000 per mille (`maxMorph`); each arm took each of the 4 positions once (`positions.byPosition`, tables "by position" and "by round" in `tables.md`).
- First start of the session failed before any visit: xcodebuild reported `Timed out while enabling automation mode` after 60 s (raw kept in
  `.local/phone/2026-10-27-cols/failed1/`). The same command a minute later started and ran 16 visits. Cause not found; the phone read `passcodeRequired: false` afterwards (INFERRED transient on the phone side).

## Limits (accepted)
- The probe arm hides pictures and is never a preset or a look verdict; the flip look lacks the veil and the object-fit image model.
- The push is a fixed XCUITest swipe, one thermal state (Serious), n = 4 per arm, no CI run; the phone reached Critical after the session.
- Numbers are comparable only inside this run (r2 base p95 69, paint 10398; here p95 61, paint 12716).
- TS stand-ins: the touch-to-take mapping (`traceOf`) in `packages/measure-webkit/src/device-push-run.mjs`; the push counts of the trace twin the Lean `takenOf`/`pushesOf`.

## Follow-ups (below the unit of decision)
- A larger n, or a hot-start order that lowers the base spread, to decide the base contrast.
- A probe that keeps the pictures painted but without decode (`content-visibility`, `opacity: 0` on the track) to separate decode from paint.
