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
| hero:scene-pause | win | win | trade / win |
| morph.columns:idle-none | win | win | win / win |
| morph.countdown:hidden-pause | win | win | win / win |
| morph.countdown:strip | open | win | trade / trade |
| morph.panel:rest | trade | trade | trade / win |
| nav:logo-3d | open | win | unknown / unknown |
| morph.mount:shift-dormant | neutral | neutral | trade / unknown |
| engine.events:quiet | open | win | no-win / win |

- Trade rows that become wins (`becomesWin`): hero:scene-pause on Chromium and morph.countdown:strip on WebKit.
- A win that becomes a trade (`leavesWin`): morph.panel:rest on WebKit, because each blur fade re-attaches the panel
  and repaints it.
- Preset decisions are unchanged. This note only reports these rows.

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
- Unit (CONFIRMED): WebKit Timeline paint quads are in root-view CSS px², and nested paints are dropped
  (`WebCore/inspector/agents/page/PageTimelineAgent.cpp:293-305`, `inspector/TimelineRecordFactory.cpp:152-170`,
  `inspector/agents/InspectorTimelineAgent.cpp:629-631@862f17d`). The phone's measured repaint area is this sum, so
  it compares to the model at DPR 1.

## Predicted vs measured (`obsCheck`)

| check | rows |
|---|---|
| agree | 45 |
| unresolved (predicted a move, measured same) | 7 |
| confounded (slow walk, non-census) | 24 |
| disagree | 5 |
| unpredicted (predicted unknown) | 2 |

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

Phone data: the seven finished arms of results/phone/2026-10-25-end-counts (MEASURED). Only the per-pass ranges
are in the golden; the raw passes stay local. CI data: the run ids in each check row's `source` field.

## Per-flag footprints (signs as in the golden)

- **hero.exit:threaded.** Chromium (`HeroExitOpt.crFrames`): script, repaint and frames fall; style rises (`cr_lane_mixed`)
  and event dispatch rises (two React root records per animation event), so it is a trade. WebKit
  (`wkFrames`): main-thread stages fall, event dispatch rises (trade). The re-attach makes paint and repaint unknown
  (`combine_opposite`).
- **hero:scene-pause.** The hero's layers drop (`heroLayers_drop`), and style or events fall. The ledger's Chromium
  trade came from trajectory timing, which this model does not count as a resource.
- **morph.columns:idle-none.** The marquee track layers drop (`tracks_layers_drop`), and so do composite and GPU
  memory.
- **morph.countdown:hidden-pause.** The skipped face writes remove style work (`HiddenPause`). On WebKit they also
  remove layout and paint records.
- **morph.countdown:strip.** Ten faces become one 12-entry strip: style, layers and composite fall. GPU memory
  rises by at most 2,287,000 bytes (the Simulator's clock backing), and 197,145,405 + 2,287,000 ≤ B
  (`strip_claim_trade_verdict_win`): the Core claim is a trade, the resource verdict a win. Chromium repaint is
  unknown, so it is open.
- **morph.panel:rest.** Chromium: style, layout, paint and repaint all rise (trade). WebKit: main-thread work is
  unchanged, but repaint rises with the re-attach on each fade (trade).
- **nav:logo-3d.** Layout and repaint fall, and one 440×120 nav layer at DPR 3 adds 3,801,600 bytes
  (`navMorphBytes`, INFERRED box size) within B: a win on WebKit.
  Chromium has no GPU peak for the added layer, so memory fit is unknown and the verdict is open.
- **morph.mount:shift-dormant.** The shift model moves work without changing totals (neutral). CI and the phone
  disagree, see the table above.
- **engine.events:quiet.** WebKit: 7 fewer root listener registrations remove the dispatch and its script
  (`quietRecords_eq`), a win. The Chromium script sign is unknown (open).

## Limits

- PrePaint (props) is not a resource. A gain that only reduces resident layers counts as neutral.
- The event-dispatch falls for scene-pause, idle-none and hidden-pause are INFERRED: a paused animation dispatches no
  iteration events.
- Bounds are given only where engine source fixes them (strip GPU bytes, nav layer bytes, the repaint bounds above).
  Every other effect is a sign only.
- No CI was dispatched and the phone was not used for this task. All observations come from earlier runs.
