import Fw.Parts.PlatformSweep
/-!
# `platform.sweep:layer-sweep`: gradient on a transform-moved layer under a static text mask
-/
namespace Fw.Parts.PlatformSweepLayer
open Fw.Parts.PlatformSweep

/-- The keyframe start as a fraction of the layer width (`-33.33333333%` of the `6w` layer). -/
def fromPct : Rat := 33333333 / 100000000

/-- The exact start: a third of the `6w` layer is `2w`. -/
def fromExact : Rat := 1 / 3

def layerX (w t : Rat) : Rat := -(fromExact * (6 * w)) * (1 - phase t)

def layerXCss (w t : Rat) : Rat := -(fromPct * (6 * w)) * (1 - phase t)

theorem layerX_eq (w t : Rat) : layerX w t = -2 * w * pos t := by
  unfold layerX fromExact pos
  grind

theorem same_look (w : Rat) (hw : 0 < w) (v t : Rat) : color (bandU w (layerX w t) v) = shown v t := by
  rw [layerX_eq]
  exact band_eq_bgpos w hw v t

theorem layerX_start (w : Rat) : layerX w 0 = -2 * w := by
  rw [layerX_eq, pos_zero]
  grind

theorem css_close (w t : Rat) (hw : 0 ≤ w) :
    layerXCss w t - layerX w t ≤ w / 1000000 ∧ layerX w t - layerXCss w t ≤ w / 1000000 := by
  have h := frac_mem (t / period)
  have hp : phase t = frac (t / period) := rfl
  have h0 : 0 ≤ 1 - phase t := by rw [hp]; grind
  have h1 : 1 - phase t ≤ 1 := by rw [hp]; grind
  have hq0 : 0 ≤ w * (1 - phase t) := Rat.mul_nonneg hw h0
  have hq1 : w * (1 - phase t) ≤ w := by
    have := Rat.mul_le_mul_of_nonneg_left h1 hw
    grind
  unfold layerXCss layerX fromExact fromPct
  grind

inductive Prop' where
  | backgroundPosition
  | transform
deriving DecidableEq, Repr

-- Chromium compositor_animations.cc:193-208@f842f52 (transform listed, background-position not); WebKit CSSProperties.json:12112,:7114@862f17d
def onCompositor : Prop' → Bool
  | .backgroundPosition => false
  | .transform => true

structure Lay where
  textMask : Bool
  anim : Option Prop'
deriving Repr

def repaints (l : Lay) : Bool := match l.anim with
  | some p => !onCompositor p
  | none => false

def textRepaints (ls : List Lay) : Nat := (ls.filter fun l => l.textMask && repaints l).length

def origWord : List Lay := [⟨true, some .backgroundPosition⟩]

def layerWord : List Lay := [⟨true, none⟩, ⟨false, some .transform⟩]

def page (word : List Lay) (n : Nat) : List Lay := (List.replicate n word).flatten

theorem orig_repaints (n : Nat) : textRepaints (page origWord n) = n := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [page, List.replicate_succ, List.flatten_cons] at ih ⊢
    simp [textRepaints, origWord, repaints, onCompositor] at ih ⊢

theorem layer_no_text_repaint (n : Nat) : textRepaints (page layerWord n) = 0 := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [page, List.replicate_succ, List.flatten_cons] at ih ⊢
    simp [textRepaints, layerWord, repaints, onCompositor] at ih ⊢

theorem run_work (frames n : Nat) :
    frames * textRepaints (page layerWord n) = 0 ∧ frames * textRepaints (page origWord n) = frames * n := by
  rw [layer_no_text_repaint, orig_repaints]; simp

def layerBytes (w h r : Nat) : Nat := 6 * w * h * r * r * 4

def pageLayers : Nat := 4

def budgetBytes : Nat := 16 * 1024 * 1024

theorem memory_ok (w h r : Nat) (hw : w ≤ 300) (hh : h ≤ 60) (hr : r ≤ 3) :
    pageLayers * layerBytes w h r ≤ budgetBytes := by
  unfold pageLayers layerBytes budgetBytes
  have h1 : w * h ≤ 300 * 60 := Nat.mul_le_mul hw hh
  have h2 : r * r ≤ 3 * 3 := Nat.mul_le_mul hr hr
  have h3 : w * h * (r * r) ≤ 300 * 60 * (3 * 3) := Nat.mul_le_mul h1 h2
  have e : 4 * (6 * w * h * r * r * 4) = 96 * (w * h * (r * r)) := by grind
  rw [e]
  omega

/-! ## Tiling and the snapped width (revision `layer-tiled`)

The original paints a `3w` tile with `background-repeat: repeat`, offset `layerX`. The layer now is two tiles (`6w`)
wide with `background-size: 50% 100%` and `repeat-x`, at the same offset, so it repeats the tile exactly where the
original does (the original's own seam at progress 0 is drawn too). `w` is the device-pixel-snapped word width. -/

/-- Tile fraction under layer-local pixel `y` of the `6w` layer: the first tile, then the second one starting at `3w`. -/
def layerU (w y : Rat) : Rat := if y < 3 * w then y / (3 * w) else (y - 3 * w) / (3 * w)

/-- Tile fraction of the original with `repeat` at element pixel `x` when the background position is `p`: the image
starts at `-2wp` and repeats every `3w`. -/
def repU (w x p : Rat) : Rat := frac ((x + 2 * w * p) / (3 * w))

/-- The fractional part of a value already in `[0, 1)` is itself. -/
theorem frac_of_mem (x : Rat) (h0 : 0 ≤ x) (h1 : x < 1) : frac x = x := by
  have n1 : x.floor < 1 := Rat.floor_lt_iff.mpr (by exact_mod_cast h1)
  have n2 : (0 : Int) ≤ x.floor := by
    have := Rat.floor_monotone h0
    have z : (0 : Rat).floor = 0 := Rat.floor_intCast 0
    omega
  have n0 : x.floor = 0 := by omega
  unfold frac
  rw [n0]
  push_cast
  grind

/-- Two tiles of `repeat-x` read the same tile fraction as a repeating image, on the whole `6w` layer. -/
theorem layerU_eq_frac (w : Rat) (hw : 0 < w) (y : Rat) (h0 : 0 ≤ y) (h1 : y < 6 * w) :
    layerU w y = frac (y / (3 * w)) := by
  have h3 : (0 : Rat) < 3 * w := by grind
  have hne : (3 * w) ≠ 0 := by grind
  have key : ∀ z : Rat, 0 ≤ z → z < 3 * w → 0 ≤ z / (3 * w) ∧ z / (3 * w) < 1 := by
    intro z hz0 hz1
    have hq : z / (3 * w) * (3 * w) = z := by grind
    constructor
    · refine Classical.byContradiction fun hn => ?_
      have : z / (3 * w) * (3 * w) < 0 * (3 * w) := Rat.mul_lt_mul_of_pos_right (by grind) h3
      grind
    · refine Classical.byContradiction fun hn => ?_
      have : 1 * (3 * w) ≤ z / (3 * w) * (3 * w) := Rat.mul_le_mul_of_nonneg_right (by grind) (Rat.le_of_lt h3)
      grind
  unfold layerU
  by_cases h : y < 3 * w
  · simp only [h, ite_true]
    rw [frac_of_mem _ (key y h0 h).1 (key y h0 h).2]
  · simp only [h, ite_false]
    have e : y / (3 * w) = (y - 3 * w) / (3 * w) + 1 := by grind
    have k := key (y - 3 * w) (by grind) (by grind)
    rw [e, frac_add_one, frac_of_mem _ k.1 k.2]

/-- **tiled_same_look.** For every positive width, every element pixel from the left edge to just under `4w` (the box
`[0, w]` and a right overhang of `3w`) and every time, the two-tile layer shows the colour of the original with
`repeat`. -/
theorem tiled_same_look (w : Rat) (hw : 0 < w) (x t : Rat) (h0 : 0 ≤ x) (h1 : x < 4 * w) :
    color (layerU w (x - layerX w t)) = color (repU w x (pos t)) := by
  have hp := pos_mem t
  rw [layerX_eq]
  have e : x - -2 * w * pos t = x + 2 * w * pos t := by grind
  have hy0 : 0 ≤ x + 2 * w * pos t := by
    have := Rat.mul_nonneg (Rat.le_of_lt hw) (Rat.le_of_lt hp.1)
    grind
  have hy1 : x + 2 * w * pos t < 6 * w := by
    have := Rat.mul_le_mul_of_nonneg_left hp.2 (Rat.le_of_lt hw)
    grind
  rw [e, layerU_eq_frac w hw _ hy0 hy1]
  rfl

/-- At progress 0 the original's tile ends on the word's right edge; the layer reads the second tile's first pixel
there, as the original does (the seam the untiled layer lacked). -/
theorem seam_at_start (w : Rat) (hw : 0 < w) : color (layerU w (w - layerX w 0)) = color (repU w w (pos 0)) :=
  tiled_same_look w hw w 0 (Rat.le_of_lt hw) (by grind)

/-! ### Device-pixel snapping of the word width

The engines snap the left and right edge of the box to whole device pixels separately (Chromium
`ToPixelSnappedRect`, `physical_rect.h:228@f842f52`), so a box of width `width` at `left` is `snapPx` device pixels
wide. `ResizeObserver` `devicePixelContentBoxSize` reports that count; where an engine lacks it the same count is
computed from the rect. Rounding is half up; the 1/64 `LayoutUnit` step is not modelled. -/

/-- One edge, snapped: `edge` css px at ratio `dpr` rounded half up to whole device pixels. -/
def snapEdge (dpr edge : Rat) : Int := (edge * dpr + 1 / 2).floor

/-- Snapped width in device pixels of a box at css `left` with css `width`. -/
def snapPx (dpr left width : Rat) : Int := snapEdge dpr (left + width) - snapEdge dpr left

/-- Snapped width in css px (a whole number of device pixels). -/
def snapW (dpr left width : Rat) : Rat := (snapPx dpr left width : Rat) / dpr

/-- **snap_box.** The snapped width is within one device pixel of the true width (strictly). -/
theorem snap_box (dpr left width : Rat) :
    (snapPx dpr left width : Rat) - width * dpr < 1 ∧ width * dpr - (snapPx dpr left width : Rat) < 1 := by
  have a1 := Rat.floor_le (left * dpr + 1 / 2)
  have a2 := Rat.lt_floor_add_one (left * dpr + 1 / 2)
  have b1 := Rat.floor_le ((left + width) * dpr + 1 / 2)
  have b2 := Rat.lt_floor_add_one ((left + width) * dpr + 1 / 2)
  unfold snapPx snapEdge
  push_cast
  have e : (left + width) * dpr = left * dpr + width * dpr := by grind
  rw [e] at b1 b2 ⊢
  push_cast at a1 a2 b1 b2
  grind

/-- The snapped width lies on the device-pixel grid: `snapW * dpr` is the whole count. -/
theorem snapW_grid (dpr left width : Rat) (hd : 0 < dpr) : snapW dpr left width * dpr = (snapPx dpr left width : Rat) := by
  unfold snapW
  have : dpr ≠ 0 := by grind
  grind

/-- A box at least one device pixel wide stays at least one device pixel wide. -/
theorem snapPx_pos (dpr left width : Rat) (h : 1 ≤ width * dpr) : 1 ≤ snapPx dpr left width := by
  have m := Rat.floor_monotone (a := (left * dpr + 1 / 2) + 1) (b := (left + width) * dpr + 1 / 2) (by grind)
  have f1 : ((left * dpr + 1 / 2) + 1).floor = (left * dpr + 1 / 2).floor + 1 := Rat.floor_add_one
  unfold snapPx snapEdge
  omega

/-- The layer in device pixels: six times the snapped count, tiles of three times it (whole numbers). -/
def layerPx (n : Int) : Int := 6 * n

/-- The tile (`background-size: 50%`) is half the layer: a whole number of device pixels. -/
theorem tile_grid (n : Int) : layerPx n / 2 = 3 * n := by unfold layerPx; omega


end Fw.Parts.PlatformSweepLayer
