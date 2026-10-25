import Lean.Data.Json
import Fw.Parts.MorphPanelOpt
/-!
# morph.panel, variant `rest`: the platform panel's filter per frame
-/
namespace Fw.Parts.MorphPanelRest

open Fw.Engine Fw.Parts.MorphPanelOpt

inductive Kind where
  | off
  | blur
deriving DecidableEq, Repr

def kindOf (r : Rat) : Kind := if (filterV (fade r)).isEmpty then .off else .blur

theorem kindOf_rest {r : Rat} (h : r ≤ 0) : kindOf r = .off := by
  simp [kindOf, filterV_rest h]

theorem kindOf_fade {r : Rat} (h : 0 < r) : kindOf r = .blur ∧ filterV (fade r) = filterO (fade r) := by
  refine ⟨?_, filterV_fade h⟩
  simp [kindOf, filterV_fade h, filterO]

theorem kindOf_off_iff (r : Rat) : kindOf r = .off ↔ r ≤ 0 := by
  constructor
  · intro h
    by_cases hr : r ≤ 0
    · exact hr
    · have := (kindOf_fade (by grind : 0 < r)).1
      rw [h] at this
      cases this
  · exact kindOf_rest

def toggles (rs : List Rat) : Nat := ((rs.zip rs.tail).filter fun p => kindOf p.1 != kindOf p.2).length

theorem toggles_cross {r s : Rat} (hr : r ≤ 0) (hs : 0 < s) : toggles [r, s] = 1 := by
  simp [toggles, kindOf_rest hr, (kindOf_fade hs).1]

theorem toggles_fade {r s : Rat} (hr : 0 < r) (hs : 0 < s) : toggles [r, s] = 0 := by
  simp [toggles, (kindOf_fade hr).1, (kindOf_fade hs).1]

theorem toggles_rest {r s : Rat} (hr : r ≤ 0) (hs : s ≤ 0) : toggles [r, s] = 0 := by
  simp [toggles, kindOf_rest hr, kindOf_rest hs]

theorem toggles_all_rest (rs : List Rat) (h : ∀ r ∈ rs, r ≤ 0) : toggles rs = 0 := by
  unfold toggles
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro p hp
  have h1 := h p.1 (List.of_mem_zip hp).1
  have h2 := h p.2 (List.mem_of_mem_tail (List.of_mem_zip hp).2)
  simp [kindOf_rest h1, kindOf_rest h2]

theorem toggles_all_fade (rs : List Rat) (h : ∀ r ∈ rs, 0 < r) : toggles rs = 0 := by
  unfold toggles
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro p hp
  have h1 := h p.1 (List.of_mem_zip hp).1
  have h2 := h p.2 (List.mem_of_mem_tail (List.of_mem_zip hp).2)
  simp [(kindOf_fade h1).1, (kindOf_fade h2).1]

#guard kindOf 0 == .off && kindOf (1/1000) == .blur && kindOf (275/1000) == .blur && kindOf 1 == .blur
#guard toggles [0, 0, 1/100, 1/2, 1, 1/2, 1/100, 0, 0] == 2
#guard toggles [0, 0, 0] == 0 && toggles [1/10, 1/2, 1] == 0

def morphs : List Int := [0, 1, 2, 10, 100, 200, 275, 300, 549, 550, 551, 1000]

def runs : List (List Int) :=
  [[0, 0, 0], [0, 1, 10, 100, 500, 1000, 500, 10, 1, 0, 0], [1000, 1000], [0, 300, 0, 300, 0], [5, 4, 3, 2, 1, 0]]

def rat (mm : Int) : Rat := (mm : Rat) / 1000

def kindStr : Kind → String
  | .off => "none"
  | .blur => "blur"

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def lines : List String :=
  morphs.map (fun mm =>
    let rad := radius (fade (rat mm))
    line "filter" [("mm", .num (.fromInt mm))]
      (Lean.Json.mkObj [("kind", .str (kindStr (kindOf (rat mm)))), ("radiusNum", .num (.fromInt rad.num)),
        ("radiusDen", .num (.fromNat rad.den))])) ++
  runs.map fun fs =>
    line "run" [("frames", .arr (fs.map fun f => Lean.Json.num (.fromInt f)).toArray)]
      (Lean.Json.mkObj [("kinds", .arr ((fs.map fun f => Lean.Json.str (kindStr (kindOf (rat f)))).toArray)),
        ("toggles", .num (.fromNat (toggles (fs.map rat))))])

def goldenText : String := String.join (lines.map (· ++ "\n"))

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/morph.panel.rest.jsonl`. -/
def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText then
      IO.eprintln s!"morph.panel.rest golden: {path} is up to date ({lines.length} lines)"
      return 0
    IO.eprintln s!"morph.panel.rest golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.MorphPanelRest
