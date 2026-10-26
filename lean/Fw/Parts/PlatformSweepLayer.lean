import Fw.Parts.PlatformSweep
/-!
# `platform.sweep:layer-sweep`: the gradient is a layer moved by a transform under a static text mask

The original paints the word with `background-clip: text` and animates `background-position`, so every frame repaints
the text mask and the gradient (`PlatformSweep`). The variant keeps the word's text as a static mask
(`mask-clip: text`) and puts the gradient on a child layer `3w` wide that a `transform: translateX` animation moves.
Chromium and WebKit run a transform animation on the compositor (`animationIsAccelerated`, `compositor_animations.cc`),
and neither runs `background-position` there. Part 1 proves the layer shows the original's colour at every point and
time. Part 2 counts the layers a frame must repaint and proves the text mask is not one of them.

`same_look` covers the colour at each point of the word over time (the gradient position), not the pixels. Measured pixel
difference against the original is in the note and the ledger row; edge and gradient rounding of two paint paths is not
part of this exact model, so the flag is a look change (`visClass` L) for the user's visual review.
-/
namespace Fw.Parts.PlatformSweepLayer
open Fw.Parts.PlatformSweep

/-! ## Part 1: same look -/

/-- The `translateX` keyframe start as a fraction of the layer's own width (`-66.6667%` in the CSS). -/
def fromPct : Rat := 666667 / 1000000

/-- The exact start the original needs: `-2/3` of the layer, which is `-2w` for a layer `3w` wide. -/
def fromExact : Rat := 2 / 3

/-- Where the layer's left edge sits at time `t` for an element `w` px wide.

The keyframes run linearly from `-fromExact * 3w` at 0 % to 0 at 100 %, so the offset is `-2w` times the original's
position fraction. -/
def layerX (w t : Rat) : Rat := -(fromExact * (3 * w)) * (1 - phase t)

/-- The same offset with the CSS's rounded `-66.6667%`. -/
def layerXCss (w t : Rat) : Rat := -(fromPct * (3 * w)) * (1 - phase t)

/-- The layer sits where the original's background sits.

The original's offset is `-2w` times `pos t`; the keyframe computes the same number. -/
theorem layerX_eq (w t : Rat) : layerX w t = -2 * w * pos t := by
  unfold layerX fromExact pos
  grind

/-- **same_look.** At every element fraction and time the moving layer shows the original's colour.

Proved for every positive width: `band_eq_bgpos` with the keyframe offset. -/
theorem same_look (w : Rat) (hw : 0 < w) (v t : Rat) : color (bandU w (layerX w t) v) = shown v t := by
  rw [layerX_eq]
  exact band_eq_bgpos w hw v t

/-- The padded layer box is `3w + 2e` wide (`e` px of padding per side, the image in the content box), so a percent
translate of its own width moves `fromExact * (3w + 2e)`; the keyframe adds `4e/3` px to bring the content box back to
`-2w`. The site uses `e = 6` and `+8px`. -/
theorem pad_start (w e : Rat) : -(fromExact * (3 * w + 2 * e)) + 4 * e / 3 = -2 * w := by
  unfold fromExact
  grind

/-- The layer starts at its keyframe start, `-2w`, like the original's 100 %. -/
theorem layerX_start (w : Rat) : layerX w 0 = -2 * w := by
  rw [layerX_eq, pos_zero]
  grind

/-- The rounded keyframe moves the layer at most `w / 10^6` px from the exact place, in either direction.

For any width up to 1000 px that is under a thousandth of a pixel. -/
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

/-! ## Part 2: the text mask is not repainted -/

/-- A property an animation can change on a layer. -/
inductive Prop' where
  | backgroundPosition
  | transform
deriving DecidableEq, Repr

/-- Whether the engines run an animation of this property on the compositor, without a paint.

Chromium: transform, opacity, filter, backdrop-filter, rotate, scale, translate (`CompositedAnimationRequiresProperties`,
`compositor_animations.cc:193-208@f842f52`); background position is not there. WebKit: `animation-wrapper-acceleration`
is set on transform, translate, scale, rotate, opacity, filter and backdrop-filter and not on background-position
(`CSSProperties.json:12112`, `:7114` @862f17d). CONFIRMED from source, the engines' own tables. -/
def onCompositor : Prop' → Bool
  | .backgroundPosition => false
  | .transform => true

/-- One layer of a word: whether it holds the text mask and which property animates on it, if any. -/
structure Lay where
  textMask : Bool
  anim : Option Prop'
deriving Repr

/-- The layers a frame repaints: those that animate a property the compositor does not take. -/
def repaints (l : Lay) : Bool := match l.anim with
  | some p => !onCompositor p
  | none => false

/-- Text-mask layers repainted in one frame. How many times the glyph mask is drawn again. -/
def textRepaints (ls : List Lay) : Nat := (ls.filter fun l => l.textMask && repaints l).length

/-- The original word: one layer holds the text mask and the animated background. -/
def origWord : List Lay := [⟨true, some .backgroundPosition⟩]

/-- The variant word: a static layer holds the text mask, a child layer holds the gradient and the transform. -/
def layerWord : List Lay := [⟨true, none⟩, ⟨false, some .transform⟩]

/-- `n` words. -/
def page (word : List Lay) (n : Nat) : List Lay := (List.replicate n word).flatten

/-- **orig_repaints.** Every word of the original repaints its text mask every frame. -/
theorem orig_repaints (n : Nat) : textRepaints (page origWord n) = n := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [page, List.replicate_succ, List.flatten_cons] at ih ⊢
    simp [textRepaints, origWord, repaints, onCompositor] at ih ⊢

/-- **layer_no_text_repaint.** No word of the variant repaints its text mask in a frame. -/
theorem layer_no_text_repaint (n : Nat) : textRepaints (page layerWord n) = 0 := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [page, List.replicate_succ, List.flatten_cons] at ih ⊢
    simp [textRepaints, layerWord, repaints, onCompositor] at ih ⊢

/-- Over any number of frames the variant repaints the text mask zero times; the original `n` times a frame. -/
theorem run_work (frames n : Nat) :
    frames * textRepaints (page layerWord n) = 0 ∧ frames * textRepaints (page origWord n) = frames * n := by
  rw [layer_no_text_repaint, orig_repaints]; simp

/-! ## Memory budget -/

/-- Bytes of one gradient layer: `3w` by `h` css px at device ratio `r`, 4 bytes a pixel. -/
def layerBytes (w h r : Nat) : Nat := 3 * w * h * r * r * 4

/-- The four words of the page have one layer each. -/
def pageLayers : Nat := 4

/-- The budget the variant may add: 8 MiB of layer memory. -/
def budgetBytes : Nat := 8 * 1024 * 1024

/-- **memory_ok.** Four words up to 300 px wide and 60 px high at device ratio 3 add at most the budget. -/
theorem memory_ok (w h r : Nat) (hw : w ≤ 300) (hh : h ≤ 60) (hr : r ≤ 3) :
    pageLayers * layerBytes w h r ≤ budgetBytes := by
  unfold pageLayers layerBytes budgetBytes
  have h1 : w * h ≤ 300 * 60 := Nat.mul_le_mul hw hh
  have h2 : r * r ≤ 3 * 3 := Nat.mul_le_mul hr hr
  have h3 : w * h * (r * r) ≤ 300 * 60 * (3 * 3) := Nat.mul_le_mul h1 h2
  have e : 4 * (3 * w * h * r * r * 4) = 48 * (w * h * (r * r)) := by grind
  rw [e]
  omega

end Fw.Parts.PlatformSweepLayer
