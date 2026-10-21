import Lean.Data.Json
import Fw.Ops.Wire

/-! JSON field readers and round-trip lemmas shared by `Fw.Wire.Sched`, `Fw.Wire.Obs` and `Fw.Ci.Telemetry`, kept
apart so `Fw.Wire.Obs` does not import `Fw.Wire.Sched` and its `Fw.Measure` and `Fw.Store` cone. -/
namespace Fw.Wire.Sched
open Lean
open Fw.Wire.Ops (opt asStr arrD)

/-- An optional string field (absent or `null` is `none`). -/
def optS (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asStr k v

/-- An optional array of strings (absent is empty). -/
def strsD (j : Json) (k : String) : Except String (List String) := do (← arrD j k).mapM (asStr k)

/-- `Except.ok` then bind is application. -/
theorem ok_bind {ε α β : Type} (a : α) (f : α → Except ε β) : (Except.ok a >>= f) = f a := rfl

/-- Decoding a mapped list element-wise inverts the encoding when each element round-trips. -/
theorem mapM_rt {α : Type} (f : α → Json) (g : Json → Except String α) (h : ∀ a, g (f a) = .ok a) :
    ∀ l : List α, (l.map f).mapM g = .ok l
  | [] => rfl
  | a :: l => by simp [List.mapM_cons, h, mapM_rt f g h l]; rfl

/-- An array field reads back as its list. -/
theorem arrD_arr (j : Json) (k : String) (a : Array Json) (h : j.getObjVal? k = .ok (.arr a)) :
    arrD j k = .ok a.toList := by
  simp [arrD, opt, h]; rfl

/-- A string-array field reads back as its list of strings. -/
theorem strsD_rt (j : Json) (k : String) (l : List String)
    (h : j.getObjVal? k = .ok (.arr (l.toArray.map .str))) : strsD j k = .ok l := by
  simp only [strsD, arrD_arr j k _ h, Array.toList_map]
  exact mapM_rt .str (asStr k) (fun _ => rfl) l

end Fw.Wire.Sched
