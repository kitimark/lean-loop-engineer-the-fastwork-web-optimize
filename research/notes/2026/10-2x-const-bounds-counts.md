---
id: 2026-10-2x-const-bounds-counts
kind: note
title: "morph.panel:const-bounds: counts per zone on WebKit Simulator and Chromium, and why the end-of-page morph is not seen"
status: review
created: 2026-10-26
topics: [morph.panel, const-bounds, webkit, chromium, counts, end-of-page]
---

# morph.panel:const-bounds: counts per zone on WebKit Simulator and Chromium

Verdicts are decided in Lean (`lean/Fw/Parts/ConstBoundsCounts.lean`) from the filed numbers
(`results/const-bounds-counts/cells.json`), replayed by the check.sh job "const-bounds-counts golden check"
(`packages/contracts/golden/parts/const-bounds-counts.jsonl`). The full per-cell tables are in
`results/const-bounds-counts/tables.md`. A cell beats, loses to or equals the base by the base's own pass-to-pass spread
(`Fw.Device.Session.verdict`); a cell with fewer than 3 VMs per side is printed "thin" with its n.

## Answer first

- **WebKit Simulator: no-win in all three zones (MEASURED, n = 3 VMs x 2 passes per arm, cb4bec8).** hero 11 cells same,
  finish 11 same (2 unresolved, 4 thin), rest 9 same. Base run 40196215217, flag run 40196209240.
- **That is "not observed", not "proved no effect" (INFERRED).** The Simulator step walk ends at the page end. The last
  steps (y 5100 to 5267) look like ordinary steps (`results/const-bounds-counts/cells.json`, tail of every pass) and
  nothing is recorded after the walk, so the ~41 morph frames that Chromium shows at the page end are probably not in
  the WebKit data. The lane has no end-dwell mode (the `hold` mode in `packages/measure-webkit/src/scrollrun.mjs` is
  virtual timers, not a dwell).
- **Chromium: finish zone is a cost, hero and rest no-win (MEASURED, 3 runs per arm at 1fac415; base 40171939293,
  flag 40171951145).** The flag lays out more objects, not more times: `trace.Layout` is 71 on both arms, but
  `trace.Layout.dirtyObjects` goes 758 to 920 (+21%) on all three runs. `trace.Paint` is +1 (1188 to 1189),
  `raster.invalidationAreaPx` +228k px and `census.drawingAreaPx` +3.25M px; the other 10 finish counts are same.
- The const-bounds code is unchanged between 1fac415 and cb4bec8 (`git diff` over `apps/site/src/parts/morph.panel` and
  nav shows only part.json, rest.golden.test.ts and rest.logic.ts differ), so the Chromium runs apply to the same flag
  code (CONFIRMED).

## WebKit Simulator

| zone | beats | worse | same | unresolved | thin | verdict |
|---|---|---|---|---|---|---|
| hero | 0 | 0 | 11 | 0 | 0 | no-win |
| finish | 0 | 0 | 11 | 2 | 4 | no-win |
| rest | 0 | 0 | 9 | 0 | 0 | no-win |

- Composite is exactly 61 / 30 / 118 (hero / finish / rest) in all 12 passes (MEASURED), and layer counts and backing MB
  are equal between arms at every state at the same requested y.
- Finish thin and unresolved cells are a confound in the state asked for, not a flag effect: the base passes split
  between y = 5231 (105.79 MB, 2 VMs) and y = 5267 (97.87 MB, 1 VM), while all 6 flag passes were asked 5267. Those cells
  have fewer than 3 VMs on a side and are reported with n.
- Raw ranges (flag vs base) that lean the same direction as the phone end-counts note but stay inside the base spread:
  rest Paint 553 to 630 vs 611 to 674 (5 of 6 flag passes below the base minimum, the base spread is 63); rest
  FunctionCall 915 to 1104 vs 901 to 979. The phone shows rest Paint lower and FunctionCall higher
  (`research/notes/2026/10-25-phone-end-counts.md`); here it is only a direction (INFERRED).
- One flag pass shows 169.93 MB at y 4500 against 149.26 to 153.64 MB for the others (MEASURED, one pass; same verdict).

## Chromium

| zone | beats | worse | same | verdict | worse counts |
|---|---|---|---|---|---|
| hero | 0 | 0 | 14 | no-win | |
| finish | 0 | 4 | 10 | cost | Layout.dirtyObjects, Paint, raster.invalidationAreaPx, census.drawingAreaPx |
| rest | 0 | 0 | 14 | no-win | |

- The morph runs on frames 575 to 615 at y 5342, the page-end dwell (MEASURED, per-frame counts). Frame by frame
  `dirtyObjects` is 7 per morph frame on the base and 11 on the flag: +4 per frame; the zone total is +162
  (758 to 920) over the morph frames.
- `trace.Paint` +1 is a one-frame shift: the base spread is 0, so the strict rule calls it worse (MEASURED); it carries
  no cost on its own (INFERRED).
- Whether the Chromium Layout trace event carries `dirty_objects` as written in `local_frame_view.cc` could not be read:
  the pinned sparse clone `.cache/upstream/chromium@f842f52` holds no file with that string, so the meaning of the
  field is INFERRED from the count (it tracks how many objects the layout pass marked).

## Mechanism and Lean why

- **Why the box is constant (CONFIRMED, proved).** `Fw.Parts.MorphConstBounds.varBox_const`: the panel box is constant
  for every m above the is-morphing cut; `orig_resizes_h` / `orig_resizes_w`: the original grows with m;
  `varBox_rest` and `end_same`: at rest and at the end state m = 1 the variant box equals the original. So the
  census states at rest cannot differ (MEASURED agreement: layers and backing MB equal at the same y), and
  `Fw.Parts.ConstBoundsCounts.panel_var_const` and `panel_orig_changes` restate it for the counts module.
- **Why Layout records are equal (CONFIRMED).** WebKit emits one Layout record per layout pass
  (`Source/WebCore/page/LocalFrameViewLayoutContext.cpp:223,335@862f17d`), and a constant panel box does not add or
  remove a pass: `morph_layout_records_same`. Chromium counts agree (71 = 71, `metric.LayoutCount` equal).
- **Why the flag lays out more objects on Chromium (INFERRED mechanism, proved arithmetic).** The `.cb` rules at
  `apps/site/src/parts/morph.panel/morph.module.css:194-228` give four children (`.backdrop`, `.veil`, `.center`,
  `.footer`) a per-frame inset from `--morph`, so each morph frame re-places those four. Lean: `insetKids = 4`,
  `kid_top_moves` (the top inset of an inset child moves between two morph frames), `dirty_gap` (a morph frame of
  the flag dirties exactly `insetKids` = 4 more objects than the original) and `dirty_gt` (strictly more). The panel layer is not resized, but the kids are placed by layout instead of by
  the panel's own box.
- Why layers and backing cannot differ in this lane (INFERRED): the layer box is constant only while the morph runs, and the lane's
  census samples at requested y values at rest, where both arms are the same box (`end_same`).

## Limits and follow-ups

- No new dispatch. The WebKit cells with fewer than 3 VMs are reported thin with n. Harness stalls are named failures
  owned by macos-vm-evidence; the run that finished as r2 of the flag was a rerun.
- **Follow-up: a WebKit end-dwell lane** that stays at the page end for the morph and records those frames, so the
  const-bounds WebKit verdict is about the frames where the flag acts. Until then the ledger WebKit cell says "no-win,
  not observed".
- **Follow-up (Chromium, INFERRED):** the four per-frame insets are what costs; a variant that drives them without a
  layout input per frame (a transform on the compositor) might keep the constant panel box without the extra dirty objects.
- Local runs are not used anywhere in this note; every number is from the CI runs above.
