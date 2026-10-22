import Lean.Data.Json
import Fw.Parts.Nav
import Fw.Parts.MorphPanel
/-!
# morph.panel, variant `const-bounds`: while the nav morphs, the panel keeps its final size and each child sits on the nav box (MCB)

**Original.** The panel is the nav's box: `width: 100%; height: 100%; inset: 0` inside the nav (css `.start-selling-morph-panel`),
so its box is `navWidth m × navHeight m` and every frame of the morph resizes it. The panel carries a blur filter, so
WebKit backs it with its own layer, and a layer whose bounds change gets new buffers and a full raster
(`research/notes/2026/10-22-webkit-render-cost.md`, F3).

**Variant.** While the nav carries `is-morphing` (`m > 1/1000`, `Nav.morphingCut`) the panel box is the final size
`panelW × panelH`, centred on the nav and clipped by the nav's `overflow: hidden`. Every child of the panel is placed
by an inset that moves it onto the nav box (`off` plus its original inset), so its box, and with it its layout, is the
original's. Nothing is added to the DOM and, at rest (no `is-morphing`), no rule applies. The scale `panelScale m` is
still taken about the panel centre, which is the nav centre in both arms.

Everything is on one axis (the other axis is the same function with heights) in `Rat`.

**Premises** (named in the theorems that need them):
* P1 the panel paints nothing itself (no background, border or shadow; `morph.module.css` `.panel`);
* P2 layout positions are exact reals; a fractional offset can snap to the device grid differently (INFERRED, at most 1/2 device px);
* P3 the engine's backing-store cost follows the bounds of a backed layer (F3), so a constant panel box is a saving only there;
* P4 the nav clips the panel (`overflow: hidden` on `.nav`, which the variant leaves as it is).
-/
namespace Fw.Parts.MorphConstBounds
open Fw.Parts.Nav Fw.Parts.MorphPanel

/-! ## Where a point is painted -/

/-- Scaling `p` about the centre `c` by `s`. -/
def scaleAbout (s c p : Rat) : Rat := s * (p - c) + c

/-- Original: a point `p` of the panel (the nav box `[0, w]`) is painted at the scale about the panel centre `w / 2`. -/
def origPos (w s p : Rat) : Rat := scaleAbout s (w / 2) p

/-- Variant: the panel's origin in nav coordinates, `left: 50%` less half its width `w1`. -/
def panelOrg (w1 w : Rat) : Rat := (w - w1) / 2

/-- Variant: where the nav box starts inside the panel; every child's inset grows by it. -/
def off (w1 w : Rat) : Rat := (w1 - w) / 2

/-- Variant: a point `p` of the nav box, painted at the scale about the panel centre `w1 / 2`, in nav coordinates. -/
def newPos (w1 w s p : Rat) : Rat := panelOrg w1 w + scaleAbout s (w1 / 2) (off w1 w + p)

/-- Same look: every point of the content is painted where the original paints it, for every scale and every final size. -/
theorem paint_eq (w1 w s p : Rat) : newPos w1 w s p = origPos w s p := by
  unfold newPos origPos panelOrg off scaleAbout
  grind

/-- The nav clips both arms to `[0, w]`, so the visible parts are the same set of points. -/
theorem visible_iff (w1 w s p : Rat) :
    (0 ≤ newPos w1 w s p ∧ newPos w1 w s p ≤ w) ↔ (0 ≤ origPos w s p ∧ origPos w s p ≤ w) := by
  rw [paint_eq]

/-- The offset puts the nav box's origin back on the nav origin. -/
theorem nav_origin (w1 w : Rat) : panelOrg w1 w + off w1 w = 0 := by
  unfold panelOrg off; grind

/-- The panel's centre is the nav's centre, so the scale pivot is the same point in both arms. -/
theorem pivot_same (w1 w : Rat) : panelOrg w1 w + w1 / 2 = w / 2 := by
  unfold panelOrg; grind

/-- A child with insets `l` and `r` from the nav box (the original's `left`/`right`; `-3 %` of the width for the backdrop)
gets the insets `off + l` and `off + r` in the panel: its width is the original's. -/
theorem inset_width_eq (w1 w l r : Rat) : w1 - (off w1 w + l) - (off w1 w + r) = w - l - r := by
  unfold off; grind

/-- The backdrop (insets `-3 %` of the width on both sides) keeps its width `1.06 w` and its left edge `3 %` outside the nav box. -/
theorem backdrop_eq (w1 w : Rat) :
    w1 - (off w1 w - 3 / 100 * w) - (off w1 w - 3 / 100 * w) = 53 / 50 * w ∧
      off w1 w - 3 / 100 * w + panelOrg w1 w = -(3 / 100 * w) := by
  unfold off panelOrg; constructor <;> grind

/-! ## Sizes as functions of the morph -/

/-- Original panel box: the nav box (width, height). -/
def origBox (v : Vp) (hp : Bool) (m : Rat) : Rat × Rat := (navWidth v hp m, navHeight v m)

/-- The nav carries `is-morphing` (`Nav.morphingCut`). -/
def morphing (m : Rat) : Bool := decide (morphingCut < m)

/-- Variant panel box: `var(--panel-w)` by `var(--panel-h)` while the nav morphs, else the original's. -/
def varBox (v : Vp) (hp : Bool) (m : Rat) : Rat × Rat := if morphing m then (panelW v, panelH v) else origBox v hp m

/-- At rest and in the width tail after a close (no `is-morphing`) the variant's box is the original's. -/
theorem varBox_rest (v : Vp) (hp : Bool) (m : Rat) (h : m ≤ morphingCut) : varBox v hp m = origBox v hp m := by
  have : morphing m = false := by unfold morphing; simp; grind
  simp [varBox, this]

/-- The variant's panel box is constant over the whole morph. -/
theorem varBox_const (v : Vp) (hp : Bool) (m m' : Rat) (h : morphingCut < m) (h' : morphingCut < m') :
    varBox v hp m = varBox v hp m' := by
  have a : morphing m = true := by unfold morphing; simp; grind
  have b : morphing m' = true := by unfold morphing; simp; grind
  simp [varBox, a, b]

/-- The original panel's height grows strictly with the morph whenever the end is taller than the pill. -/
theorem orig_resizes_h (v : Vp) (hh : pillH v < panelH v) (m m' : Rat) (h : m < m') :
    navHeight v m < navHeight v m' := by
  unfold navHeight
  have : 0 < panelH v - pillH v := by grind
  have := Rat.mul_pos this (show 0 < m' - m by grind)
  grind

/-- The original panel's width grows strictly with the morph whenever the end is wider than the pill. -/
theorem orig_resizes_w (v : Vp) (hp : Bool) (hw : pillW v < panelW v) (m m' : Rat) (h : m < m') :
    navWidth v hp m < navWidth v hp m' := by
  unfold navWidth
  have : 0 < panelW v - pillW v := by grind
  have := Rat.mul_pos this (show 0 < m' - m by grind)
  grind

/-- At the end the two arms have the same box and the offset is zero. -/
theorem end_same (v : Vp) (hp : Bool) :
    varBox v hp 1 = origBox v hp 1 ∧ off (panelW v) (navWidth v hp 1) = 0 := by
  have h := end_box v hp
  constructor
  · have : morphing 1 = true := by unfold morphing morphingCut; simp; grind
    simp [varBox, origBox, this, h.1, h.2.1]
  · unfold off; rw [h.2.1]; grind

/-- The offset is not negative for `m` in `[0, 1]` when the end is not smaller than the pill, so the nav box lies inside the
panel box and no child is placed with a negative inset by the offset. -/
theorem off_nonneg (v : Vp) (hp : Bool) (m : Rat) (h1 : m ≤ 1) (hh : pillH v ≤ panelH v) :
    0 ≤ off (panelW v) (navWidth v hp m) ∧ 0 ≤ off (panelH v) (navHeight v m) := by
  have hw := panel_ge_pill v
  unfold off navWidth navHeight
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  have b := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v by grind) (show 0 ≤ 1 - m by grind)
  constructor <;> grind

/-! ## The columns do not scale (why the tracks stay out) -/

/-- Column width: `n` flex items of the backdrop (`3 %` wider on each side of the panel, so `1.06 w`), `g` apart. -/
def colW (n g w : Rat) : Rat := (w * (53 / 50) - (n - 1) * g) / n

/-- Column pitch: one column and one gap. -/
def pitch (n g w : Rat) : Rat := colW n g w + g

/-- Column width grows with the panel width, so the tracks' bounds change every frame in both arms. -/
theorem colW_mono (n g w w' : Rat) (hn : 0 < n) (h : w < w') : colW n g w < colW n g w' := by
  unfold colW
  have hi : 0 < n⁻¹ := Rat.inv_pos.mpr hn
  rw [Rat.div_def, Rat.div_def]
  have := Rat.mul_pos (show 0 < w' * (53 / 50) - w * (53 / 50) by grind) hi
  grind

/-- Scaling the final layout (every length by `w / w1`) leaves the gap `g` scaled too; the original keeps it. So the
pitch of a scaled final layout differs from the original's as soon as `g ≠ 0` and `w ≠ w1`: constant track bounds are not
the same look. -/
theorem pitch_scaled_ne (n g w w1 : Rat) (hn : 0 < n) (hg : g ≠ 0) (hw1 : 0 < w1) (hne : w ≠ w1) :
    pitch n g w ≠ pitch n g w1 * (w / w1) := by
  intro h
  unfold pitch colW at h
  rw [Rat.div_def, Rat.div_def, Rat.div_def] at h
  have e1 : n * n⁻¹ = 1 := Rat.mul_inv_cancel _ (by grind)
  have e2 : w1 * w1⁻¹ = 1 := Rat.mul_inv_cancel _ (by grind)
  have key : g * (w1 - w) = 0 := by grind
  rcases Rat.mul_eq_zero.mp key with h1 | h1
  · exact hg h1
  · exact hne (by grind)

/-! ## Goldens -/

/-- Viewports (width, height) the rows cover: both sides of the 640 px phone band and the desktop caps. -/
def viewports : List (Rat × Rat) :=
  [(375, 667), (390, 844), (640, 900), (641, 900), (768, 1024), (1000, 700), (1280, 800), (1440, 900), (1920, 1080)]

/-- Morph values the rows cover (the first is at rest, where no rule applies); the same-look cells use these. -/
def samples : List Rat := [0, 1 / 1000, 1 / 20, 1 / 5, 2 / 5, 1 / 2, 4 / 5, 23 / 25, 1]

open Lean in
private def jrat (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

open Lean in
/-- Rows `box`: the boxes, offsets and child insets of both arms at one viewport and morph value. -/
def boxRows (_ : Unit := ()) : List String :=
  viewports.flatMap fun (w, h) => samples.map fun m =>
    let v : Vp := ⟨w, h⟩
    let nw := navWidth v false m
    let nh := navHeight v m
    (Json.mkObj [("kind", .str "box"), ("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("morphing", .bool (morphing m)),
      ("navW", jrat nw), ("navH", jrat nh), ("varW", jrat (varBox v false m).1), ("varH", jrat (varBox v false m).2),
      ("newW", jrat (panelW v)), ("newH", jrat (panelH v)),
      ("orgX", jrat (panelOrg (panelW v) nw)), ("orgY", jrat (panelOrg (panelH v) nh)),
      ("offX", jrat (off (panelW v) nw)), ("offY", jrat (off (panelH v) nh)),
      ("bdLeft", jrat (off (panelW v) nw - 3 / 100 * nw)), ("bdW", jrat (53 / 50 * nw))]).compress

open Lean in
/-- Rows `paint`: where the content's left, centre and right edges are painted by both arms, at the panel scale. -/
def paintRows (_ : Unit := ()) : List String :=
  viewports.flatMap fun (w, h) => samples.map fun m =>
    let v : Vp := ⟨w, h⟩
    let nw := navWidth v false m
    let pts : List Rat := [0, nw / 2, nw]
    (Json.mkObj [("kind", .str "paint"), ("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("scale", jrat (panelScale m)),
      ("orig", Json.arr (pts.map fun p => jrat (origPos nw (panelScale m) p)).toArray),
      ("new", Json.arr (pts.map fun p => jrat (newPos (panelW v) nw (panelScale m) p)).toArray)]).compress

/-- The contents of `packages/contracts/golden/parts/morph-const-bounds.jsonl`. -/
def boundsJsonl (_ : Unit := ()) : String := String.join ((boxRows () ++ paintRows ()).map (· ++ "\n"))

#guard ((paintRows ()).length, (boxRows ()).length) == (81, 81)

#guard boundsJsonl () == include_str "../../../packages/contracts/golden/parts/morph-const-bounds.jsonl"

end Fw.Parts.MorphConstBounds
