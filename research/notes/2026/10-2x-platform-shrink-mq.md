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

## Premise check (CONFIRMED)
`--platform-shrink` is read at platform.module.css:8 (scale) and :31 (radius); the scale and radius variables only at :31
and :32; the band at :303-315 pins them on the section and sets `border-radius: 0; transform: none` on the card. No other
file of the part mentions it. `shrink.test.ts` pins these line numbers and the band block.

## Work claim and its limit
The saving is one custom-property write per moving frame in the band, which restyles the section subtree. Counts are in
`results/platform-shrink-mq/report.json`. INFERRED: the frames fall on the way into the end-of-page window, not
inside the felt part; the Simulator replay of the end of page is a follow-up.
