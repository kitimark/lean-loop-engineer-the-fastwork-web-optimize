# sim-layer-sweep: does layer-sweep remove the last per-frame recalc at the end of the page?

Status: MEASURED on the CI iOS Simulator (iOS 27.0 runtime, not the phone). Branch `ci/sim-layer-sweep`, 3 runs x 3 separate
jobs x 1 round = 9 jobs. No flag or preset change: `platform.sweep:layer-sweep` stays class L, awaiting the user's visual review.
gate: none (measurement task; layer-sweep gate run 40335795674 is older).

## Answer

Yes, on the Simulator. With `platform.sweep:layer-sweep` replacing `platform.sweep:offscreen-pause` (arm `bothL`), the
end-of-page window reads 99..110 style recalcs per 100 animation-frame callbacks (tier one), against 199..204 for `both`
(tier two). Back at the top: `bothL` 100..102, `both` 200. The paused stage reads 100 for both arms in every job.

| run | commit | end both | end bothL | back both | back bothL |
|---|---|---|---|---|---|
| 41212638765 | 9672980ce | 201, 203, 204 | 100, 103, 106 | 200 x3 | 101 x3 |
| 41215962130 | 13f66adf0 | 204, 199, 200 | 106, 99, 101 | 200 x3 | 101, 100, 101 |
| 41219277317 | 9110f3bbd | 200, 199, 203 | 103, 104, 110 | 200 x3 | 101, 101, 102 |

Lean-gated verdict (`Fw.Device.SimLayerSweep`): `cut:platform.sweep`, predicted equal to observed ("held"), end and back, in
all three runs. Tiers: `bothL` one and `both` two in 9 of 9 jobs.

## Per-arm census (took-check per flag)

- Every flag took in every job, both arms, both stages (effect lines "took", overall "took").
- `bothL`: 4 layer loops running (`sweepLayerX`, transform only, 2 in view), 0 sweepDoc loops, nothing non-layer running.
- `both`: 4 sweepDoc loops, 2 running in view, which hold it at about 200 per 100.
- Animated properties of the layer loops: `transform` only (CONFIRMED in the stylesheet; `CSSProperties.json` marks transform
  accelerated).
- Accelerated state: run 3 read the Web Inspector. 5 `layerBg` nodes, 1 without a renderer (`display:none`-like, no layer
  tree entry), 4 layers, all 4 with the `animation` compositing reason, `will-change` reasons 0. The `animation` reason is
  necessary but not sufficient (`RenderLayerCompositor.cpp:3842-3860` @862f17d), so the evidence is "inspector" plus the
  property list; whether the animation runs on the compositor is INFERRED. Runs 1 and 2 had probe errors; their rates are unaffected.

## Lean tick demand (CONFIRMED source, @862f17d)

An animation effect ticks the frame loop only while it is running, rendered and not completely accelerated:
`KeyframeEffect.cpp:2724-2745` (`ticksContinuouslyWhileActive`), `AnimationEffect.cpp:391-401`,
`DocumentTimeline.cpp:371-388`, `KeyframeEffect.cpp:1736-1768`. The sweepDoc loops animate `background-position`, which is not
accelerated, so each in-view loop ticks every frame; the layer loops animate transform only, so they do not.
Theorems in `lean/Fw/Device/SimLayerSweep.lean`: `ticks_core` :95, `accelerated_loop_adds_no_frame_tick` :109,
`sweepDoc_ticks` :141, `sweepLayer_core_no_tick` :146, `predTierL_accelerated` :239, `predTierL_contradicted` :279,
`pred_cut_of_census` :425. TS stand-in checked against `packages/contracts/golden/device/sim-layer-sweep.jsonl`
(`packages/measure-webkit/src/sim-layer-sweep.mjs`; `layerReadOf` and the report lines have no golden, TS stand-in).

Residual over 100 for `bothL` (0..10): a document `animationend` listener (`apps/site/src/parts/hero.exit/index.tsx:65-66`)
gives one tick per 4 s iteration per loop (`KeyframeEffect.cpp:2747-2763`, INFERRED). Lean bound `iterRate_le` :172: at most 9
per 100 over a window up to 24000 ms. The rest is shared window noise (`both` also reads up to +4 over 200). r3 job 3 reads
110 (window 23.7 s), at the tier-one band edge.

## Findings from the harness

- Premise refuted: the 360-callback windows are not 6-8 s on the Simulator. They span 6.9..23.7 s (end) and up to 28.2 s
  (a `both` back window), about 13..50 fps. The Lean bound `windowMsMax` was set to 24000 from the measured spans; the report
  flags windows outside it (r3 back job 3: 24407 ms, still tier one).
- Pin: 18 of 18 end windows have y equal to the window's own maxY (0 jumps), so the end window sat at the end of the page. Only 5 of 18 sit at the final page end 5267 (the others at 5231; back windows always 5267). The 36 px growth between
  the end and back stages is not investigated (follow-up). No rate difference between the 5231 and 5267 windows.

## Limits

Simulator only (not the phone); 3 jobs x 1 round per run; accelerated state is inspector
evidence plus INFERRED; no look verdict (layer-sweep changes the look of the sweep and stays class L); no preset change.

Raw results: `results/sim-layer-sweep/r1|r2|r3/` (job JSON, logs, rows.txt, table.txt, layer.txt).
