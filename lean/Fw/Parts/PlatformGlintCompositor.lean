import Fw.Parts.PlatformGlintHold
namespace Fw.Parts.PlatformGlintCompositor
open Fw.Parts.PlatformGlint
open Fw.Parts.PlatformSweep (frac)
open Fw.Parts.PlatformGlintHold (Attr segLerp segOf x1At_seg vals segFrom)

def stopOffsets : List Rat := [0, 1 / 5, 2 / 5, 3 / 5, 4 / 5, 1]

def layerLeft : Rat := -200

def layerWidth : Rat := 120

def origStop (s : Side) (e o : Rat) : Rat := (sample s e).1 + o * ((sample s e).2 - (sample s e).1)

def shiftAt (s : Side) (u : Rat) : Rat := segLerp .x1 s (segOf u) (5 * u - segOf u) + 200

def varStop (s : Side) (e o : Rat) : Rat := layerLeft + o * layerWidth + shiftAt s (cycle e)

#guard shiftAt .left 0 == 0
#guard shiftAt .left (1 / 10) == 200
#guard shiftAt .right (1 / 2) == 200
#guard varStop .left 500 (1 / 5) == origStop .left 500 (1 / 5)

theorem shiftAt_eq (s : Side) (u : Rat) : shiftAt s u = x1At s u + 200 := by
  unfold shiftAt
  rw [x1At_seg]

theorem stops_eq (s : Side) (e o : Rat) : varStop s e o = origStop s e o := by
  have h := (glint_translate s (cycle e)).1
  have h1 := shiftAt_eq s (cycle e)
  simp only [varStop, origStop, sample, layerLeft, layerWidth, h1]
  grind

theorem stops_eq_all (s : Side) (e : Rat) : stopOffsets.map (varStop s e) = stopOffsets.map (origStop s e) := by
  apply List.map_congr_left
  intro o _
  exact stops_eq s e o

theorem shift_periodic (s : Side) (e : Rat) : shiftAt s (cycle (e + dur)) = shiftAt s (cycle e) := by
  have h := sample_periodic s e
  rw [shiftAt_eq, shiftAt_eq]
  have h' : (sample s (e + dur)).1 = (sample s e).1 := by rw [h]
  simp only [sample] at h'
  rw [h']

inductive Kind | smilAttr | cssTransform
deriving Repr, DecidableEq

def writesPerFrame : Kind → Nat
  | .smilAttr => 1
  | .cssTransform => 0

def faithfulSet : List Kind := [.smilAttr, .smilAttr, .smilAttr, .smilAttr]

def variantSet : List Kind := [.cssTransform, .cssTransform]

theorem variant_no_smil : ∀ k ∈ variantSet, k ≠ .smilAttr := by decide

theorem variant_no_writes : (variantSet.map writesPerFrame).sum = 0 := by decide

theorem faithful_writes : (faithfulSet.map writesPerFrame).sum = 4 := by decide

end Fw.Parts.PlatformGlintCompositor
