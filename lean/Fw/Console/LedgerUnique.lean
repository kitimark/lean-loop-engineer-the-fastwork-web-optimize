import Lean.Data.Json
namespace Fw.Console.LedgerUnique

def floor : Nat := 26

def bad (ns : List Nat) : List Nat :=
  (ns.eraseDups).filter fun n => floor ≤ n && 1 < ns.count n

def ok (ns : List Nat) : Bool := (bad ns).isEmpty

theorem ok_iff (ns : List Nat) : ok ns = true ↔ ∀ n ∈ ns, floor ≤ n → ns.count n = 1 := by
  unfold ok bad
  rw [List.isEmpty_iff, List.filter_eq_nil_iff]
  constructor
  · intro h n hn hf
    have := h n (List.mem_eraseDups.mpr hn)
    have hc : 0 < ns.count n := List.count_pos_iff.mpr hn
    simp only [hf, decide_true, Bool.true_and, Bool.not_eq_true, decide_eq_false_iff_not] at this
    omega
  · intro h n hn
    have hn' := List.mem_eraseDups.mp hn
    by_cases hf : floor ≤ n
    · simp [h n hn' hf]
    · simp [hf]

theorem exempt_below_floor (n : Nat) (hn : n < floor) : ok [n, n] = true := by
  have : ¬ floor ≤ n := by omega
  simp [ok, bad, this]

theorem dup_refused (a b : List Nat) (n : Nat) (hn : floor ≤ n) : ok (a ++ n :: b ++ [n]) = false := by
  have h : ¬ ∀ m ∈ a ++ n :: b ++ [n], floor ≤ m → (a ++ n :: b ++ [n]).count m = 1 := by
    intro h
    have := h n (by simp) hn
    simp [List.count_append, List.count_cons_self] at this
    omega
  cases hk : ok (a ++ n :: b ++ [n])
  · rfl
  · exact absurd ((ok_iff _).mp hk) h

theorem append_fresh (ns : List Nat) (n : Nat) (h : ok ns = true) (hn : n ∉ ns) : ok (ns ++ [n]) = true := by
  rw [ok_iff] at h ⊢
  intro m hm hf
  have hm' : m ∈ ns ∨ m = n := by simpa using hm
  rcases hm' with hm' | rfl
  · have hne : m ≠ n := fun e => hn (e ▸ hm')
    rw [List.count_append, h m hm' hf, List.count_eq_zero.mpr (by simpa using hne)]
  · rw [List.count_append, List.count_eq_zero.mpr hn]; simp

end Fw.Console.LedgerUnique

namespace Fw.Wire.LedgerUnique.Golden
open Lean Fw.Console.LedgerUnique

def cases : List (String × List Nat) := [
  ("empty", []), ("distinct", [26, 27, 28]), ("dup-48", [46, 47, 48, 48, 49]),
  ("legacy-repeat", [6, 6, 6, 9, 9, 26]), ("legacy-and-dup", [6, 6, 30, 31, 30]),
  ("triple", [40, 40, 40]), ("floor-edge", [25, 25, 26, 26]), ("far-apart", [30, 31, 32, 30])]

#guard (cases.map fun (_, ns) => ok ns) = [true, true, false, true, false, false, false, false]

def line (name : String) (ns : List Nat) : String :=
  (Json.mkObj [("name", .str name), ("ns", .arr (ns.map fun n => toJson n).toArray),
    ("bad", .arr ((bad ns).map fun n => toJson n).toArray), ("ok", .bool (ok ns))]).compress

def fileText (_ : Unit := ()) : String := String.join (cases.map fun (n, ns) => line n ns ++ "\n")

def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "console" / "ledger-unique.jsonl"
  if write then
    IO.FS.writeFile p fileText
    IO.println s!"ledger-unique golden: {cases.length} cases written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != fileText then
    IO.println s!"ledger-unique golden: {p} is stale (regenerate: cd lean && lake test -- --write-ledger-unique-golden)"
    return 1
  IO.println s!"ledger-unique golden: {cases.length} cases, 0 stale"
  return 0

end Fw.Wire.LedgerUnique.Golden
