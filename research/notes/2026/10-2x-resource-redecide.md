# Preset rows re-decided by the resource verdict

Question: with the landed resource verdict (a GPU memory cost is acceptable when main-thread work falls and the peak fits
budget B), which preset rows change? Rows: `morph.countdown:strip` on WebKit (ledger trade, verdict win),
`morph.columns:idle-none` on both engines and `morph.panel:rest` on WebKit (ledger win, verdict not win). Model:
`lean/Fw/Engine/ResourceFlags.lean`. Goldens: `packages/contracts/golden/engine/resource.jsonl` (fields `verdict` and
`decided` per row), `packages/contracts/golden/preset/v2-proved.decisions.jsonl`. Tags: CONFIRMED, INFERRED, MEASURED.

## Answer

| flag | engine | predicted | decided | basis | preset effect |
|---|---|---|---|---|---|
| morph.countdown:strip | WebKit | win | win | INFERRED win: gated falls are predictions (strip_units, strip_repaint_down); phone counts inside base spread, 3 strip passes, every visit ended Serious (mixed thermal) | none yet: the trajectory cells are pending and Chromium is open |
| morph.countdown:strip | Chromium | open | open | INFERRED, no phone row | none |
| morph.columns:idle-none | Chromium | open | open | INFERRED style; phone rows same, mixed thermal (Serious at visit end) | none: still no ledger link (`why` no-link) |
| morph.columns:idle-none | WebKit | open | open | INFERRED style; phone rows same, mixed thermal (Serious at visit end) | none |
| morph.panel:rest | WebKit | trade | trade (INFERRED; CI only, no phone row) | INFERRED (see per-row), CI only | stays excluded; the reason is the decided verdict |
| morph.panel:rest | Chromium | trade | trade | MEASURED, CI only | stays excluded |

The `v2-proved` preset is unchanged (`{"engine.scroll":"unthrottle"}`). No row in this task is in the look-change class
(`part.json` has no `visClass` for strip, idle-none or rest), so none waits on the user's visual review.

Every phone number below comes from sessions in which each visit ended at Serious thermal state (MEASURED,
`10-25-phone-thermal-check.md`). Counts and the census do not depend on the
clock; frames do.

## Decided verdict (`decided`, `resolvedSign`, `moved`, `evidenceSign`)

The predicted footprint keeps its signs. `decided B fp` is `verdict B` of the footprint with each sign resolved by the
footprint's own observations. An observation moves when its walk is not slow (census resources ignore the walk) and
its measured sign is up or down; a measured `same` never counts. One move sign replaces the prediction; up and down
together give `unknown`. Proved: `moved_slow`, `moved_same`, `moved_move`, `evidence_none`, `evidence_agree`,
`evidence_conflict`, `resolved_predicted`, `resolved_measured`. `becomesWin` and `leavesWin` use the decided verdict.

Side effects outside the three rows (MEASURED, already in the golden):
`morph.mount:shift-dormant` goes from neutral to trade on both engines (WebKit script and EventDispatch rise on the
phone; Chromium resolves about 200 more elements). `hero:scene-pause` on WebKit goes to trade (below).

## Per row

**morph.countdown:strip, WebKit: win.** Gated signs: style down (`strip_units`, INFERRED from the model), repaint
down (`strip_repaint_down`), the rest same. GPU memory up by the clock backing (`strip_backing_gt`; Simulator 0.591 to
2.287 MB, run 40081936555, MEASURED). The phone thermal session (9 base, 3 strip passes, not slow: wall 3614 to 3784
against 3607 to 3653 ms) measures style, layout, paint records, script, EventDispatch, repaint area, composites and frames
inside the base spread (MEASURED, 8 rows `thermalStrip`): 5 agree, 3 unresolved (style, repaint, composite). So the
win rests on predicted falls the phone does not contradict and does not show. Peak, mixed source (`stripPeakSrc`,
`strip_peaks_fit`): the phone end-counts base peak 197,145,405 B plus the Simulator clock backing 2,287,000 B is
199,432,405 B. The phone thermal session's own strip peak is 191,681,597 B (y 4500, one pass). Both fit B = 220,200,960 B,
and B stays INFERRED.

The strip's layer bound of 72 per census state (the clock's own layers) fails on the phone (MEASURED,
`thermalStripLayers`): drops by range are 74, 78, 72, 73, 72 at y 0, 1500, 3000, 4500, 5267, and at y 1500 every pass
pair drops at least 74. Those rows stay outside `observations`, since the golden replay test fixes the bound count at 4.
Backing per state rises by 2,120,288 B at y 0 in all 3 strip passes; at y 3000 and y 4500 one of 3 strip passes is
7,432,880 B and 23,284,400 B above the base (constant over 9 passes), beyond the 2,287,000 B clock-backing bound; like
the layer rows they stay outside `observations` (MEASURED, thermalStripBytes). The peak still fits B (strip_peaks_fit).

**morph.countdown:strip, Chromium: open.** Repaint stays unknown: faces and strips both own their layers, so per-frame
repaint is the same (`own_frame_repaint`), and Chromium's off-screen tile retention is not modelled.

**morph.columns:idle-none, both: open.** Style `same` is INFERRED: `cr_realChrome_pause_eq` and `wk_pause_eq`
cover a paused compositor animation; the flag removes the animation (animation-name none), which the lemmas treat as a pause.
Paint records, script, EventDispatch and repaint stay unknown; the phone measures them inside the spread (4 unpredicted
rows). A measured `same` does not resolve an unknown, so both engines stay open.

**morph.panel:rest, WebKit: trade.** Repaint is up (`panel_repaint_up`, INFERRED premise: each none to blur toggle
re-attaches the group layer; no theorem links `filterToggle` to the re-attach). CI webkit-sim 40174475566 (base) vs
40174472900 (flag), 6 passes each, not slow: Paint records 1352 to 1409 against 1433 to 1678, up (raw MEASURED:
quarantined by measure.classify and load-confounded, flag VMs 30 to 40 percent higher loadCenti, panel-rest-n11; the
decided trade is INFERRED, and the predicted trade rests on the INFERRED panel_repaint_up premise); repaint area, style,
layout and EventDispatch inside the spread; backing summed over y ≥ 3000 347,962 to 358,260 KiB against 304,047, down
(MEASURED, agrees). Per-state layers (y 3000: 136 to 140 against 135 to 139) are not added: the range spread exceeds the
bound of 1, so the bound check needs a spread rule (follow-up).

**morph.panel:rest, Chromium: trade** (unchanged, `MorphPanelOpt.crO/crV`; ledger n = 11 MEASURED, runs 40174480097 /
40174482844). In `Gen.lean` the exclusion is `Exclusion.resourceTrade`; a `#guard` in `Fw.Engine.Resource.Preset`
(`ResourceFlags.lean`) requires every such entry to have a decided trade on every engine; `panel_rest_not_mem` keeps it out of the preset.

## Review follow-ups

- **hero:scene-pause, WebKit EventDispatch:** the INFERRED fall (StyleOriginatedAnimation.cpp:340-345@862f17d) is not seen.
  CI webkit-sim 40151813906 (base, 4 passes) vs 40151792642 (flag, 6 passes), not slow (3 × 7262 ≥ 2 × 7378): EventDispatch
  1053 to 1179 against 1072 to 1674, same (MEASURED). The sign is unknown. The same runs measure style 647 to 651 against
  657 to 688, up (MEASURED; cause INFERRED: the pause attribute write per scene change restyles the hero subtree). Predicted
  open, decided trade.
- **Repaint at DPR 3** (`repaintPx_dpr3`: 9 device px per CSS px):

| flag | engine | sign | theorem | premise |
|---|---|---|---|---|
| strip | WebKit | down | `strip_repaint_down` | a face leaves coverage and returns (`face_reattach`) |
| strip | Chromium | unknown | `own_frame_repaint` | off-screen tile retention not modelled |
| logo-3d | WebKit | down | `logo_repaint_down` | at least 3 bar resizes per morph, logo no larger than the bar (INFERRED) |
| logo-3d | Chromium | down | `logo_frame_repaint_down` | per frame only; the promotion raster is not modelled (INFERRED) |
| panel:rest | WebKit | up | `panel_repaint_up` | a toggle re-attaches the group layer (INFERRED) |

## Accepted limits

- No CI dispatch and no phone use in this task (pinned sessions: phone-thermal-pin).
- B stays INFERRED. A look-change flag enters a preset only after the user's visual review.
- Strip enters `v2-proved` only after its trajectory cells pass on both engines, which needs CI runs.

## Open

- Drop the strip WebKit layer bound of 72 and bytes bound of 2,287,000 B (the phone refutes both: layer drops 74 and
  78, one pass +23,284,400 B at y 4500) and add `thermalStripLayers` and `thermalStripBytes` to `observations`: needs
  `packages/measure-webkit/test/resource-check.test.mjs` to accept fewer bounds (follow-up).
- `moved` takes no VM load or quarantine input: the scene-pause WebKit style rise (6 to 37 records) and the panel:rest
  WebKit Paint rise can both be load-confounded. Add a load/quarantine input to `moved`, or re-run on matched VMs
  (follow-up).
- `Exclusion.resourceTrade` in `Gen.lean` is a hand list checked by a `#guard`; a flag that becomes a decided trade on
  every engine is excluded only once someone adds it. Derive the exclusion from the verdict once the `include_str` cone
  issue is solved (follow-up).
- Bounds against ranges need a spread rule before per-state CI layer rows can enter (panel:rest y 3000).
- The scene-pause WebKit style rise needs a mechanism lemma.
- `Gen.lean` does not import `ResourceFlags.lean`: the parts modules it imports read `golden/parts/*.jsonl` by
  `include_str`, which would put those files in the `Main` cone outside `coneGlobs` (`scripts/ci-paths.test.mjs`). So the
  check runs the other way: `ResourceFlags.lean` imports `Gen.lean`.
