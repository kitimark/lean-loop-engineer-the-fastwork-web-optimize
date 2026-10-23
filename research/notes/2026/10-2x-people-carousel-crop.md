# people.carousel:crop (GPU route, look class L)

Status: Lean proved, variant built, CI runs done (see Runs; WebKit cost shows no separated difference, not a no-win proof). Ledger row `people.carousel.crop`; part.json variant `crop`
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
which changes the look. The same-look preset has nothing to ship.

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

## Runs (branch ci/people-carousel-crop, code tip ee8ff9c58; files in results/people-carousel-crop/)

| lane | run | result |
|---|---|---|
| trajectory-probe, fw=people.carousel:crop, both engines, all widths (inputs read back from the step name: commit-line) | 39896845339 | success. Chromium hero and morph units RED as in the faithful arm (42 fail in both) plus one new unit nav.background-color 1280 close@0, not this part; Linux WebKit CLEAN (hero path) |
| GPU carousel cell, people zone (avatar rects per frame, Chromium, 390 and 640) | same run, artifact cells-gpu-chromium | grade L at both widths, 4 reps each, swaps 4 against 4: the rects differ because the leaver keeps its box (Lean `leaver_box_differs`) |
| breakpoint gate, both engines, fw=people.carousel:crop | 39898995879 | pass |
| webkit-sim lag+cost, rewrite, 430x775, vms 3, base | 39899015125 | r1 and r2 gave lag json (r3 cancelled after r2 failed) |
| webkit-sim lag+cost, same, fw=people.carousel:crop | 39899018175 | failed, no data (Safari lost in every VM) |
| same, retry | 39906731945 | success, r1 r2 r3 |

Dispatches used: 4 of 6 (gate 1, webkit-sim 3).

WebKit cost (end of page = scroll B, the people zone; base 3 passes, flag 6 passes): no counter and no frame-cadence value differs
beyond overlapping ranges (Paint, Composite, Layout, RecalculateStyles, skipped slots, over 25 ms, over 50 ms). This is
not a no-win proof. The lane scrolls in steps through the page and does not sample inside the 220 ms swap windows, which hold 13
layout frames of every 61, and the Simulator is noisy (wide ranges). The lane does show, as the Lean layer budget predicts, a
layer census at the end-of-page state 124 layers against 128 (+4) and compositing reason `animation` 5 against 8.
Follow-up outside the unit: a lane that samples inside the swap windows (the time-driven swap), and the felt-lag check on the phone.

The trajectory units of the hero and morph paths do not read the people zone; the one new unit is on the nav.
Linux WebKit walks the pain cell only, so there is no WebKit people-zone trajectory (accepted limit).

## Follow-ups

1. Footprint (CONFIRMED, packages/contracts/golden/parts/footprint.gen.json): part-footprint.mjs follows className expressions in
   the JSX attribute, not arrow-function locals. The role ternary now sits inline in className in people.carousel/index.tsx, so
   the footprint records `avatar`, `isExit`, `isEnter` and the crop classes `cropExit`, `cropEnter`, `cropShift` again (all six
   `setModuleClass` rows, variants faithful and crop: the tool does not split a part's variants on a ternary). `--write`,
   `lake build Fw.Parts.Contract` and `ContractsGolden.lean --check` are green; FootprintRows.lean and footprint-diff.gen.json
   regenerate unchanged.
2. Premise WkAnim.clean (CONFIRMED, crop.golden.test.ts): every crop rule has cubic-bezier with both y in [0, 1] and
   `avatarsCropExit` and `avatarsShift` have exactly 2 stops. The test fails if a later edit breaks the premise.
3. nav.background-color 1280 close@0 (INFERRED flake): 1 of 62 samples, `close@0=apart`, in a part that does not touch the nav.
   The same unit appears in earlier runs of unrelated arms: 10-21-trajectory-probe.md (4 units, one per width, at close@0),
   10-21-morph-scroll-lock.md (A/A arm, mac 390 and Chromium 1280), 10-20-earn-transition-retarget.md (all four runs). Run id of
   the people-carousel-crop sighting: 39896845339. The rerun is under Follow-up runs.
4. WebKit lane inside the swap windows: design only. The lane needs a time-driven sampler: start the Simulator page at the people
   zone (scroll B held), run `webkit-sim` with the carousel loop live (1020 ms period) and record layout counts per
   frame for at least 8 periods, so 8 x 13 swap-window layout frames of the original arm meet the Lean prediction 0 for crop.
   The existing lag lane scrolls in steps; a hold-at-B profile with a timed capture window is the missing piece, owned by the
   webkit-sim harness, not by this part.

### Follow-up runs

| lane | run | result |
|---|---|---|
| trajectory-probe, fw=people.carousel:crop, widths=1280, both engines, diagnostic (branch ci/carousel-crop-followups) | 39914708420 | success. Chromium 1280: no `nav.background-color` unit (new units 0, both 0, cleared 0): the 39896845339 unit is a flake (MEASURED). Dispatches used: 0 (one push run) |
