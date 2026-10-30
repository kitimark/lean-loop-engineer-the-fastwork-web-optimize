import Lean
namespace Fw.Ops.Attrib
open Lean

structure Run where
  commit : String
  flags : List (String × String)
  pass : Bool
deriving Repr, DecidableEq

def get (fs : List (String × String)) (part : String) : Option String :=
  (fs.find? (·.1 == part)).map (·.2)

def delta (a b : List (String × String)) : List String :=
  ((a.map (·.1) ++ b.map (·.1)).eraseDups).filter (fun p => get a p != get b p)

inductive Verdict
  | causedBy (part : String) (failing passing : Option String)
  | noEffect (part : String)
  | notAttributable
deriving Repr, DecidableEq

def direction (a b : Run) (p : String) : Verdict :=
  if a.pass == b.pass then .noEffect p
  else if a.pass then .causedBy p (get b.flags p) (get a.flags p)
  else .causedBy p (get a.flags p) (get b.flags p)

def verdict (a b : Run) : Verdict :=
  if a.commit != b.commit then .notAttributable
  else match delta a.flags b.flags with
    | [p] => direction a b p
    | _ => .notAttributable

theorem same_commit (a b : Run) (h : verdict a b ≠ .notAttributable) : a.commit = b.commit := by
  unfold verdict at h
  by_cases c : (a.commit != b.commit) = true
  · simp [c] at h
  · simpa using c

theorem one_part (a b : Run) (h : verdict a b ≠ .notAttributable) : ∃ p, delta a.flags b.flags = [p] := by
  rcases hd : delta a.flags b.flags with _ | ⟨p, _ | ⟨g, t⟩⟩
  · simp [verdict, hd] at h
  · exact ⟨p, rfl⟩
  · simp [verdict, hd] at h

theorem two_parts_not_attributable (a b : Run) (f g : String)
    (h : delta a.flags b.flags = [f, g]) : verdict a b = .notAttributable := by
  unfold verdict
  simp [h]

theorem zero_parts_not_attributable (a b : Run) (h : delta a.flags b.flags = []) :
    verdict a b = .notAttributable := by
  unfold verdict
  simp [h]

theorem other_commit_not_attributable (a b : Run) (h : a.commit ≠ b.commit) :
    verdict a b = .notAttributable := by
  unfold verdict
  simp [h]

theorem verdict_eq_direction (a b : Run) (p : String) (hc : a.commit = b.commit)
    (h : delta a.flags b.flags = [p]) : verdict a b = direction a b p := by
  unfold verdict
  simp [hc, h]

theorem noEffect_of_same_outcome (a b : Run) (p : String) (hc : a.commit = b.commit)
    (h : delta a.flags b.flags = [p]) (hp : a.pass = b.pass) : verdict a b = .noEffect p := by
  rw [verdict_eq_direction a b p hc h]
  simp [direction, hp]

theorem causedBy_of_fail_first (a b : Run) (p : String) (hc : a.commit = b.commit)
    (h : delta a.flags b.flags = [p]) (ha : a.pass = false) (hb : b.pass = true) :
    verdict a b = .causedBy p (get a.flags p) (get b.flags p) := by
  rw [verdict_eq_direction a b p hc h]
  simp [direction, ha, hb]

theorem causedBy_of_fail_second (a b : Run) (p : String) (hc : a.commit = b.commit)
    (h : delta a.flags b.flags = [p]) (ha : a.pass = true) (hb : b.pass = false) :
    verdict a b = .causedBy p (get b.flags p) (get a.flags p) := by
  rw [verdict_eq_direction a b p hc h]
  simp [direction, ha, hb]

theorem delta_differs (a b : List (String × String)) (p : String) (h : p ∈ delta a b) :
    get a p ≠ get b p := by
  simp [delta] at h
  exact h.2

theorem causedBy_values_differ (a b : Run) (p : String) (fv pv : Option String)
    (h : verdict a b = .causedBy p fv pv) : fv ≠ pv := by
  have hne : verdict a b ≠ .notAttributable := by rw [h]; simp
  obtain ⟨q, hq⟩ := one_part a b hne
  have hc := same_commit a b hne
  rw [verdict_eq_direction a b q hc hq] at h
  have hd := delta_differs a.flags b.flags q (by rw [hq]; simp)
  unfold direction at h
  split at h
  · simp at h
  · split at h
    · simp at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact fun e => hd e.symm
    · simp at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact hd

end Fw.Ops.Attrib
