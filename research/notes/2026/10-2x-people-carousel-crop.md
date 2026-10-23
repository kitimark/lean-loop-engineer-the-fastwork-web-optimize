# people.carousel:crop (GPU route, look class L)

Status: Lean proved, variant built, CI runs pending (see Runs). Ledger row `people.carousel.crop`; part.json variant `crop`
(kind proposal, visClass L); Lean `lean/Fw/Parts/PeopleCarouselCrop.lean`; golden `packages/contracts/golden/parts/people-carousel-crop.jsonl`.

## What changes per frame (CONFIRMED by the Lean statements, premises named)

Every 1.02 s the swap row shows for 220 ms (13 frames at 60 Hz, `swapFrames_60`).

| | original | crop |
|---|---|---|
| leaver effect | opacity, flex-basis, width, margin-right, border-width, transform | opacity, transform |
| followers | moved by layout (the leaver's collapse) | `translate: -24px` effect each (3) |
| entering avatar | pop (opacity, transform) | pop + `translate` effect |
| thread, WebKit | exit on main (`wk_orig_exit_main`), pop UI process | all six UI process, every mode (`wk_crop_all_comp`) |
| thread, Chromium | exit on main (bit 13), pop compositor | all six compositor (`cr_crop_all_comp`) |
| layout per frame | 1 pass, 4 units Chromium; 1 pass, 4+ units WebKit (`cr_orig_layout`, `wk_layout`) | 0 (`cr_crop_zero`, `wk_layout`) |
| paint, raster, commit per frame | exit repaints | 0 in Chromium (`cr_crop_zero`), 0 off the comp stage in WebKit (`wk_crop_zero`) |
| compositor units | 1 | 6 (a trade: `wk_comp_trade`, `cr_comp_trade`) |
| animated layers | 1 | 5, 36,864 B each at dpr 3, 184,320 B in all, for 220 ms (`layer_budget`) |

## Why there is no same-look route (`split_keeps_layout_wk`, `split_keeps_layout_cr`)

Any split of the `avatars-exit` properties into effects leaves a piece that holds `width`. That piece is not accelerated on
either engine (WebKit: `layout_not_accelerated`, `piece_main`; Chromium: bit 13), so it ticks on main every frame and
its frame runs a layout pass, in every mode and on every layer state. Layout can only go by changing what is animated,
which changes the look. This is the finding for the same-look preset: nothing to ship there.

## Deviation from the ledger's first design

Ledger row 19 proposed a clip-path ellipse crop. A clip-path effect is not accelerated in WebKit (`wkThread` guard
`[.transform, .clipPath]` is `.main`, WebKit.lean) and paints in Chromium (paint worklet not used). So the variant
animates opacity, transform and translate only; the crop is the container's existing `overflow: hidden` plus paint order
(followers draw over the leaver). That meets the task's goal (compositor only), not its wording.

## Look class L (a proposal; the user reviews)

- The leaver keeps its 32 px box and fades and scales in place instead of collapsing; the border-width shrink is gone.
  The differing region lies in the leaver slot (`leaver_region`: both boxes within 32 px; `leaver_box_differs`: at half
  progress 16 px against 32 px).
- Followers: translate `-24p` px equals the original shift at every progress (`shift_eq_translate`, the `follower_shift` of
  the existing file). Painted positions are within half a device pixel of the exact one on both sides, so they differ by at
  most one device pixel (`snap_err`, `follower_within_one`). LayoutUnit rounding (1/64 CSS px) is not modelled.
- Never in the same-look preset: `Fw.Preset.Gen` lists it in `look-change.candidates.jsonl`.

## Accepted limits

CI has no real GPU; the felt-lag check on the phone is the user's. A no-win on a cost lane is a finding with the Lean why above.

## Runs

(filled from the handoff when runs finish)
