import Lean.Data.Json
import Fw.Console.LedgerUnique
namespace Fw.Console.LedgerAlloc
open Fw.Console

def top (ns : List Nat) : Nat := ns.foldr max 0

def explicit (rows : List (Option Nat)) : List Nat := rows.filterMap id

def go : Nat → List (Option Nat) → List Nat
  | _, [] => []
  | next, some n :: r => n :: go next r
  | next, none :: r => next :: go (next + 1) r

def start (mainNs : List Nat) (rows : List (Option Nat)) : Nat := top (mainNs ++ explicit rows) + 1

def assign (mainNs : List Nat) (rows : List (Option Nat)) : List Nat := go (start mainNs rows) rows

theorem le_top {ns : List Nat} {n : Nat} (h : n ∈ ns) : n ≤ top ns := by
  induction ns with
  | nil => simp at h
  | cons a t ih =>
    simp only [top, List.foldr_cons] at *
    rcases List.mem_cons.mp h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

theorem length_go (next : Nat) (rows : List (Option Nat)) : (go next rows).length = rows.length := by
  induction rows generalizing next with
  | nil => rfl
  | cons a r ih => cases a <;> simp [go, ih]

theorem mem_go {m next : Nat} {rows : List (Option Nat)} (h : m ∈ go next rows) : m ∈ explicit rows ∨ next ≤ m := by
  induction rows generalizing next with
  | nil => simp [go] at h
  | cons a r ih =>
    cases a with
    | some n =>
      simp only [go, List.mem_cons] at h
      rcases h with rfl | h
      · left; simp [explicit]
      · rcases ih h with h | h
        · left; simp [explicit] at *; exact Or.inr h
        · right; exact h
    | none =>
      simp only [go, List.mem_cons] at h
      rcases h with rfl | h
      · right; exact Nat.le_refl _
      · rcases ih h with h | h
        · left; simpa [explicit] using h
        · right; omega

theorem go_keeps (next : Nat) (rows : List (Option Nat)) (i n : Nat) (h : rows[i]? = some (some n)) :
    (go next rows)[i]? = some n := by
  induction rows generalizing next i with
  | nil => simp at h
  | cons a r ih =>
    cases i with
    | zero => simp at h; subst h; simp [go]
    | succ i =>
      cases a <;> simp [go] <;> exact ih _ _ (by simpa using h)

theorem assign_keeps (mainNs : List Nat) (rows : List (Option Nat)) (i n : Nat) (h : rows[i]? = some (some n)) :
    (assign mainNs rows)[i]? = some n := go_keeps _ _ _ _ h

theorem assign_length (mainNs : List Nat) (rows : List (Option Nat)) : (assign mainNs rows).length = rows.length :=
  length_go _ _

theorem go_unique (rows : List (Option Nat)) (next : Nat) (hlt : ∀ n ∈ explicit rows, n < next)
    (hok : ∀ n ∈ explicit rows, LedgerUnique.floor ≤ n → (explicit rows).count n = 1) :
    ∀ m ∈ go next rows, LedgerUnique.floor ≤ m → (go next rows).count m = 1 := by
  induction rows generalizing next with
  | nil => simp [go]
  | cons a r ih =>
    cases a with
    | some n =>
      have hn : n ∈ explicit (some n :: r) := by simp [explicit]
      have hnr : (explicit (some n :: r)).count n = 1 ∨ n < LedgerUnique.floor := by
        by_cases hf : LedgerUnique.floor ≤ n
        · exact Or.inl (hok n hn hf)
        · exact Or.inr (by omega)
      have hex : explicit (some n :: r) = n :: explicit r := by simp [explicit]
      intro m hm hf
      have ihr := ih next (fun k hk => hlt k (by rw [hex]; exact List.mem_cons_of_mem _ hk)) (by
        intro k hk hkf
        have := hok k (by rw [hex]; exact List.mem_cons_of_mem _ hk) hkf
        rw [hex, List.count_cons] at this
        have hpos : 0 < (explicit r).count k := List.count_pos_iff.mpr hk
        by_cases hkn : k = n
        · subst hkn; simp at this; omega
        · have hnk : ¬ n = k := fun e => hkn e.symm
          simpa [hnk] using this)
      simp only [go]
      by_cases hmn : m = n
      · subst hmn
        have h0 : (go next r).count m = 0 := by
          rw [List.count_eq_zero]
          intro hin
          rcases mem_go hin with h | h
          · have := hok m hn hf
            rw [hex, List.count_cons] at this
            have hpos : 0 < (explicit r).count m := List.count_pos_iff.mpr h
            simp at this; omega
          · have := hlt m hn; omega
        simp [h0]
      · have hmr : m ∈ go next r := by
          simp only [go, List.mem_cons] at hm
          rcases hm with h | h
          · exact absurd h hmn
          · exact h
        have hnm : ¬ n = m := fun e => hmn e.symm
        simpa [List.count_cons, hnm] using ihr m hmr hf
    | none =>
      have hex : explicit (none :: r) = explicit r := by simp [explicit]
      intro m hm hf
      have ihr := ih (next + 1) (fun k hk => by have := hlt k (by rw [hex]; exact hk); omega)
        (fun k hk hkf => by have := hok k (by rw [hex]; exact hk) hkf; rwa [hex] at this)
      simp only [go]
      by_cases hmn : m = next
      · subst hmn
        have h0 : (go (m + 1) r).count m = 0 := by
          rw [List.count_eq_zero]
          intro hin
          rcases mem_go hin with h | h
          · have := hlt m (by rw [hex]; exact h); omega
          · omega
        simp [h0]
      · have hmr : m ∈ go (next + 1) r := by
          simp only [go, List.mem_cons] at hm
          rcases hm with h | h
          · exact absurd h hmn
          · exact h
        have hnm : ¬ next = m := fun e => hmn e.symm
        simpa [List.count_cons, hnm] using ihr m hmr hf

theorem assign_unique (mainNs : List Nat) (rows : List (Option Nat))
    (h : LedgerUnique.ok (explicit rows) = true) : LedgerUnique.ok (assign mainNs rows) = true := by
  rw [LedgerUnique.ok_iff] at h ⊢
  refine go_unique rows _ ?_ h
  intro n hn
  have : n ≤ top (mainNs ++ explicit rows) := le_top (List.mem_append_right _ hn)
  simp only [start]; omega

theorem new_above (mainNs : List Nat) (rows : List (Option Nat)) (n : Nat) (hn : n ∈ mainNs ++ explicit rows) :
    n < start mainNs rows := by
  have := le_top hn; simp only [start]; omega

theorem branch_check_skips_none (rows : List (Option Nat)) :
    explicit (none :: rows) = explicit rows := by simp [explicit]

theorem start_eq_of_top (a b : List Nat) (rows : List (Option Nat)) (h : top a = top b) :
    assign a rows = assign b rows := by
  have : ∀ l : List Nat, top (l ++ explicit rows) = max (top l) (top (explicit rows)) := by
    intro l; induction l with
    | nil => simp [top]
    | cons x t ih => simp only [List.cons_append, top, List.foldr_cons] at *; rw [ih, Nat.max_assoc]
  simp only [assign, start, this, h]

end Fw.Console.LedgerAlloc

namespace Fw.Wire.LedgerAlloc.Golden
open Lean Fw.Console.LedgerAlloc

def cases : List (String × List Nat × List (Option Nat)) := [
  ("empty", [], []),
  ("one-new", [26, 27, 72], [none]),
  ("two-new-order", [70, 72, 71], [none, none]),
  ("keeps-existing", [26, 27], [some 26, some 27, none]),
  ("mixed", [30, 31, 32], [some 30, none, some 31, none, some 32]),
  ("explicit-above-main", [30], [some 35, none, none]),
  ("legacy-repeat", [6, 6, 9, 26], [some 6, some 6, none]),
  ("main-empty", [], [none, none, none]),
  ("incident-67", [66, 69], [some 66, none, none]),
  ("explicit-dup", [40, 41], [some 41, some 41, none])]

def opt (o : Option Nat) : Json := match o with | some n => toJson n | none => Json.null

def line (c : String × List Nat × List (Option Nat)) : String :=
  let (name, m, rows) := c
  (Json.mkObj [("name", .str name), ("main", .arr (m.map fun n => toJson n).toArray),
    ("rows", .arr (rows.map opt).toArray),
    ("out", .arr ((assign m rows).map fun n => toJson n).toArray),
    ("ok", .bool (Fw.Console.LedgerUnique.ok (assign m rows)))]).compress

def fileText (_ : Unit := ()) : String := String.join (cases.map fun c => line c ++ "\n")

def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "console" / "ledger-alloc.jsonl"
  if write then
    IO.FS.writeFile p fileText
    IO.println s!"ledger-alloc golden: {cases.length} cases written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != fileText then
    IO.println s!"ledger-alloc golden: {p} is stale (regenerate: cd lean && lake test -- --write-ledger-alloc-golden)"
    return 1
  IO.println s!"ledger-alloc golden: {cases.length} cases, 0 stale"
  return 0

end Fw.Wire.LedgerAlloc.Golden
