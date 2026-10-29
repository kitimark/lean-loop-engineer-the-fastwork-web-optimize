import Fw.Parts.PlatformGlintHold
/-! # platform.glint:compositor
One fixed gradient layer per dash, moved by a CSS transform whose keyframes are the original's `x1` key values plus 200. -/
namespace Fw.Parts.PlatformGlintCompositor
open Fw.Parts.PlatformGlint
open Fw.Parts.PlatformSweep (frac)
open Fw.Parts.PlatformGlintHold (Attr segLerp segOf x1At_seg vals segFrom)

/-- The six colour stop offsets of the dash gradient (`0%` to `100%`). -/
def stopOffsets : List Rat := [0, 1 / 5, 2 / 5, 3 / 5, 4 / 5, 1]

/-- Left edge of the fixed layer in dash coordinates: the rest `x1` of the left dash. -/
def layerLeft : Rat := -200

/-- Width of the fixed layer: the rest distance `x2 - x1`. -/
def layerWidth : Rat := 120

/-- Where the original puts the gradient stop at offset `o`, `e` ms after the animation began (dash coordinates). -/
def origStop (s : Side) (e o : Rat) : Rat := (sample s e).1 + o * ((sample s e).2 - (sample s e).1)

/-- Translation of the layer at cycle fraction `u`: the CSS keyframes at offsets `k/5` hold `vals x1 + 200`, linear between. -/
def shiftAt (s : Side) (u : Rat) : Rat := segLerp .x1 s (segOf u) (5 * u - segOf u) + 200

/-- Where the compositor variant puts the stop at offset `o`: fixed place in the layer plus the transform. -/
def varStop (s : Side) (e o : Rat) : Rat := layerLeft + o * layerWidth + shiftAt s (cycle e)

#guard shiftAt .left 0 == 0
#guard shiftAt .left (1 / 10) == 200
#guard shiftAt .right (1 / 2) == 200
#guard varStop .left 500 (1 / 5) == origStop .left 500 (1 / 5)

/-- The keyframe value is the original's `x1` plus 200. -/
theorem shiftAt_eq (s : Side) (u : Rat) : shiftAt s u = x1At s u + 200 := by
  unfold shiftAt
  rw [x1At_seg]

/-- **stops_eq.** At every time and for every stop offset, the compositor variant's stop sits where the original's does. -/
theorem stops_eq (s : Side) (e o : Rat) : varStop s e o = origStop s e o := by
  have h := (glint_translate s (cycle e)).1
  have h1 := shiftAt_eq s (cycle e)
  simp only [varStop, origStop, sample, layerLeft, layerWidth, h1]
  grind

/-- Every one of the six stops, at every time. -/
theorem stops_eq_all (s : Side) (e : Rat) : stopOffsets.map (varStop s e) = stopOffsets.map (origStop s e) := by
  apply List.map_congr_left
  intro o _
  exact stops_eq s e o

/-- The layer is periodic with the 5 s cycle. -/
theorem shift_periodic (s : Side) (e : Rat) : shiftAt s (cycle (e + dur)) = shiftAt s (cycle e) := by
  have h := sample_periodic s e
  rw [shiftAt_eq, shiftAt_eq]
  have h' : (sample s (e + dur)).1 = (sample s e).1 := by rw [h]
  simp only [sample] at h'
  rw [h']

/-! ## The animation set -/

/-- What drives a value: a SMIL attribute animation or a CSS transform. -/
inductive Kind | smilAttr | cssTransform
deriving Repr, DecidableEq

/-- Main-thread writes per frame. A SMIL attribute animation writes its attribute on every tick; a CSS transform
animation with linear timing is run by the compositor (premise, tested by the WKTR lane, not proved here). -/
def writesPerFrame : Kind → Nat
  | .smilAttr => 1
  | .cssTransform => 0

/-- The original: per dash an `x1` and an `x2` animation. -/
def faithfulSet : List Kind := [.smilAttr, .smilAttr, .smilAttr, .smilAttr]

/-- The variant: per dash one transform animation. -/
def variantSet : List Kind := [.cssTransform, .cssTransform]

theorem variant_no_smil : ∀ k ∈ variantSet, k ≠ .smilAttr := by decide

theorem variant_no_writes : (variantSet.map writesPerFrame).sum = 0 := by decide

theorem faithful_writes : (faithfulSet.map writesPerFrame).sum = 4 := by decide

end Fw.Parts.PlatformGlintCompositor
