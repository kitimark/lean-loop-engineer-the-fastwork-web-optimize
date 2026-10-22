# morph.panel:const-bounds (render-cost C1): constant panel bounds while the nav morphs

Task `morph-constant-bounds`. Branch `worktree-wf_966da1fd-1d2-1`, CI branch `ci/morph-constant-bounds`. Context:
`10-22-webkit-render-cost.md` (F3, F4, C1, C8).

## Verdict

- PROVED (Lean, `Fw.Parts.MorphConstBounds`): while the nav carries `is-morphing`, the panel box is constant
  (`varBox_const`), the original's grows with the morph (`orig_resizes_h`, `orig_resizes_w`), and every child is painted
  where the original paints it at every scale (`paint_eq`, `visible_iff`, `pivot_same`) with the original width
  (`inset_width_eq`, `backdrop_eq`). At rest no rule applies (`varBox_rest`).
- CONFIRMED (CI): breakpoint gate, both engines, final design: run 39747969466 pass.
- MEASURED, first design only: webkit-sim base 39744614747 against 39744653093, counts overlap (below). The final
  design has no webkit-sim run: the dispatch cap (4) went to the first design, which failed the gate (run 39744563175).
  The command is in the report's `open`.
- Not delivered: IOSurface creations (the Simulator lane does not record them), PathPix pixels (no lane code), the
  tracks and the nav resize.

## Design

The panel (`position: absolute; inset: 0` in the nav) is the nav's box, so the layer that carries its blur filter is
resized on every morph frame (F3). While the nav carries `is-morphing` (`m > 1/1000`, `Nav.morphingCut`) the variant
sets the panel box to `var(--panel-w)` by `var(--panel-h)`, centred on the nav, and gives each direct child an inset
that moves it onto the nav box (`--cb-x`, `--cb-y`: half the difference of the panel and nav boxes):

| child | original | variant |
|---|---|---|
| panel | `inset: 0` | `left: -cb-x`, `top: -cb-y`, final width and height |
| backdrop | `inset: 0 -3%` | `left: cb-x - 0.03 cb-w`, `top: cb-y`, width `1.06 cb-w`, height `cb-h` |
| veil | `inset: 0` | `left: cb-x`, `top: cb-y`, width `cb-w`, height `cb-h` |
| center | `width: 100%` | `width: cb-w` (its 50 % / 50 % anchor is the shared centre) |
| footer | `left: 0; right: 0; bottom: 0` | `left: cb-x`, `right: cb-x`, `bottom: cb-y` |

`--cb-w` and `--cb-h` restate the nav's width and height rules (they read `--hero-pill-w`, `--pill-w`, `--panel-w`,
`--pill-h`, `--panel-h`, `--nav-expand`, `--morph`), so a media override of those variables (the 640 px phone band)
carries over. The nav's `overflow: hidden` clips the larger panel. No element is added.

Why not a wrapper: the first design put the content in a nav-sized frame inside the panel. The breakpoint gate
(`anchors.json` roles with `>` selectors) counted 0 backdrop, veil, center and footer children and read panel insets of
`-4px` and `-412px` at rest, so every cell failed (run 39744563175, merge job). Restricting the geometry to the
morphing state and insetting each child keeps the DOM and the rest state byte-equal.

## Lean

`lean/Fw/Parts/MorphConstBounds.lean` (one axis; the other is the same function with heights). Premises P1 to P4 are
in the module doc: the panel paints nothing itself; positions are exact reals (a fractional offset may snap
differently, at most 1/2 device px, INFERRED); the backing cost follows layer bounds (F3); the nav clips.

| theorem | statement |
|---|---|
| `paint_eq`, `visible_iff` | a point of the nav box is painted at the same place, so the clipped views are equal |
| `nav_origin`, `pivot_same` | the offset puts the nav origin back; the scale pivot is the same point |
| `inset_width_eq`, `backdrop_eq` | a child with insets `l`, `r` keeps width `w - l - r`; the backdrop keeps `1.06 w` |
| `varBox_rest`, `varBox_const` | at or below the cut the box is the original's; above it, constant |
| `orig_resizes_h`, `orig_resizes_w` | the original box grows strictly with the morph |
| `end_same`, `off_nonneg` | at `m = 1` the boxes are equal and the offset is 0; the offset is never negative |
| `colW_mono`, `pitch_scaled_ne` | why the tracks stay out: column widths change with the panel width, and scaling the final layout would scale the 12 px gap, so the pitch differs for `w != w1` |

Golden `packages/contracts/golden/parts/morph-const-bounds.jsonl` (162 rows: 9 viewports on both sides of the 640 px
band, 9 morph values from rest to 1). `lean #guard` ties the file to `boundsJsonl`. TS:
`apps/site/src/parts/morph.panel/const-bounds.golden.test.ts` evaluates the CSS calc strings (nav variables included)
against the rows: boxes, every child inset, and painted positions at the panel scale.

Regen: copy the module without its `include_str` guard into a scratch file, append
`def main : IO Unit := IO.print (Fw.Parts.MorphConstBounds.boundsJsonl ())`, `lake env lean --run`.

## Gate and PathPix

- Breakpoint gate, engines both, flag `morph.panel:const-bounds`: first design run 39744563175 failed (above); final design run 39747969466 pass.
- PathPix: `Fw.Gate.PathPix` has no lane code (its handoff), so no pixel cell was filled. The sampled morph values in the
  golden (`1/1000, 1/20, 1/5, 2/5, 1/2, 4/5, 23/25, 1`) are the cells to fill. By its premises (C5: content that
  translates without snap) a fractional offset caps the grade at Q.

## Measurement (first design)

CI webkit-sim, iOS Simulator 430x775, lag and cost passes, two passes per arm, base run 39744614747 against
`?fw=morph.panel:const-bounds` (wrapper design) run 39744653093. `lag/cli.mjs cost-report` and a count script over
`r1-lag.json`:

- Frame cadence, Composite and Paint per frame, paint records after the tween end: every morph-zone cell overlaps the base.
- Whole-morph-pass records, pass 1 and 2: RecalculateStyles 3004 and 656 (base) against 470 and 422; Layout 1719 and
  401 against 294 and 230; the base passes differ from each other by more than the arms do. rAF deltas over 33 ms:
  45 of 46 and 42 of 53 (base) against 40 of 52 and 38 of 43.
- Composite per frame (open and close pushes): 192569 and 149485 us (base) against 168077 and 173603 us.
- IOSurface creations: the lane records none. Layer sizes between layer-tree reads are in `cost.layersMorph.snaps`; the
  same layers resize in both arms (about 12 per read in the open push), and the panel layer cannot be told apart by id.

Reading: no win on the main thread, as the proof says (children keep their layout inputs, `inset_width_eq`). The saving
sits in the GPU process (F3) and in the F4 tiles, which the Simulator does not show. INFERRED, not measured.

## Measurement (final design): not delivered

The 5th dispatch, webkit-sim run 39751427150 (target=rewrite, lag=true, cost=on, fw=morph.panel:const-bounds, branch tip
b4cd0105), booted the Simulator at 08:59:35Z and then sat in the step `Determinism sessions` with no step output until
GitHub cancelled the job at the 60 min limit (09:55:56Z). No pass completed, no artifact was uploaded, so there are no
final-design numbers. The first-design numbers above stay recorded as a separate row; they belong to the wrapper design
that failed the gate. Cause of the hang: unknown (the job log is not served for a cancelled step; INFERRED a lost page
target, as the lead anticipated). No dispatch is left in this task.

## Limits

- PathPix pixel cells wait for task path-pix-lanes; a fractional offset caps the grade at Q (accepted limit).

- The nav still resizes (C8) and so do the column tracks (`pitch_scaled_ne`).
- The panel layer's blur outset changes while the fade runs (m from 0.08 to 0.8), which may still resize it; WebKit's
  filter-outset path is unread (INFERRED).
- A pointer-events panel (`m > 0.92`) is larger than the nav; the nav's overflow clip decides hits (INFERRED; with the
  language menu open the nav does not clip).
- The reader test of `morph.tween` (`waapi.golden.test.ts`) lists `cb` as a reader of `--morph`; `--morph` inherits in every arm.

## Ledger and preset

Ledger row n=45 `morph.panel-const-bounds` (status partly-proved, webkit unknown). `Fw.Preset.Gen.run []` regenerated
`v2-proved.decisions.jsonl`. Footprint: `apps/site/scripts/part-footprint.mjs --write`.
