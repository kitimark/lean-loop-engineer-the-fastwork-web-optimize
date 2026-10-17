import Auto.MathDoc
namespace Demo
/-- Raising the threshold never raises the count.
math[77ff]: t ≤ t' ⇒ #{x ∈ X : x > t'} ≤ #{x ∈ X : x > t} -/
theorem countAbove_antitone (t t' : Nat) (xs : List Nat) (h : t ≤ t') :
    (xs.filter (fun x => decide (t' < x))).length ≤ (xs.filter (fun x => decide (t < x))).length := by
  induction xs with
  | nil => simp
  | cons x xs ih => by_cases h1 : t' < x <;> by_cases h2 : t < x <;> simp [h1, h2] <;> omega
end Demo
#math_doc Demo
