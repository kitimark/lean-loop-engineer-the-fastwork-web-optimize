# hero.countdown:hidden-pause on the homepage lane: no saving

`?fw=hero.countdown:hidden-pause` alone saves no restyled element in frames 104-200 on swipe-v1 and swipe-touch-v1,
over the base page and over v2-proved (MEASURED). The flag stays out of v2-proved: `linkTable` in
`lean/Fw/Preset/Gen.lean` gets no `k8h` row, and the regenerated preset files are byte-identical to the current ones.

## Arms

Workflow chromium-counts, sha bcf9c7e0, image run 39292310716, 3 reps per run. Each arm has a control run at the same
sha. The judged counter is the sum of `trace.UpdateLayoutTree.elementCount` over frames 104-200 (min and max of the
3 reps).

| profile | over | control run | arm run | control | arm |
|---|---|---|---|---|---|
| swipe-v1 | base | 39313893490 | 39312082945 | 9497-9502 | 9499-9502 |
| swipe-v1 | v2-proved | 39313899612 | 39312057983 | 1255-1257 | 1255-1257 |
| swipe-touch-v1 | base | 39313905095 | 39312091230 | 9515-9517 | 9515-9517 |
| swipe-touch-v1 | v2-proved | 39313910145 | 39312076214 | 2166-2168 | 2166-2168 |

The flag adds cost in every arm (MEASURED):

| profile | over | `trace.FunctionCall` frames 0-103 | other rises |
|---|---|---|---|
| swipe-v1 | base | 779 to 872 | none |
| swipe-v1 | v2-proved | 868 to 962 | none |
| swipe-touch-v1 | base | 938 to 1023 | frames 104-200: FunctionCall 1219 to 1228, FireAnimationFrame 445 to 446 |
| swipe-touch-v1 | v2-proved | 1027 to 1114 | after frame 200: UpdateLayoutTree 542 to 543, elementCount 22713-22715 to 22833-22851 |

The FunctionCall rise is the MutationObserver on the stage's style attribute. It runs once per hero.exit write of
`--exit-opacity` (INFERRED from `apps/site/src/parts/hero.countdown/hidden.ts` and `hero.exit/driver.ts`).
`results/countdown-hidden-arm/summary.json` lists the per-rep sums of seven counters in three frame ranges.

## Why nothing drops

`hidden_work` (`lean/Fw/Parts/HeroCountdownHidden.lean`) proves a saving only for a frame whose only change is the
countdown and that has $d > 0$ springing digits. Neither condition holds on these frames.

1. The style-pass term is absorbed. Every frame from 104 to 200 already has an UpdateLayoutTree from other writers
   (about 98 elements per frame over the base page, 13 over v2-proved, MEASURED). Theorem `hidden_pass_absorbed`
   proves that the pass count of any stage another part touches is the same with and without the face writes (from
   `passes_absorb_part`).
2. The element term is zero. In the lane, spring frames restyle no face element, even in the faithful control. Part
   page run 39257533380 (`?only=hero.countdown`, shard r1) shows this. Frames 120-146 run the digit's spring chain
   (FireAnimationFrame 3) and frames 104-119 do not (FireAnimationFrame 2), but both restyle 4 elements per frame
   with no paint. While the hero is in view, frames 60-77 (spring) and 34-59 (no spring) both restyle 105 elements,
   paint 7 times and raster the same 3150 px (MEASURED). So the lane's countdown frames are `cdFrame p 0 l`.
   Theorem `hidden_work_idle` proves that `skipWrites` is the identity on that frame, with equal work in every
   engine.

The source says each changed face should cost one element. `Element::InvalidateStyleAttribute` marks a changed
inline style (third_party/blink/renderer/core/dom/element.cc:13299-13311@f842f52). `ResolveStyle` counts every
element it resolves, including the incremental inline path
(third_party/blink/renderer/core/css/resolver/style_resolver.cc:1362-1364, 1442, 2015-2030@f842f52). The writes
therefore change no face transform in the lane. Why they change none is open. Two candidates (INFERRED): the
written strings equal the current ones, or the handles point at nodes that are no longer in the document.

## Lesson

Before an arm, check on the part page that the control pays the cost the flag removes. Here the part page run that
already existed showed 0 face elements, and that would have decided the arm without 4 homepage runs. A per-frame
saving proved for a frame that changes only one part needs a check that the lane's frames match that premise
(`passes_absorb_part`).
