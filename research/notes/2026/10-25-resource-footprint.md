# Resource footprint per flag: what each flag costs and saves, per engine

Question: for each of nine flags, which resources does it raise or lower on Chromium and on WebKit, as predicted from
the engine stage rules and part modules? Does today's phone and CI data agree? And which flags win once repaint
area and GPU memory are counted? Model: `lean/Fw/Engine/Resource.lean`, `ResourceVerdict.lean`, `ResourceFlags.lean`.
Golden: `packages/contracts/golden/engine/resource.jsonl` (180 predict rows, 83 check rows). Checker:
`packages/measure-webkit/src/resource-check.mjs`. Tags: CONFIRMED, INFERRED, MEASURED.

## Answer

| flag | Chromium | WebKit | ledger before (Cr / Wk) |
|---|---|---|---|
| hero.exit:threaded | trade | trade | trade / trade |
| hero:scene-pause | open | win | trade / win |
| morph.columns:idle-none | open | open | win / win |
| morph.countdown:hidden-pause | win | win | win / win |
| morph.countdown:strip | open | win | trade / trade |
| morph.panel:rest | trade | open | trade / win |
| nav:logo-3d | open | open | unknown / unknown |
| morph.mount:shift-dormant | neutral | neutral | trade / unknown |
| engine.events:quiet | open | win | no-win / win |

- The trade row that becomes a win (`becomesWin`): morph.countdown:strip on WebKit.
- Wins that become open (`leavesWin`): morph.columns:idle-none on both engines (event dispatch, paint and script
  unknown) and morph.panel:rest on WebKit (repaint unknown). The panel-rest-n11 task measures that flag on CI.
- Preset decisions are unchanged.

## Verdict rule (`verdict`, proved in `ResourceVerdict.lean`)

- Gated resources: style, layout, paint records, script, event dispatch, repaint area and frames requested. Layers,
  composite and GPU memory are census only.
- **trade**: any gated resource rises (`trade_iff`).
- **open**: no gated rise, but some gated sign is unknown (`open_of_unknown`).
- **neutral**: every gated sign is the same.
- **win**: no gated rise, at least one gated fall, and GPU memory falls, stays the same, or rises to a peak within B
  (`win_iff`).
- **overBudget**: the same, but the peak is past B (`over_budget_not_win`).
- A memory-only cost is never a trade (`memory_only_not_trade`). A rise within B still wins (`memory_cost_win`). A
  larger B keeps every win (`win_mono_budget`).
- B = 210 MiB (INFERRED, see `10-25-webkit-ios-gpu-memory.md`).

## Repaint area

- Repaint area is CSS px² × DPR² × frames (`repaintPx`), counted on the layer that paints.
- A change on an element without its own backing repaints its host layer's dirty rect: at least the element's own
  area, at most the host's area (`pushed_repaint`, from `display_bounds`).
- A composited element that only moves repaints nothing (`changePx` own = 0). A promoted tween pays one re-attach
  paint per promotion (`tween_repaint`, from `promote_tween`). A strip that never re-attaches pays none
  (`strip_no_reattach`).
- Predict rows give repaint in CSS px² x DPR² summed over a run. No footprint derives its repaint sign from
  `repaintPx` or `changePx` yet (follow-up: logo-3d, strip and panel:rest at DPR 3).
- Unit (CONFIRMED): WebKit Timeline paint quads are in root-view CSS px², and nested paints are dropped
  (`WebCore/inspector/agents/page/PageTimelineAgent.cpp:293-305`, `inspector/TimelineRecordFactory.cpp:152-170`,
  `inspector/agents/InspectorTimelineAgent.cpp:629-631@862f17d`). The phone's measured repaint area is this sum, so
  it compares to the model at DPR 1.

## Predicted vs measured (`obsCheck`)

| check | rows |
|---|---|
| agree | 43 |
| unresolved (predicted a move, measured same) | 5 |
| confounded (slow walk, non-census) | 24 |
| disagree | 5 |
| unpredicted (predicted unknown) | 6 |

- A walk is slow when the arm's lowest wall time is over 1.5 × the base's highest (`slowWalk`). Then only layers and
  GPU memory are judged, since a slower walk crosses more frames. The scene-pause, hidden-pause and logo-3d phone
  arms are slow.
- Measured sign (`measuredSign`): down when the arm's highest value plus the tolerance is below the base's lowest, up
  the other way round, otherwise same.

| flag, engine, resource | measured | mechanism |
|---|---|---|
| threaded, WebKit, paint records | up (unpredicted) | INFERRED: re-attach paints of the promoted animation targets (`promote_tween`) outweigh the per-frame paint drop |
| threaded, WebKit, repaint area | same (unpredicted) | INFERRED: the re-attach area is a small share of the walk's paint area, inside the pass spread |
| shift-dormant, WebKit, event dispatch | up | INFERRED: the early-mounted panel's transitions reach the React root listeners (`records_orig`) |
| shift-dormant, WebKit, script | up | INFERRED: the same root listener calls as the event-dispatch rise |
| shift-dormant, Chromium, layout | down | MEASURED (runs 39325709978 vs 39325721909): the early mount merges into a frame that already lays out; the shift model keeps totals equal |
| shift-dormant, Chromium, style | up | MEASURED (same runs): about 200 more resolved elements while the dormant panel is mounted; the model has no dormant restyle |
| events:quiet, WebKit, layers | up | open: one more layer at y=4500 in all three passes |
| idle-none, WebKit, paint records and repaint area | same (unpredicted) | open: the host's paint of the dropped track layers is not modelled |
| idle-none, WebKit, script | same (unpredicted) | open: the flag's MutationObserver callbacks are not modelled |
| idle-none, WebKit, event dispatch | same (unpredicted) | open: the animationcancel and animationstart of the re-created tracks are not counted |

Phone data: the seven finished arms of results/phone/2026-10-25-end-counts (MEASURED). Only the per-pass ranges
are in the golden; the raw passes stay local. Every check row carries its unit: phone layers and GPU memory are
sums over the three census states y >= 3000 (3000, 4500, max), e.g. 116,385,244 + 191,681,597 + 109,230,592 bytes =
407,517 KiB. CI data: the run ids in each check row's `source` field.

## Per-flag footprints (signs as in the golden)

- **hero.exit:threaded.** Chromium (`HeroExitOpt.crFrames`): script, repaint and frames fall; style rises (`cr_lane_mixed`)
  and event dispatch rises (two React root records per animation event), so it is a trade. WebKit
  (`wkFrames`): main-thread stages fall, event dispatch rises (trade). The re-attach makes paint and repaint unknown
  (`combine_opposite`).
- **hero:scene-pause.** The hero's layers drop (`heroLayers_drop`). Chromium: pausing changes no main-thread stage
  in real Chrome (`cr_realChrome_pause_eq`); the CI lane's style drop (`cr_pause_style_units`) is a lane artefact and
  is not counted. No Chromium source line was read for the iteration events of a paused animation, so event dispatch
  is unknown and the verdict open. WebKit: no web-process stage changes (`wk_pause_eq`), and a paused animation
  enqueues no animationiteration (INFERRED, `StyleOriginatedAnimation.cpp:340-345@862f17d`), a win.
- **morph.columns:idle-none.** The marquee track layers drop (`tracks_layers_drop`), and so do composite and GPU
  memory. Iteration events are equal, since the base already holds the tracks paused under the scene rule. But
  `animation-name: none` (morph.module.css:14-16) cancels the tracks and re-creates them on return, and each new
  animation enqueues animationstart (WebKit `StyleOriginatedAnimation.cpp:333-334,353-354@862f17d`, Chromium
  `css_animations.cc:3660-3666@f842f52`). The walk does not fix that count, so event dispatch is unknown (INFERRED).
  Paint, repaint and the flag's MutationObserver script are unknown too: open on both engines.
- **morph.countdown:hidden-pause.** The flag gates only the countdown's face writes (morph.countdown/index.tsx:59-64),
  so the model uses only the countdown frame pairs (`hiddenCrPairs`, `hiddenWkPairs`). Style and repaint fall on both
  engines (`cr_countdown_style`, `wk_countdown_style`); on WebKit layout and paint records fall too. The clock runs
  no CSS animation, so event dispatch stays the same.
- **morph.countdown:strip.** Ten faces become one 12-entry strip: style, layers and composite fall. GPU memory
  rises by at most 2,287,000 bytes of hero clock backing (the Simulator's whole clock backing; the CI row rises by
  1,696,000 bytes), and 197,145,405 + 2,287,000 ≤ B
  (`strip_claim_trade_verdict_win`): the Core claim is a trade, the resource verdict a win. Chromium repaint is
  unknown, so it is open.
- **morph.panel:rest.** Chromium: style, layout, paint and repaint all rise (trade). WebKit: main-thread work is
  unchanged (`wkO`/`wkV`). A none→blur toggle may create the group layer and paint it in full, but no theorem links
  the filter toggle to a re-attach paint (`tween_repaint` covers animation promotion), so repaint is unknown (open).
- **nav:logo-3d.** Layout and repaint fall. While morphing the logo moves by `transform` instead of `translate` and
  `scale` (nav/box.module.css:53-57), and the nav keeps the original transition lists (box.module.css:4), so event
  dispatch is unknown: open on both engines. The WebKit peak adds the modelled 3,801,600 bytes of two 440×120 layers
  at DPR 3 (`navMorphBytes`, INFERRED box size) to the base peak.
- **morph.mount:shift-dormant.** The shift model moves work without changing totals (neutral). CI and the phone
  disagree, see the table above.
- **engine.events:quiet.** WebKit: 7 fewer root listener registrations remove the dispatch and its script
  (`quietRecords_eq`), a win. Chromium creates an animation event only while the document has a listener of its
type (`css_animations.cc:3610@f842f52`), and the page's other listeners are not enumerated, so event dispatch and
script are unknown (open).

## Limits

- PrePaint (props) is not a resource. A gain that only reduces resident layers counts as neutral.
- The WebKit scene-pause event-dispatch fall is INFERRED from WebKit source. Every Chromium event sign without a
  Chromium source line is unknown.
- Four bounds remain, each with its own unit: strip layers on both engines (72 layers per census state), strip GPU
  memory on WebKit (2,287,000 bytes of hero clock backing) and panel:rest layers on WebKit (1 layer per census
  state). `boundHolds` and the measure-webkit test check that every check row of a bounded effect shares its unit and
  changes by at most the bound. The idle-none, scene-pause and events:quiet bounds were dropped because the measured
  change is larger or in another unit (scene-pause: up to 89 layers against 85); the logo-3d bounds were dropped
  because their only check rows are census sums.
- The `peak` fields are MEASURED phone maxima, or the MEASURED base peak plus a modelled rise (strip, logo-3d), so
  memory fit is partly checked against the data it was read from.
- Follow-ups: derive the repaint signs and bounds of logo-3d, strip and panel:rest from `changePx`/`repaintPx` at
  DPR 3; count the flags' own observer callbacks (idle-none, hidden-pause) in script; read Chromium source for the
  remaining Chromium event signs.
- No CI was dispatched and the phone was not used for this task. All observations come from earlier runs.
