/-!
# Usage dedupe (PLAN §8.4 `pnpm fw usage`: transcript tailer, deduped by `message.id`)

One API message spans several transcript lines that share `message.id`, and their `usage`
differs from line to line (MEASURED, observability note §1: 468 of 2,841 messages). Lines can
also arrive twice, partially (a field missing) or out of order. "Last line wins" depends on the
order (an adversarial review found it; see `lastWins` below), so the tailer keeps the **join**:
the per-field maximum, keyed by `message.id`.

The table is a list of `(id, usage)` pairs strictly sorted by id, so equal tables are equal
lists. Proved: `merge` is commutative, associative and idempotent on sorted tables
(`merge_comm`, `merge_assoc`, `merge_idem`); `ingest` does not depend on the order of the lines
(`ingest_perm`), batches can be merged (`ingest_append`), duplicates change nothing
(`ingest_dup`), and the entry of an id is the join of all its lines (`get_ingest`).
-/
namespace Fw.Ops.Usage

/-- The token counts of one usage record; a missing field counts 0. -/
structure Usage where
  input       : Nat := 0
  cacheRead   : Nat := 0
  cacheCreate : Nat := 0
  cache5m     : Nat := 0
  cache1h     : Nat := 0
  output      : Nat := 0
deriving DecidableEq, Repr

/-- The join of two records: the maximum of each field. -/
def Usage.join (a b : Usage) : Usage :=
  ⟨max a.input b.input, max a.cacheRead b.cacheRead, max a.cacheCreate b.cacheCreate,
   max a.cache5m b.cache5m, max a.cache1h b.cache1h, max a.output b.output⟩

/-- The sum of two records, field by field (for totals). -/
def Usage.add (a b : Usage) : Usage :=
  ⟨a.input + b.input, a.cacheRead + b.cacheRead, a.cacheCreate + b.cacheCreate,
   a.cache5m + b.cache5m, a.cache1h + b.cache1h, a.output + b.output⟩

/-- The join is commutative. -/
theorem join_comm (a b : Usage) : a.join b = b.join a := by
  simp only [Usage.join, Nat.max_comm]

/-- The join is associative. -/
theorem join_assoc (a b c : Usage) : (a.join b).join c = a.join (b.join c) := by
  simp only [Usage.join, Nat.max_assoc]

/-- The join is idempotent. -/
theorem join_idem (a : Usage) : a.join a = a := by
  simp [Usage.join]

/-- The all-zero record is the unit of the join (a partial record with missing fields loses
nothing).
-/
theorem join_zero (a : Usage) : a.join {} = a := by
  simp [Usage.join]

/-- The join lifted to optional records: an absent side is the unit. -/
def ojoin : Option Usage → Option Usage → Option Usage
  | none, b => b
  | some a, none => some a
  | some a, some b => some (a.join b)

/-- `ojoin` is commutative. -/
theorem ojoin_comm (x y : Option Usage) : ojoin x y = ojoin y x := by
  cases x <;> cases y <;> simp [ojoin, join_comm]

/-- `ojoin` is associative. -/
theorem ojoin_assoc (x y z : Option Usage) : ojoin (ojoin x y) z = ojoin x (ojoin y z) := by
  cases x <;> cases y <;> cases z <;> simp [ojoin, join_assoc]

/-- `ojoin` is idempotent. -/
theorem ojoin_idem (x : Option Usage) : ojoin x x = x := by
  cases x <;> simp [ojoin, join_idem]

/-- `⊥` is a right unit of `ojoin`. -/
theorem ojoin_none (x : Option Usage) : ojoin x none = x := by
  cases x <;> rfl

/-- A table: `(message.id, usage)` pairs; the tailer keeps it strictly sorted by id. -/
abbrev Table := List (String × Usage)

/-- A table is strictly sorted by id (so each id occurs once). -/
def Sorted (t : Table) : Prop := t.Pairwise fun a b => a.1 < b.1

/-- The entry of an id: the first pair with that id. -/
def get : Table → String → Option Usage
  | [], _ => none
  | (k, u) :: t, j => if k = j then some u else get t j

/-- Insert one record into a sorted table: before the first larger id, or joined into the equal id. -/
def ins (r : String × Usage) : Table → Table
  | [] => [r]
  | (k, u) :: t => if r.1 < k then r :: (k, u) :: t else if r.1 = k then (k, r.2.join u) :: t else (k, u) :: ins r t

/-- Merge the records of `a` into the table `b`, one by one. -/
def merge (a b : Table) : Table := a.foldl (fun t r => ins r t) b

/-- The table of a list of raw records (any order, duplicates allowed). -/
def ingest (l : List (String × Usage)) : Table := merge l []

/-- The join of all records of `l` with id `j` (`⊥` when there is none). -/
def gather : List (String × Usage) → String → Option Usage
  | [], _ => none
  | (k, u) :: l, j => if k = j then ojoin (some u) (gather l j) else gather l j

/-- The field-wise sum of all entries (totals per agent or gate). -/
def total (t : Table) : Usage := t.foldl (fun acc r => acc.add r.2) {}

/-! ## Table lemmas -/

/-- An id below every key of a table has no entry. -/
theorem get_of_lt (t : Table) (j : String) (h : ∀ x ∈ t, j < x.1) : get t j = none := by
  induction t with
  | nil => rfl
  | cons x t ih =>
    obtain ⟨k, u⟩ := x
    have hk : j < k := h _ List.mem_cons_self
    have hne : k ≠ j := fun e => String.lt_irrefl j (e ▸ hk)
    simp only [get, hne, ↓reduceIte]
    exact ih fun y hy => h y (List.mem_cons_of_mem _ hy)

/-- Every key of `ins r t` is the key of `r` or a key of `t`. -/
theorem ins_keys (r : String × Usage) (t : Table) :
    ∀ x ∈ ins r t, x.1 = r.1 ∨ ∃ y ∈ t, x.1 = y.1 := by
  induction t with
  | nil => intro x hx; simp [ins] at hx; exact .inl (by rw [hx])
  | cons y t ih =>
    obtain ⟨k, u⟩ := y
    intro x hx
    simp only [ins] at hx
    split at hx
    · simp only [List.mem_cons] at hx
      rcases hx with h | h | h
      · exact .inl (by rw [h])
      · exact .inr ⟨_, List.mem_cons_self, by rw [h]⟩
      · exact .inr ⟨x, List.mem_cons_of_mem _ h, rfl⟩
    · split at hx
      · simp only [List.mem_cons] at hx
        rcases hx with h | h
        · exact .inr ⟨_, List.mem_cons_self, by rw [h]⟩
        · exact .inr ⟨x, List.mem_cons_of_mem _ h, rfl⟩
      · simp only [List.mem_cons] at hx
        rcases hx with h | h
        · exact .inr ⟨_, List.mem_cons_self, by rw [h]⟩
        · rcases ih x h with h' | ⟨z, hz, h'⟩
          · exact .inl h'
          · exact .inr ⟨z, List.mem_cons_of_mem _ hz, h'⟩

/-- Two distinct strings are ordered one way or the other. -/
theorem str_lt_or_gt (a b : String) (h : a ≠ b) : a < b ∨ b < a := by
  by_cases h1 : a < b
  · exact .inl h1
  · by_cases h2 : b < a
    · exact .inr h2
    · exact absurd (String.le_antisymm (String.not_lt.mp h2) (String.not_lt.mp h1)) h

/-- Inserting keeps a table sorted. -/
theorem ins_sorted (r : String × Usage) (t : Table) (h : Sorted t) : Sorted (ins r t) := by
  induction t with
  | nil => simp [ins, Sorted]
  | cons y t ih =>
    obtain ⟨k, u⟩ := y
    unfold Sorted at h ⊢
    rw [List.pairwise_cons] at h
    simp only [ins]
    split
    · rename_i hlt
      rw [List.pairwise_cons]
      refine ⟨?_, List.pairwise_cons.mpr h⟩
      intro x hx
      simp only [List.mem_cons] at hx
      rcases hx with hx | hx
      · rw [hx]; exact hlt
      · exact String.lt_trans hlt (h.1 x hx)
    · split
      · exact List.pairwise_cons.mpr ⟨h.1, h.2⟩
      · rename_i hlt heq
        have hgt : k < r.1 := (str_lt_or_gt r.1 k heq).resolve_left hlt
        rw [List.pairwise_cons]
        refine ⟨?_, ih h.2⟩
        intro x hx
        rcases ins_keys r t x hx with e | ⟨z, hz, e⟩
        · rw [e]; exact hgt
        · rw [e]; exact h.1 z hz

/-- The entry of an id after one insert: joined with the inserted record when the ids agree. -/
theorem get_ins (r : String × Usage) (t : Table) (j : String) (h : Sorted t) :
    get (ins r t) j = if r.1 = j then ojoin (some r.2) (get t j) else get t j := by
  induction t with
  | nil => by_cases e : r.1 = j <;> simp [ins, get, e, ojoin]
  | cons y t ih =>
    obtain ⟨k, u⟩ := y
    unfold Sorted at h
    rw [List.pairwise_cons] at h
    simp only [ins]
    split
    · rename_i hlt
      by_cases e : r.1 = j
      · have : get ((k, u) :: t) j = none := by
          apply get_of_lt
          intro x hx
          simp only [List.mem_cons] at hx
          rcases hx with hx | hx
          · rw [hx, ← e]; exact hlt
          · rw [← e]; exact String.lt_trans hlt (h.1 x hx)
        rw [this, show get (r :: (k, u) :: t) j = some r.2 by simp [get, e]]
        simp [e, ojoin]
      · simp [get, e]
    · split
      · rename_i _ heq
        by_cases e : r.1 = j
        · simp [get, ← heq, e, ojoin]
        · have : k ≠ j := fun h' => e (heq.trans h')
          simp [get, e, this]
      · rename_i hlt heq
        by_cases e : k = j
        · have : r.1 ≠ j := fun h' => heq (h'.trans e.symm)
          simp [get, e, this]
        · simp only [get, e, ↓reduceIte]
          exact ih h.2

/-- Merging raw records into a sorted table joins, for each id, the records' join into the entry. -/
theorem get_merge_gather (l : List (String × Usage)) (t : Table) (j : String) (h : Sorted t) :
    get (merge l t) j = ojoin (gather l j) (get t j) := by
  induction l generalizing t with
  | nil => simp [merge, gather, ojoin]
  | cons r l ih =>
    simp only [merge, List.foldl_cons] at ih ⊢
    rw [ih _ (ins_sorted r t h), get_ins r t j h]
    obtain ⟨k, u⟩ := r
    by_cases e : k = j
    · simp only [e, ↓reduceIte, gather]
      rw [← ojoin_assoc, ojoin_comm (gather l j) (some u)]
    · simp [e, gather]

/-- Merging into a sorted table keeps it sorted. -/
theorem merge_sorted (l : List (String × Usage)) (t : Table) (h : Sorted t) : Sorted (merge l t) := by
  induction l generalizing t with
  | nil => exact h
  | cons r l ih => exact ih _ (ins_sorted r t h)

/-- On a sorted table, gathering an id is looking it up. -/
theorem gather_sorted (t : Table) (j : String) (h : Sorted t) : gather t j = get t j := by
  induction t with
  | nil => rfl
  | cons y t ih =>
    obtain ⟨k, u⟩ := y
    unfold Sorted at h
    rw [List.pairwise_cons] at h
    by_cases e : k = j
    · have hn : get t j = none := get_of_lt t j fun x hx => e ▸ h.1 x hx
      simp [gather, get, e, ih h.2, hn, ojoin]
    · simp [gather, get, e, ih h.2]

/-- Merging two sorted tables joins their entries. -/
theorem get_merge (a b : Table) (j : String) (ha : Sorted a) (hb : Sorted b) :
    get (merge a b) j = ojoin (get a j) (get b j) := by
  rw [get_merge_gather a b j hb, gather_sorted a j ha]

/-- Extensionality: two sorted tables with the same entries are the same list. -/
theorem ext : ∀ {t1 t2 : Table}, Sorted t1 → Sorted t2 → (∀ j, get t1 j = get t2 j) → t1 = t2
  | [], [], _, _, _ => rfl
  | [], (k, u) :: t, _, _, h => by have := h k; simp [get] at this
  | (k, u) :: t, [], _, _, h => by have := h k; simp [get] at this
  | (k1, u1) :: t1, (k2, u2) :: t2, h1, h2, h => by
    unfold Sorted at h1 h2
    rw [List.pairwise_cons] at h1 h2
    have below (k : String) (u : Usage) (t : Table) (hs : ∀ x ∈ t, k < x.1) (j : String) (hj : j < k) :
        get ((k, u) :: t) j = none :=
      get_of_lt _ j fun x hx => by
        simp only [List.mem_cons] at hx
        rcases hx with hx | hx
        · rw [hx]; exact hj
        · exact String.lt_trans hj (hs x hx)
    have hk : k1 = k2 := by
      apply Classical.byContradiction
      intro hne
      rcases str_lt_or_gt k1 k2 hne with hlt | hlt
      · have := h k1
        rw [below k2 u2 t2 h2.1 k1 hlt] at this
        simp [get] at this
      · have := h k2
        rw [below k1 u1 t1 h1.1 k2 hlt] at this
        simp [get] at this
    subst hk
    have hu : u1 = u2 := by have := h k1; simpa [get] using this
    subst hu
    have ht : t1 = t2 := ext h1.2 h2.2 fun j => by
      by_cases e : k1 = j
      · rw [get_of_lt t1 j (fun x hx => e ▸ h1.1 x hx), get_of_lt t2 j (fun x hx => e ▸ h2.1 x hx)]
      · have := h j; simpa [get, e] using this
    rw [ht]

/-! ## The join laws on tables -/

/-- Merge is commutative on sorted tables. -/
theorem merge_comm (a b : Table) (ha : Sorted a) (hb : Sorted b) : merge a b = merge b a :=
  ext (merge_sorted a b hb) (merge_sorted b a ha) fun j => by
    rw [get_merge a b j ha hb, get_merge b a j hb ha, ojoin_comm]

/-- Merge is associative on sorted tables. -/
theorem merge_assoc (a b c : Table) (ha : Sorted a) (hb : Sorted b) (hc : Sorted c) :
    merge (merge a b) c = merge a (merge b c) :=
  ext (merge_sorted _ c hc) (merge_sorted a _ (merge_sorted b c hc)) fun j => by
    rw [get_merge _ c j (merge_sorted a b hb) hc, get_merge a b j ha hb,
      get_merge a _ j ha (merge_sorted b c hc), get_merge b c j hb hc, ojoin_assoc]

/-- Merge is idempotent on sorted tables. -/
theorem merge_idem (a : Table) (ha : Sorted a) : merge a a = a :=
  ext (merge_sorted a a ha) ha fun j => by rw [get_merge a a j ha ha, ojoin_idem]

/-! ## Order independence of the raw stream -/

/-- A table built from raw records is sorted. -/
theorem ingest_sorted (l : List (String × Usage)) : Sorted (ingest l) :=
  merge_sorted l [] List.Pairwise.nil

/-- The entry of an id is the join of all records with that id, whatever their order or
repetitions.
-/
theorem get_ingest (l : List (String × Usage)) (j : String) : get (ingest l) j = gather l j := by
  rw [ingest, get_merge_gather l [] j List.Pairwise.nil]
  exact ojoin_none _

/-- Gathering does not depend on the order of the records. -/
theorem gather_perm {l l' : List (String × Usage)} (p : l.Perm l') (j : String) : gather l j = gather l' j := by
  induction p with
  | nil => rfl
  | cons x _ ih => obtain ⟨k, u⟩ := x; simp [gather, ih]
  | swap x y l =>
    obtain ⟨k1, u1⟩ := x
    obtain ⟨k2, u2⟩ := y
    by_cases e1 : k1 = j <;> by_cases e2 : k2 = j <;> simp only [gather, e1, e2, ↓reduceIte]
    rw [← ojoin_assoc, ← ojoin_assoc, ojoin_comm (some u2)]
  | trans _ _ ih1 ih2 => exact ih1.trans ih2

/-- Order independence: any reordering of the lines gives the same table. -/
theorem ingest_perm {l l' : List (String × Usage)} (p : l.Perm l') : ingest l = ingest l' :=
  ext (ingest_sorted l) (ingest_sorted l') fun j => by rw [get_ingest, get_ingest, gather_perm p]

/-- Gathering over a concatenation joins the two parts. -/
theorem gather_append (l1 l2 : List (String × Usage)) (j : String) :
    gather (l1 ++ l2) j = ojoin (gather l1 j) (gather l2 j) := by
  induction l1 with
  | nil => simp [gather, ojoin]
  | cons x l ih =>
    obtain ⟨k, u⟩ := x
    by_cases e : k = j <;> simp [gather, e, ih, ojoin_assoc]

/-- Batches: the table of two batches is the merge of their tables. -/
theorem ingest_append (l1 l2 : List (String × Usage)) :
    ingest (l1 ++ l2) = merge (ingest l1) (ingest l2) :=
  ext (ingest_sorted _) (merge_sorted _ _ (ingest_sorted l2)) fun j => by
    rw [get_ingest, get_merge _ _ j (ingest_sorted l1) (ingest_sorted l2), get_ingest, get_ingest,
      gather_append]

/-- Duplicates change nothing: reading every line twice gives the same table. -/
theorem ingest_dup (l : List (String × Usage)) : ingest (l ++ l) = ingest l := by
  rw [ingest_append, merge_idem _ (ingest_sorted l)]

/-! ## Why not "last line wins" -/

/-- The rejected rule: for each id keep the record of the last line, the survivors in line order. -/
def lastWins (l : List (String × Usage)) : Table :=
  l.foldl (fun t r => ((t.filter (·.1 != r.1)) ++ [r])) []

/-- Two partial lines of one message: output 3, then output 5 (all other fields 0). -/
def exLines : List (String × Usage) := [("m1", { output := 3 }), ("m1", { output := 5 })]

-- last-line-wins depends on the order; the join does not
#guard lastWins exLines != lastWins exLines.reverse
#guard ingest exLines == ingest exLines.reverse
#guard ingest exLines == [("m1", { output := 5 })]
#guard ingest [("b", { input := 1 }), ("a", { output := 2 }), ("b", { cacheRead := 7 })] ==
  [("a", { output := 2 }), ("b", { input := 1, cacheRead := 7 })]
#guard total (ingest [("b", { input := 1 }), ("a", { input := 2 }), ("b", { input := 4 })]) == { input := 6 }

end Fw.Ops.Usage
