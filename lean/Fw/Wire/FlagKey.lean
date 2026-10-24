import Lean.Data.Json
/-!
# The canonical flag-set key

A page is chosen by the set of `part:variant` flags, not by the order the author typed them. The key of
a set is its distinct flags ordered by part, then variant, joined with commas. The site prerender
stores each page under `?fw=<key>`, and every lookup (gate smoke, `fw run`, the console preview) turns
the typed list into the same key before it looks. Golden: `packages/contracts/golden/wire/flag-key.jsonl`,
replayed by `apps/site/test/prerender-keys.test.ts`.
-/
namespace Fw.Wire.FlagKey
open Lean

/-- A flag as `(part, variant)`. -/
abbrev Flag := String × String

/-- Part first, then variant. -/
def leF (a b : Flag) : Bool := decide (a.1 < b.1 ∨ (a.1 = b.1 ∧ a.2 ≤ b.2))

theorem leF_trans (a b c : Flag) (h1 : leF a b = true) (h2 : leF b c = true) : leF a c = true := by
  simp only [leF, decide_eq_true_eq] at *
  rcases h1 with h1 | ⟨e1, h1⟩ <;> rcases h2 with h2 | ⟨e2, h2⟩
  · exact .inl (String.lt_trans h1 h2)
  · exact .inl (e2 ▸ h1)
  · exact .inl (e1 ▸ h2)
  · exact .inr ⟨e1.trans e2, String.le_trans h1 h2⟩

theorem leF_total (a b : Flag) : (leF a b || leF b a) = true := by
  simp only [leF, Bool.or_eq_true, decide_eq_true_eq]
  by_cases h1 : a.1 < b.1
  · exact .inl (.inl h1)
  by_cases h2 : b.1 < a.1
  · exact .inr (.inl h2)
  have e : a.1 = b.1 := String.le_antisymm (String.not_lt.mp h2) (String.not_lt.mp h1)
  rcases String.le_total a.2 b.2 with h | h
  · exact .inl (.inr ⟨e, h⟩)
  · exact .inr (.inr ⟨e.symm, h⟩)

theorem leF_antisymm (a b : Flag) (h1 : leF a b = true) (h2 : leF b a = true) : a = b := by
  simp only [leF, decide_eq_true_eq] at *
  rcases h1 with h1 | ⟨e1, h1⟩ <;> rcases h2 with h2 | ⟨e2, h2⟩
  · exact absurd h1 (String.lt_asymm h2)
  · exact absurd (e2 ▸ h1) (String.lt_irrefl _)
  · exact absurd (e1 ▸ h2) (String.lt_irrefl _)
  · exact Prod.ext e1 (String.le_antisymm h1 h2)

/-- Order by part (stable); equal flags stay adjacent, so the part check can refuse a repeat. -/
def sortFlags (fw : List Flag) : List Flag := fw.mergeSort leF

/-- Each element once (the last occurrence stays). -/
def dd {α : Type} [DecidableEq α] : List α → List α
  | [] => []
  | x :: xs => if x ∈ xs then dd xs else x :: dd xs

theorem mem_dd {α : Type} [DecidableEq α] {x : α} : ∀ {l : List α}, x ∈ dd l ↔ x ∈ l
  | [] => by simp [dd]
  | y :: ys => by
    unfold dd
    by_cases h : y ∈ ys
    · simp only [h, ite_true, mem_dd (l := ys), List.mem_cons]
      constructor
      · exact .inr
      · rintro (rfl | h') <;> simp_all
    · simp only [h, ite_false, List.mem_cons, mem_dd (l := ys)]

theorem nodup_dd {α : Type} [DecidableEq α] : ∀ (l : List α), (dd l).Nodup
  | [] => by simp [dd]
  | y :: ys => by
    unfold dd
    by_cases h : y ∈ ys
    · simp only [h, ite_true]; exact nodup_dd ys
    · simp only [h, ite_false, List.nodup_cons]
      exact ⟨fun hm => h (mem_dd.mp hm), nodup_dd ys⟩

/-- The canonical list of a flag set: distinct flags, ordered. -/
def canon (fw : List Flag) : List Flag := (dd fw).mergeSort leF

theorem perm_canon (fw : List Flag) : (canon fw).Perm (dd fw) := List.mergeSort_perm _ _

/-- The key keeps exactly the flags of the set (it determines the set). -/
theorem mem_canon {x : Flag} {fw : List Flag} : x ∈ canon fw ↔ x ∈ fw :=
  (perm_canon fw).mem_iff.trans mem_dd

theorem nodup_canon (fw : List Flag) : (canon fw).Nodup := (perm_canon fw).nodup_iff.mpr (nodup_dd fw)

theorem pairwise_canon (fw : List Flag) : (canon fw).Pairwise (fun a b => leF a b = true) :=
  List.pairwise_mergeSort leF_trans leF_total _

/-- Two lists of the same set give the same key. -/
theorem canon_eq_of_same_set {a b : List Flag} (h : ∀ x, x ∈ a ↔ x ∈ b) : canon a = canon b := by
  have hp : (canon a).Perm (canon b) :=
    (List.perm_ext_iff_of_nodup (nodup_canon a) (nodup_canon b)).mpr fun x => by
      rw [mem_canon, mem_canon]; exact h x
  exact List.Perm.eq_of_pairwise (fun x y _ _ h1 h2 => leF_antisymm x y h1 h2)
    (pairwise_canon a) (pairwise_canon b) hp

/-- Reading the key back as a list gives the same key; the set read off the key is the set. -/
theorem canon_roundtrip (fw : List Flag) : canon (canon fw) = canon fw ∧ ∀ x, x ∈ canon fw ↔ x ∈ fw :=
  ⟨canon_eq_of_same_set fun _ => mem_canon,
   fun _ => mem_canon⟩


/-- A flag `"part:variant"` with exactly one colon. -/
def parse (s : String) : Option Flag :=
  match s.splitOn ":" with
  | [a, b] => some (a, b)
  | _ => none

/-- A flag as `"part:variant"`. -/
def render (p : Flag) : String := p.1 ++ ":" ++ p.2

/-- The key of a typed flag list: the canonical flags joined with commas; `none` when a flag is malformed. -/
def keyOf (fw : List String) : Option String :=
  (fw.mapM parse).map fun ps => ",".intercalate ((canon ps).map render)

/-- A registry: each flag with the flags it requires. -/
abbrev Reg := List (Flag × List Flag)

/-- Every flag of the composition is in the registry and its required flags are in the composition. -/
def Valid (reg : Reg) (c : List Flag) : Prop :=
  ∀ f ∈ c, ∃ rs, (f, rs) ∈ reg ∧ ∀ r ∈ rs, r ∈ c

/-- Validity depends on the set, not on the order. -/
theorem valid_of_same_set {reg : Reg} {a b : List Flag} (h : ∀ x, x ∈ a ↔ x ∈ b) :
    Valid reg a ↔ Valid reg b := by
  constructor
  · intro v f hf
    obtain ⟨rs, hr, hs⟩ := v f ((h f).mpr hf)
    exact ⟨rs, hr, fun r hr' => (h r).mp (hs r hr')⟩
  · intro v f hf
    obtain ⟨rs, hr, hs⟩ := v f ((h f).mp hf)
    exact ⟨rs, hr, fun r hr' => (h r).mpr (hs r hr')⟩

/-- The pages a prerender stores for a list of requested compositions: one per distinct key. -/
def pages (cs : List (List Flag)) : List (List Flag) := dd (cs.map canon)

/-- A requested composition, typed in any order, finds exactly one page under its key. -/
theorem exactly_one_page {cs : List (List Flag)} {c c' : List Flag} (hc : c ∈ cs)
    (h : ∀ x, x ∈ c' ↔ x ∈ c) : (pages cs).count (canon c') = 1 := by
  unfold pages
  have hm : canon c' ∈ dd (cs.map canon) :=
    mem_dd.mpr (List.mem_map.mpr ⟨c, hc, (canon_eq_of_same_set h).symm⟩)
  rw [(nodup_dd _).count]
  simp [hm]

/-- Each flag with what it requires: the compositions the prerender enumerates. -/
def enumerated (reg : Reg) : List (List Flag) := reg.map fun e => e.1 :: e.2

/-- The registry names the requirements of every required flag among the composition. -/
def Closed (reg : Reg) : Prop :=
  ∀ e ∈ reg, ∀ r ∈ e.2, ∃ rs, (r, rs) ∈ reg ∧ ∀ r' ∈ rs, r' = e.1 ∨ r' ∈ e.2

/-- Every enumerated composition of a closed registry is valid. -/
theorem enumerated_valid {reg : Reg} (hc : Closed reg) : ∀ c ∈ enumerated reg, Valid reg c := by
  intro c hm f hf
  obtain ⟨e, he, rfl⟩ := List.mem_map.mp hm
  rcases List.mem_cons.mp hf with rfl | hr
  · exact ⟨e.2, he, fun r hr => List.mem_cons_of_mem _ hr⟩
  · obtain ⟨rs, hrs, hsub⟩ := hc e he f hr
    exact ⟨rs, hrs, fun r' hr' => by
      rcases hsub r' hr' with rfl | h
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ h⟩

/-- A registry-valid composition of an enumerated one, in any order, is valid and has exactly one prerendered page. -/
theorem enumerated_one_page {reg : Reg} (hc : Closed reg) {c c' : List Flag} (hm : c ∈ enumerated reg)
    (h : ∀ x, x ∈ c' ↔ x ∈ c) :
    Valid reg c' ∧ (pages (enumerated reg)).count (canon c') = 1 :=
  ⟨(valid_of_same_set h).mpr (enumerated_valid hc c hm), exactly_one_page hm h⟩


/-- Typed lists and their keys (`null` = refused). -/
def cases : List (List String) :=
  [[], ["morph.countdown:strip", "hero.countdown:strip"], ["hero.countdown:strip", "morph.countdown:strip"],
   ["a:x", "a:x"], ["a:x", "a.b:y"], ["a.b:y", "a:x"], ["a:y", "a:x"], ["p:v@mui", "o:w"],
   ["nocolon"], ["a:b:c", "d:e"]]

def row (fw : List String) : String :=
  (Json.mkObj [("in", Json.arr (fw.map Json.str).toArray),
    ("key", match keyOf fw with | none => Json.null | some k => Json.str k)]).compress

def goldenLines (_ : Unit) : List String := cases.map row

def jsonl (_ : Unit) : String := String.join ((goldenLines ()).map (· ++ "\n"))

#guard jsonl () == include_str "../../../packages/contracts/golden/wire/flag-key.jsonl"

end Fw.Wire.FlagKey
