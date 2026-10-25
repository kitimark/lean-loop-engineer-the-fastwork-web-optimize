import Lean.Data.Json
import Fw.Parts.MorphPanelOpt
/-!
# morph.panel, variant `rest`: the platform panel's filter per frame
Reuses `Fw.Parts.MorphPanelOpt` (`filterV`, `filterO`, `rest_iff`, `rest_visSame_E`, `cr_rest_le`, `wk_rest_le`,
`wk_toggle_eqv`, `cr_toggle_not_le`); this module adds only the per-frame decision the site writes and a run-level count of
its flips. Note: `research/notes/2026/10-2x-panel-rest-n11.md`.

* `kindOf r`: `off` (CSS `filter: none`) exactly when `filterV (fade r)` is empty, else `blur` with the original's radius.
* `kindOf_off_iff`, `kindOf_rest`, `kindOf_fade`: the two branches, each proved on its own.
* `toggles`: the number of adjacent frame pairs whose kind differs; each one is a rest↔fade toggle frame.
-/
namespace Fw.Parts.MorphPanelRest

open Fw.Engine Fw.Parts.MorphPanelOpt

/-- The two filter states of the platform panel: no filter, or the fade's blur.

The value the variant writes for `filter`. -/
inductive Kind where
  | off
  | blur
deriving DecidableEq, Repr

/-- **The decision per frame**: `off` when the variant's filter list is empty, else `blur`.

What the platform panel's `filter` is at section progress `r`. -/
def kindOf (r : Rat) : Kind := if (filterV (fade r)).isEmpty then .off else .blur

/-- **Rest branch**: at rest the variant writes no filter.

At `r ≤ 0` the decision is `off`. -/
theorem kindOf_rest {r : Rat} (h : r ≤ 0) : kindOf r = .off := by
  simp [kindOf, filterV_rest h]

/-- **Fade branch**: during the fade the variant writes a blur, the original's own.

At `0 < r` the decision is `blur`, and the list is the original's. -/
theorem kindOf_fade {r : Rat} (h : 0 < r) : kindOf r = .blur ∧ filterV (fade r) = filterO (fade r) := by
  refine ⟨?_, filterV_fade h⟩
  simp [kindOf, filterV_fade h, filterO]

/-- The decision is `off` exactly at rest.

`off` if and only if `r ≤ 0`. -/
theorem kindOf_off_iff (r : Rat) : kindOf r = .off ↔ r ≤ 0 := by
  constructor
  · intro h
    by_cases hr : r ≤ 0
    · exact hr
    · have := (kindOf_fade (by grind : 0 < r)).1
      rw [h] at this
      cases this
  · exact kindOf_rest

/-- The number of rest↔fade toggle frames of a run: adjacent frame pairs whose decisions differ.

How often the variant flips the panel's filter. -/
def toggles (rs : List Rat) : Nat := ((rs.zip rs.tail).filter fun p => kindOf p.1 != kindOf p.2).length

/-- A pair that crosses from rest into the fade is one toggle.

The first frame past rest flips the filter once. -/
theorem toggles_cross {r s : Rat} (hr : r ≤ 0) (hs : 0 < s) : toggles [r, s] = 1 := by
  simp [toggles, kindOf_rest hr, (kindOf_fade hs).1]

/-- A pair inside the fade is no toggle.

Two fade frames keep the blur. -/
theorem toggles_fade {r s : Rat} (hr : 0 < r) (hs : 0 < s) : toggles [r, s] = 0 := by
  simp [toggles, (kindOf_fade hr).1, (kindOf_fade hs).1]

/-- A pair at rest is no toggle.

Two rest frames keep no filter. -/
theorem toggles_rest {r s : Rat} (hr : r ≤ 0) (hs : s ≤ 0) : toggles [r, s] = 0 := by
  simp [toggles, kindOf_rest hr, kindOf_rest hs]

/-- A run that stays at rest never toggles.

All frames at rest: no flip. -/
theorem toggles_all_rest (rs : List Rat) (h : ∀ r ∈ rs, r ≤ 0) : toggles rs = 0 := by
  unfold toggles
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro p hp
  have h1 := h p.1 (List.of_mem_zip hp).1
  have h2 := h p.2 (List.mem_of_mem_tail (List.of_mem_zip hp).2)
  simp [kindOf_rest h1, kindOf_rest h2]

/-- A run that stays in the fade never toggles.

All frames in the fade: no flip. -/
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

/-! ## Golden rows -/

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
