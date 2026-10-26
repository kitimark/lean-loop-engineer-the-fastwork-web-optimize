import Fw.Parts.PlatformSweep
/-!
# `platform.sweep:layer-sweep`: gradient on a transform-moved layer under a static text mask
-/
namespace Fw.Parts.PlatformSweepLayer
open Fw.Parts.PlatformSweep

def fromPct : Rat := 666667 / 1000000

def fromExact : Rat := 2 / 3

def layerX (w t : Rat) : Rat := -(fromExact * (3 * w)) * (1 - phase t)

def layerXCss (w t : Rat) : Rat := -(fromPct * (3 * w)) * (1 - phase t)

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

def layerBytes (w h r : Nat) : Nat := 3 * w * h * r * r * 4

def pageLayers : Nat := 4

def budgetBytes : Nat := 8 * 1024 * 1024

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
