---
id: 2026-10-2x-platform-shrink-mq
kind: note
title: "platform:mq, skip the invisible --platform-shrink write in the phone band"
status: draft
created: 2026-10-22
authors: [agent:part-builder]
topics: [platform, end-of-page, webkit, main-thread, flags]
---

# platform:mq (task platform-shrink-mq)

Question: on the phone band the CSS pins the platform card (scale 1, radius 0), yet the scroll callback computes and
writes `--platform-shrink` every frame the card moves. Can the write be skipped there with an identical look?

## What changes
- `apps/site/src/parts/platform/driver.ts`: `createShrink(el, env, { gate })`. With the gate on (`mq.c860`), no
  `setShrink`; the class switch (`is-platform-shrinking`, section background white, platform.module.css:19-21) runs as
  before. The decision is the pure `planShrink` in `logic.ts`, checked against Lean goldens.
- `index.tsx`: under `?fw=platform:mq` the gate is `matchMedia(mq.c860)`; its `change` event runs the frame, so leaving the
  band writes the current value before the next paint.
- `part.json`: variant `mq`, kind optimized, tier T0.

## Proof (lean/Fw/Parts/PlatformShrinkOpt.lean)
| claim | theorem |
|---|---|
| in the band the card's look is (1, 0) whatever the inline value | `look_gated` |
| the look is value-independent exactly in the band | `look_const_iff` |
| after a non-gated event the variant holds the original's value | `inl_ungated` |
| class bits agree after every event | `cls_agree` |
| looks agree after every event, also across band changes | `look_agree` |
| visible scenes equal (class E) | `platformShrink_visSame` |
| variant never writes more | `writes_le` (invariant `writes_inv`) |
| a run inside the band writes nothing, strictly less when the original writes | `gated_run`, `gated_run_lt` |
| the TS decision is the model's event | `stepV_writes` |

Difference from people.card:mq: that proof assumes the band is fixed per load (P1). Here the event sequence carries the
environment per event, and the media-change handler is an event, so a rotation or resize across the edge is covered
(premise: an event runs at every gate change; the HTML rendering update reports media-query changes before it runs
animation-frame callbacks and style, so the write lands before the next paint; CONFIRMED by the spec text, not measured).

## Premises of the proof
- P1: the frame runs in the `mq.c860` change handler, so the gate it reads is the one in force at the next paint.
- P2: the only author of the inline `--platform-shrink` is this writer; the initial inline value is the CSS `0`.
- P3: a write is counted when the value differs from the last written one (a same-value inline write is a no-op in both
  engines, see PeopleCardOpt premise P5). Browser cost of a write is MEASURED on CI, not modelled.
- Original: snapshot `nodes/2.DyWL8TcE.js` pretty 12434-12448 (shrink callback), `assets/2.gBuqKVzi.css` pretty
  5530-5531, 7830, 10985-11075 (the section variables and the band), restated in this repo's faithful part.

## Premise check (CONFIRMED)
`--platform-shrink` is read at platform.module.css:8 (scale) and :31 (radius); the scale and radius variables only at :31
and :32; the band at :303-315 pins them on the section and sets `border-radius: 0; transform: none` on the card. No other
file of the part mentions it. `shrink.test.ts` pins these line numbers and the band block.

## Result: the premise does not hold on the rewrite page (negative finding)
- The proposal expected one section restyle saved per frame while the card bottom is between 85 % and 35 % of the screen
  height. The rewrite's last section is the platform card (App.tsx:68-83; platform.module.css:15, padding 0), so a plain
  scroll never lifts its bottom above the viewport bottom. CONFIRMED by source. The shrink is 0 at every frame and the
  original writes nothing either: Lean `unshrunk_run` (writes = 0 while bottom >= 0.85 vh).
- Debug probe, not a result (local Playwright WebKit on the CI-built site of run 39680958629): card bottom at the end of
  the page 807.8 px at 430x775, 838.5 px at 1280x800; under `platform:mq` the inline value was never set at 430.
- MEASURED, CI webkit-sim, end-of-page window y 4500..5200 (15 steps, 2 passes), base run 39680958629 against
  `?fw=platform:mq` run 39680964944: RecalculateStyles 94/70 against 85/83, Layout 100/56 against 87/76. The gap between
  arms is smaller than the gap between two passes of the base (24, 44). No effect visible. Frame-time percentiles are
  not available in this lane (no RenderingFrame events).
- Gate: breakpoint-gate with `platform:mq`, engines both, run 39680952848 success. Lean CI run 39680908944 pass.
- Lesson: a saving that rests on a runtime path needs the path shown on the page it will run on before the proof is
  built; the cheapest check is the card's rect at the end of the scroll. Where a section sits last on the page, a
  scroll-progress writer keyed to the viewport bottom is dead code there. Follow-ups: the Simulator replay of the end
  of page (morph push), and re-check if a section is added below the card.
