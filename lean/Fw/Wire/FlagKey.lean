/-!
# The canonical flag-set key
-/
namespace Fw.Wire.FlagKey

abbrev Flag := String × String

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

def sortFlags (fw : List Flag) : List Flag := fw.mergeSort leF

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

def canon (fw : List Flag) : List Flag := (dd fw).mergeSort leF

theorem perm_canon (fw : List Flag) : (canon fw).Perm (dd fw) := List.mergeSort_perm _ _

theorem mem_canon {x : Flag} {fw : List Flag} : x ∈ canon fw ↔ x ∈ fw :=
  (perm_canon fw).mem_iff.trans mem_dd

theorem nodup_canon (fw : List Flag) : (canon fw).Nodup := (perm_canon fw).nodup_iff.mpr (nodup_dd fw)

theorem pairwise_canon (fw : List Flag) : (canon fw).Pairwise (fun a b => leF a b = true) :=
  List.pairwise_mergeSort leF_trans leF_total _

theorem canon_eq_of_same_set {a b : List Flag} (h : ∀ x, x ∈ a ↔ x ∈ b) : canon a = canon b := by
  have hp : (canon a).Perm (canon b) :=
    (List.perm_ext_iff_of_nodup (nodup_canon a) (nodup_canon b)).mpr fun x => by
      rw [mem_canon, mem_canon]; exact h x
  exact List.Perm.eq_of_pairwise (fun x y _ _ h1 h2 => leF_antisymm x y h1 h2)
    (pairwise_canon a) (pairwise_canon b) hp

theorem canon_roundtrip (fw : List Flag) : canon (canon fw) = canon fw ∧ ∀ x, x ∈ canon fw ↔ x ∈ fw :=
  ⟨canon_eq_of_same_set fun _ => mem_canon,
   fun _ => mem_canon⟩


def parse (s : String) : Option Flag :=
  match s.splitOn ":" with
  | [a, b] => some (a, b)
  | _ => none

def render (p : Flag) : String := p.1 ++ ":" ++ p.2

/-- The key of a typed flag list: the canonical flags joined with commas; `none` when a flag is malformed. -/
def keyOf (fw : List String) : Option String :=
  (fw.mapM parse).map fun ps => ",".intercalate ((canon ps).map render)

abbrev Reg := List (Flag × List Flag)

def Valid (reg : Reg) (c : List Flag) : Prop :=
  ∀ f ∈ c, ∃ rs, (f, rs) ∈ reg ∧ ∀ r ∈ rs, r ∈ c

theorem valid_of_same_set {reg : Reg} {a b : List Flag} (h : ∀ x, x ∈ a ↔ x ∈ b) :
    Valid reg a ↔ Valid reg b := by
  constructor
  · intro v f hf
    obtain ⟨rs, hr, hs⟩ := v f ((h f).mpr hf)
    exact ⟨rs, hr, fun r hr' => (h r).mp (hs r hr')⟩
  · intro v f hf
    obtain ⟨rs, hr, hs⟩ := v f ((h f).mp hf)
    exact ⟨rs, hr, fun r hr' => (h r).mpr (hs r hr')⟩

def pages (cs : List (List Flag)) : List (List Flag) := dd (cs.map canon)

theorem exactly_one_page {cs : List (List Flag)} {c c' : List Flag} (hc : c ∈ cs)
    (h : ∀ x, x ∈ c' ↔ x ∈ c) : (pages cs).count (canon c') = 1 := by
  unfold pages
  have hm : canon c' ∈ dd (cs.map canon) :=
    mem_dd.mpr (List.mem_map.mpr ⟨c, hc, (canon_eq_of_same_set h).symm⟩)
  rw [(nodup_dd _).count]
  simp [hm]

def enumerated (reg : Reg) : List (List Flag) := reg.map fun e => e.1 :: e.2

def Closed (reg : Reg) : Prop :=
  ∀ e ∈ reg, ∀ r ∈ e.2, ∃ rs, (r, rs) ∈ reg ∧ ∀ r' ∈ rs, r' = e.1 ∨ r' ∈ e.2

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

theorem enumerated_one_page {reg : Reg} (hc : Closed reg) {c c' : List Flag} (hm : c ∈ enumerated reg)
    (h : ∀ x, x ∈ c' ↔ x ∈ c) :
    Valid reg c' ∧ (pages (enumerated reg)).count (canon c') = 1 :=
  ⟨(valid_of_same_set h).mpr (enumerated_valid hc c hm), exactly_one_page hm h⟩


end Fw.Wire.FlagKey
