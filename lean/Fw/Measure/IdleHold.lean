import Lean.Data.Json
import Fw.Parts.MorphIdleNone
/-!
# `IdleHold` of morph.columns idle-none (`apps/site/src/parts/morph.columns/idle.ts`)
-/
namespace Fw.Measure.IdleHold
open Lean Fw.Parts.MorphIdleNone Fw.Parts.HiddenPause

structure Anim where
  target : Option Nat
  time : Option Rat
  deriving Repr, DecidableEq

abbrev Held := List (Nat × Rat)

def lookupH (h : Held) (t : Nat) : Option Rat := (h.find? (·.1 == t)).map (·.2)

def setH (h : Held) (t : Nat) (c : Rat) : Held := (t, c) :: h.filter (·.1 != t)

def keepOne (h : Held) (a : Anim) : Held :=
  match a.target, a.time with
  | some t, some c => setH h t c
  | _, _ => h

def keep (h : Held) (as : List Anim) : Held := as.foldl keepOne h

def restoreOne (h : Held) (a : Anim) : Anim :=
  match a.target with
  | some t => match lookupH h t with
    | some c => { a with time := some c }
    | none => a
  | none => a

def restore (h : Held) (as : List Anim) : List Anim × Held := (as.map (restoreOne h), [])

theorem keepOne_noTarget (h : Held) (c : Option Rat) : keepOne h ⟨none, c⟩ = h := rfl

theorem keepOne_noTime (h : Held) (t : Option Nat) : keepOne h ⟨t, none⟩ = h := by
  cases t <;> rfl

theorem lookup_setH (h : Held) (t : Nat) (c : Rat) : lookupH (setH h t c) t = some c := by
  simp [lookupH, setH]

theorem lookup_setH_ne (h : Held) {t u : Nat} (c : Rat) (hne : u ≠ t) : lookupH (setH h t c) u = lookupH h u := by
  have key : ∀ l : Held, (l.filter (·.1 != t)).find? (·.1 == u) = l.find? (·.1 == u) := by
    intro l
    induction l with
    | nil => rfl
    | cons x xs ih =>
      by_cases hx : x.1 = u
      · have hp : (x.1 != t) = true := by simp [hx, hne]
        rw [List.filter_cons_of_pos (p := fun y : Nat × Rat => y.1 != t) hp, List.find?_cons_of_pos (by simp [hx]),
          List.find?_cons_of_pos (by simp [hx])]
      · by_cases ht : (x.1 != t) = true
        · rw [List.filter_cons_of_pos (p := fun y : Nat × Rat => y.1 != t) ht, List.find?_cons_of_neg (by simp [hx]),
            List.find?_cons_of_neg (by simp [hx]), ih]
        · rw [List.filter_cons_of_neg (p := fun y : Nat × Rat => y.1 != t) ht, List.find?_cons_of_neg (by simp [hx]), ih]
  have h2 : ¬ ((t, c).1 == u) = true := by simp; omega
  unfold lookupH setH
  rw [List.find?_cons_of_neg (p := fun y : Nat × Rat => y.1 == u) h2, key]

theorem restoreOne_hit {h : Held} {t : Nat} {c : Rat} (hl : lookupH h t = some c) (x : Option Rat) :
    restoreOne h ⟨some t, x⟩ = ⟨some t, some c⟩ := by
  simp [restoreOne, hl]

theorem restoreOne_miss {h : Held} {t : Nat} (hl : lookupH h t = none) (x : Option Rat) :
    restoreOne h ⟨some t, x⟩ = ⟨some t, x⟩ := by
  simp [restoreOne, hl]

theorem restoreOne_noTarget (h : Held) (x : Option Rat) : restoreOne h ⟨none, x⟩ = ⟨none, x⟩ := rfl

theorem restore_twice (h : Held) (as bs : List Anim) : restore (restore h as).2 bs = (bs, []) := by
  have : ∀ a : Anim, restoreOne [] a = a := by
    intro a
    cases a with
    | mk t x => cases t <;> simp [restoreOne, lookupH]
  have h' : restoreOne [] = id := funext this
  simp [restore, h']

theorem hold_returns_orig_clock (ℓ0 : Rat) (hist : List (Rat × Rat)) (t : Nat) (restarted : Rat) :
    (restore (keep [] [⟨some t, some (varRun ℓ0 hist).clock⟩]) [⟨some t, some restarted⟩]).1 =
      [⟨some t, some (origClock ℓ0 hist)⟩] := by
  rw [varRun_clock]
  have hl : lookupH (keep [] [⟨some t, some (origClock ℓ0 hist)⟩]) t = some (origClock ℓ0 hist) := by
    simpa [keep, keepOne] using lookup_setH [] t (origClock ℓ0 hist)
  simp only [restore, List.map_cons, List.map_nil, restoreOne_hit hl]

inductive Op where
  | keep (as : List Anim)
  | restore (as : List Anim)

def runOps : Held → List Op → List (List Anim)
  | _, [] => []
  | h, .keep as :: rest => runOps (keep h as) rest
  | h, .restore as :: rest => (restore h as).1 :: runOps (restore h as).2 rest

private def A (t : Option Nat) (c : Option Int) : Anim := ⟨t, c.map fun (x : Int) => (x : Rat)⟩

private def animJson (a : Anim) : Json :=
  Json.arr #[a.target.map toJson |>.getD Json.null, a.time.map (fun q => toJson q.floor) |>.getD Json.null]

private def opJson : Op → Json
  | .keep as => Json.mkObj [("op", "keep"), ("anims", Json.arr (as.map animJson).toArray)]
  | .restore as => Json.mkObj [("op", "restore"), ("anims", Json.arr (as.map animJson).toArray)]

private def cases : List (List Op) :=
  [[.keep [A (some 1) (some 100), A (some 2) (some 250)], .restore [A (some 1) (some 0), A (some 2) (some 0)]],
   [.keep [A none (some 5), A (some 3) none, A (some 4) (some 40)], .restore [A none (some 9), A (some 3) (some 9), A (some 4) (some 0)]],
   [.restore [A (some 1) (some 7), A none none]],
   [.keep [A (some 1) (some 100)], .restore [A (some 1) (some 0)], .restore [A (some 1) (some 8)]],
   [.keep [A (some 1) (some 100)], .keep [A (some 1) (some 300), A (some 2) (some 0)], .restore [A (some 1) (some 0), A (some 2) (some 9)]],
   [.keep [A (some 1) (some 100)], .restore [A (some 3) (some 5)], .restore [A (some 1) (some 7)]],
   [.keep [A (some 1) (some 16)], .restore [A (some 1) (some 0)], .keep [A (some 1) (some 48), A (some 2) (some 48)], .restore [A (some 2) (some 0), A (some 1) (some 0)]]]

def goldenLines : List String :=
  cases.map fun ops =>
    (Json.mkObj [("kind", "idleHold"), ("ops", Json.arr (ops.map opJson).toArray),
      ("out", Json.arr ((runOps [] ops).map fun as => Json.arr (as.map animJson).toArray).toArray)]).compress

end Fw.Measure.IdleHold
