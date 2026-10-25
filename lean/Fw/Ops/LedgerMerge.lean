import Lean.Data.Json
/-!
# Three-way merge of id-keyed ledgers (`scripts/merge-ledger.mjs`)

The JSON ledgers (`docs/team/incidents/ledger.json`, `research/findings/ledger.json`,
`research/mistakes/ledger.json`) are lists of entries keyed by an id. Two branches that each append an entry edit
the same lines at the end of the array, so git's line merge reports a conflict although the entries do not clash
(three `fw land` refusals on 2026-10-18). The git merge driver `scripts/merge-ledger.mjs` merges such lists per id
with the decision below; reading, writing and rendering JSON is glue.

* An entry is a pair `(i, v)` of an id and a value; `ℓ(i, L)` is the first value of id `i` in `L`, or
  `⊥` (absent).
* Per id, the three-way rule `pick3` on `(ℓ(i,B), ℓ(i,O), ℓ(i,T))`: a side that left the base unchanged
  takes the other side's version (an addition, an edit or a deletion), equal versions agree, and the id is a
  conflict iff both sides changed it differently.
* Output order: ours' ids in ours' order, then theirs' ids that ours lacks, in theirs' order. A ledger branch keeps
  the base order and appends, so this is "base order, then ours' additions, then theirs'"; taking ours' order (not
  the base's) is what makes `merge_idempotent` hold exactly.

Theorems: `conflict_iff`, `merge_comm_up_to_order`, `no_conflict_disjoint_ids`, `merge_idempotent` and
`merge_appends` (two branches that append different entries merge to base, ours' entries, theirs' entries: the
2026-10-18 conflict). The key type is generic: ids are strings, and per-task notes are keyed by the pair
(entry, task) (`NoteKey`), so tasks that only add notes never clash (`add_only_merge`, `distinct_notes_merge`,
`distinct_notes_append`; inc-findings-shared-entry). Golden vectors: `packages/contracts/golden/ops/ledger-merge.jsonl`
(`Fw.Wire.LedgerMerge.Golden.run`, checked by `lake test`).
-/

namespace Fw.Ops.LedgerMerge

variable {K V : Type} [DecidableEq K] [DecidableEq V]

/-- The ids of an entry list, in order.

The id column of a ledger. -/
def keys (l : List (K × V)) : List K := l.map (·.1)

/-- The value of the first entry with id `i`, or none.

Looks an id up in a ledger. -/
def look (i : K) : List (K × V) → Option V
  | [] => none
  | (j, v) :: r => if j = i then some v else look i r

/-- The three-way rule for one id: base `b`, ours `o`, theirs `t` (each a value or `⊥` for absent); the result
is `some(r)` with the merged version `r` (again possibly `⊥`, a deletion) or `none` for a
conflict.

A side that left the base unchanged takes the other side; both changed alike agree; both changed differently
conflict. -/
def pick3 (b o t : Option V) : Option (Option V) :=
  if o = b then some t else if t = b then some o else if o = t then some o else none

#guard pick3 (some 1) (some 1) (some 2) = some (some 2)
#guard pick3 (some 1) (some 2) (some 1) = some (some 2)
#guard pick3 (some 1) none (some 1) = some none
#guard pick3 (none : Option Nat) (some 3) none = some (some 3)
#guard pick3 (some 1) (some 2) (some 2) = some (some 2)
#guard pick3 (some 1) (some 2) (some 3) = none
#guard pick3 (some 1) none (some 3) = none
#guard pick3 (none : Option Nat) (some 2) (some 3) = none

/-- The merge's id order: ours' ids, then theirs' ids that ours lacks.

The bracket keeps theirs' order (a filtered list, not a set). -/
def ids (o t : List (K × V)) : List K :=
  keys o ++ (keys t).filter (fun i => decide (i ∉ keys o))

/-- One row of the merge: keep id `i` with value `v`, drop id `i` (deleted), or a clash with the base, ours' and
theirs' versions.

What the driver renders per id. -/
inductive Row (K V : Type) where
  /-- id kept with this value -/
  | keep (i : K) (v : V)
  /-- id deleted -/
  | drop (i : K)
  /-- both sides changed the id differently -/
  | clash (i : K) (b o t : Option V)
  deriving DecidableEq, Repr

/-- The row of id `i`.

Applies the three-way rule to one id. -/
def row (b o t : List (K × V)) (i : K) : Row K V :=
  match pick3 (look i b) (look i o) (look i t) with
  | some (some v) => .keep i v
  | some none => .drop i
  | none => .clash i (look i b) (look i o) (look i t)

/-- All rows, in merge order.

The per-id decisions the driver renders. -/
def rows (b o t : List (K × V)) : List (Row K V) := (ids o t).map (row b o t)

/-- The entry a row keeps, if any.

Kept rows become entries. -/
def Row.entry? : Row K V → Option (K × V)
  | .keep i v => some (i, v)
  | _ => none

/-- Whether a row is a clash.

Any clash fails the merge. -/
def Row.isClash : Row K V → Bool
  | .clash .. => true
  | _ => false

/-- **The ledger merge.** No clash: the kept entries in merge order; a clash: none (git reports a conflict).

The whole decision of `scripts/merge-ledger.mjs`; JSON in and out is glue. -/
def merge (b o t : List (K × V)) : Option (List (K × V)) :=
  let rs := rows b o t
  if rs.any Row.isClash then none else some (rs.filterMap Row.entry?)

-- two appends merge to base, ours', theirs'
#guard merge [("a", 1)] [("a", 1), ("b", 2)] [("a", 1), ("c", 3)] = some [("a", 1), ("b", 2), ("c", 3)]
-- an edit on one side wins, a deletion on one side wins
#guard merge [("a", 1), ("b", 2)] [("a", 5), ("b", 2)] [("b", 2)] = none
#guard merge [("a", 1), ("b", 2)] [("a", 1), ("b", 2)] [("b", 2)] = some [("b", 2)]
#guard merge [("a", 1), ("b", 2)] [("a", 5), ("b", 2)] [("a", 1)] = some [("a", 5)]
-- both edit the same id differently: conflict
#guard merge [("a", 1)] [("a", 2)] [("a", 3)] = none
#guard rows [("a", 1)] [("a", 2)] [("a", 3)] = [Row.clash "a" (some 1) (some 2) (some 3)]
-- the same new id with the same value on both sides: one entry
#guard merge [] [("x", 7)] [("x", 7)] = some [("x", 7)]
#guard merge ([] : List (String × Nat)) [] [] = some []

/-! ## Lookup lemmas -/

omit [DecidableEq V] in
/-- A present lookup names a listed id.

A looked-up value names a listed id. -/
theorem mem_keys_of_look {i : K} : ∀ {l : List (K × V)}, look i l ≠ none → i ∈ keys l
  | [], h => absurd rfl h
  | (j, v) :: r, h => by
    simp only [look] at h
    simp only [keys, List.map_cons, List.mem_cons]
    by_cases hj : j = i
    · exact Or.inl hj.symm
    · simp only [hj, ↓reduceIte] at h; exact Or.inr (mem_keys_of_look h)

omit [DecidableEq V] in
/-- A listed id looks up to a value.

The converse of `mem_keys_of_look`. -/
theorem look_ne_none {i : K} : ∀ {l : List (K × V)}, i ∈ keys l → look i l ≠ none
  | [], h => by simp [keys] at h
  | (j, v) :: r, h => by
    simp only [keys, List.map_cons, List.mem_cons] at h
    simp only [look]
    by_cases hj : j = i
    · simp [hj]
    · simp only [hj, ↓reduceIte]
      exact look_ne_none (h.resolve_left (fun e => hj e.symm))

omit [DecidableEq V] in
/-- Lookup in a concatenation: the first list first.

Used for appended ledgers. -/
theorem look_append (i : K) : ∀ (l m : List (K × V)), look i (l ++ m) = (look i l).or (look i m)
  | [], _ => rfl
  | (j, v) :: r, m => by
    simp only [List.cons_append, look]
    split
    · rfl
    · exact look_append i r m

omit [DecidableEq V] in
/-- An id not listed looks up to nothing.

Contrapositive of `mem_keys_of_look`. -/
theorem look_eq_none {i : K} {l : List (K × V)} (h : i ∉ keys l) : look i l = none :=
  Classical.byContradiction fun hn => h (mem_keys_of_look hn)

omit [DecidableEq V] in
/-- A filter-map over the ids that yields each id's own entry rebuilds the list.

A list with distinct ids is its ids, each with its value. -/
theorem filterMap_keys_look : ∀ (l : List (K × V)) (g : K → Option (K × V)), (keys l).Nodup →
    (∀ i ∈ keys l, g i = (look i l).map (i, ·)) → (keys l).filterMap g = l
  | [], _, _, _ => rfl
  | (a, v) :: r, g, hnd, hg => by
    simp only [keys, List.map_cons, List.nodup_cons] at hnd
    have ha : g a = some (a, v) := by rw [hg a (by simp [keys])]; simp [look]
    have hr : ∀ i ∈ keys r, g i = (look i r).map (i, ·) := by
      intro i hi
      have hne : a ≠ i := fun h => hnd.1 (h ▸ hi)
      rw [hg i (by simp only [keys, List.map_cons, List.mem_cons]; exact Or.inr hi)]
      simp [look, hne]
    simp only [keys, List.map_cons, List.filterMap_cons, ha]
    exact congrArg _ (filterMap_keys_look r g hnd.2 hr)

/-! ## The rule per id -/

/-- `pick3` fails exactly on a two-sided different change.

The conflict condition per id. -/
theorem pick3_eq_none (b o t : Option V) : pick3 b o t = none ↔ o ≠ b ∧ t ≠ b ∧ o ≠ t := by
  unfold pick3
  by_cases h1 : o = b <;> by_cases h2 : t = b <;> by_cases h3 : o = t <;> simp [h1, h2, h3]

/-- `pick3` is symmetric in ours and theirs.

Swapping the sides changes no per-id decision. -/
theorem pick3_comm (b o t : Option V) : pick3 b o t = pick3 b t o := by
  unfold pick3
  by_cases h1 : o = b <;> by_cases h2 : t = b <;> by_cases h3 : o = t <;> simp_all [eq_comm]

omit [DecidableEq V] in
/-- Membership in the merge order.

Every id of either side gets a row. -/
theorem mem_ids (i : K) (o t : List (K × V)) : i ∈ ids o t ↔ i ∈ keys o ∨ i ∈ keys t := by
  unfold ids
  simp only [List.mem_append, List.mem_filter, decide_eq_true_eq]
  by_cases h : i ∈ keys o <;> simp [h]

/-- No clash among the rows iff no id is a two-sided different change.

Ids outside both sides cannot clash, since absent equals absent there. -/
theorem any_clash_iff (b o t : List (K × V)) :
    (rows b o t).any Row.isClash = true ↔
      ∃ i, look i o ≠ look i b ∧ look i t ≠ look i b ∧ look i o ≠ look i t := by
  unfold rows
  simp only [List.any_map, List.any_eq_true, Function.comp]
  constructor
  · rintro ⟨i, _, hc⟩
    refine ⟨i, (pick3_eq_none _ _ _).mp ?_⟩
    unfold row at hc
    split at hc
    · simp [Row.isClash] at hc
    · simp [Row.isClash] at hc
    · assumption
  · rintro ⟨i, h⟩
    have hp := (pick3_eq_none _ _ _).mpr h
    have hi : i ∈ ids o t := by
      rw [mem_ids]
      by_cases ho : look i o = none
      · have : look i t ≠ none := by rw [← ho]; exact Ne.symm h.2.2
        exact Or.inr (mem_keys_of_look this)
      · exact Or.inl (mem_keys_of_look ho)
    refine ⟨i, hi, ?_⟩
    unfold row
    rw [hp]
    rfl

/-! ## The four properties -/

/-- **Conflict iff a two-sided different change.** The merge fails exactly when some id was changed on both sides,
to different versions (an absent version counts: deleting on one side and editing on the other is a conflict, and
adding the same id with different values on both sides is one).

Here `ℓ(i, ·) = ⊥` when `i` is absent. -/
theorem conflict_iff (b o t : List (K × V)) :
    merge b o t = none ↔ ∃ i, look i o ≠ look i b ∧ look i t ≠ look i b ∧ look i o ≠ look i t := by
  rw [← any_clash_iff]
  dsimp only [merge]
  split <;> simp_all

/-- What a successful merge holds: exactly the ids of either side whose rule keeps a value, with that value.

Membership in the merged list, independent of its order. -/
theorem mem_merge {b o t m : List (K × V)} (h : merge b o t = some m) (i : K) (v : V) :
    (i, v) ∈ m ↔ (i ∈ keys o ∨ i ∈ keys t) ∧ pick3 (look i b) (look i o) (look i t) = some (some v) := by
  dsimp only [merge] at h
  split at h
  · cases h
  · cases h
    simp only [rows, List.filterMap_map, List.mem_filterMap, Function.comp, ← mem_ids]
    constructor
    · rintro ⟨j, hj, he⟩
      unfold row at he
      split at he
      · rename_i w hw
        simp only [Row.entry?, Option.some.injEq, Prod.mk.injEq] at he
        obtain ⟨rfl, rfl⟩ := he
        exact ⟨hj, hw⟩
      · simp [Row.entry?] at he
      · simp [Row.entry?] at he
    · rintro ⟨hi, hp⟩
      refine ⟨i, hi, ?_⟩
      unfold row
      rw [hp]
      rfl

/-- **Swapping ours and theirs gives the same entry set.** The merge fails for one order iff it fails for the other,
and when both succeed they hold the same entries (only their order may differ).

The driver's result does not depend on which branch is merged into which, up to order. -/
theorem merge_comm_up_to_order (b o t : List (K × V)) :
    (merge b o t = none ↔ merge b t o = none) ∧
      ∀ m m', merge b o t = some m → merge b t o = some m' → ∀ e, e ∈ m ↔ e ∈ m' := by
  refine ⟨?_, ?_⟩
  · rw [conflict_iff, conflict_iff]
    constructor
    · rintro ⟨i, h1, h2, h3⟩; exact ⟨i, h2, h1, Ne.symm h3⟩
    · rintro ⟨i, h1, h2, h3⟩; exact ⟨i, h2, h1, Ne.symm h3⟩
  · intro m m' hm hm' e
    obtain ⟨i, v⟩ := e
    rw [mem_merge hm, mem_merge hm', pick3_comm, Or.comm]

/-- **Changes on disjoint ids never conflict.** If no id is changed by both sides, the merge succeeds.

The ids ours changed and the ids theirs changed are disjoint sets; a change is an addition, edit or deletion. -/
theorem no_conflict_disjoint_ids (b o t : List (K × V))
    (h : ∀ i, look i o ≠ look i b → look i t = look i b) : ∃ m, merge b o t = some m := by
  cases hm : merge b o t with
  | some m => exact ⟨m, rfl⟩
  | none =>
    obtain ⟨i, h1, h2, _⟩ := (conflict_iff b o t).mp hm
    exact absurd (h i h1) h2

/-- A merge whose rule keeps exactly the entries of `L`, in `L`'s id order, returns `L`.

The common step of `merge_idempotent` and `merge_appends`. -/
theorem merge_eq_of_pick (b o t l : List (K × V)) (hnd : (keys l).Nodup) (hids : ids o t = keys l)
    (hp : ∀ i ∈ keys l, pick3 (look i b) (look i o) (look i t) = some (look i l)) : merge b o t = some l := by
  have hrow : ∀ i ∈ keys l, row b o t i = match look i l with | some v => .keep i v | none => .drop i := by
    intro i hi
    unfold row
    rw [hp i hi]
    cases look i l <;> rfl
  have hnc : (rows b o t).any Row.isClash = false := by
    simp only [rows, hids, List.any_map, List.any_eq_false, Function.comp]
    intro i hi
    rw [hrow i hi]
    cases look i l <;> simp [Row.isClash]
  unfold merge
  simp only [hnc]
  simp only [Bool.false_eq_true, ite_false, rows, hids, List.filterMap_map, Option.some.injEq]
  have hcongr : ∀ i ∈ keys l, (Row.entry? ∘ row b o t) i = (look i l).map (i, ·) := by
    intro i hi
    simp only [Function.comp, hrow i hi]
    cases look i l <;> rfl
  exact filterMap_keys_look l _ hnd hcongr

/-- **Merging a branch with itself gives the branch.** For ours equal to theirs with distinct ids, the merge returns
that list unchanged, whatever the base.

Idempotence: a merge of identical sides is a no-op, order included. -/
theorem merge_idempotent (b x : List (K × V)) (hnd : (keys x).Nodup) : merge b x x = some x := by
  apply merge_eq_of_pick b x x x hnd
  · unfold ids
    have : (keys x).filter (fun i => decide (i ∉ keys x)) = [] := by
      rw [List.filter_eq_nil_iff]; intro i hi; simp [hi]
    rw [this, List.append_nil]
  · intro i _
    unfold pick3
    by_cases h : look i x = look i b <;> simp [h]

/-- **Two branches that append different entries merge cleanly** (the 2026-10-18 incident-ledger conflict): ours
appends `X` to the base `B`, theirs appends `Y`, and all ids are distinct; the merge is `B`, then `X`, then `Y`.

The textual conflict of two appends is no conflict per id. -/
theorem merge_appends (B X Y : List (K × V)) (hnd : (keys (B ++ X ++ Y)).Nodup) :
    merge B (B ++ X) (B ++ Y) = some (B ++ X ++ Y) := by
  simp only [keys, List.map_append, List.nodup_append, List.mem_append] at hnd
  obtain ⟨⟨hB, hX, hBX⟩, hY, hBXY⟩ := hnd
  apply merge_eq_of_pick B (B ++ X) (B ++ Y) (B ++ X ++ Y)
  · simp only [keys, List.map_append, List.nodup_append, List.mem_append]
    exact ⟨⟨hB, hX, hBX⟩, hY, hBXY⟩
  · unfold ids
    simp only [keys, List.map_append, List.filter_append, List.append_assoc]
    congr 2
    have h1 : (B.map (·.1)).filter (fun i => decide (i ∉ B.map (·.1) ++ X.map (·.1))) = [] := by
      rw [List.filter_eq_nil_iff]; intro i hi; simp [hi]
    have h2 : (Y.map (·.1)).filter (fun i => decide (i ∉ B.map (·.1) ++ X.map (·.1))) = Y.map (·.1) := by
      rw [List.filter_eq_self]
      intro i hi
      simp only [List.mem_append, decide_eq_true_eq, not_or]
      exact ⟨fun hb => hBXY i (Or.inl hb) i hi rfl, fun hx => hBXY i (Or.inr hx) i hi rfl⟩
    rw [h1, h2, List.nil_append]
  · intro i hi
    simp only [keys, List.map_append, List.mem_append] at hi
    simp only [look_append]
    rcases hi with (hb | hx) | hy
    · -- a base id: both sides keep the base value
      obtain ⟨v, hv⟩ := Option.ne_none_iff_exists'.mp (look_ne_none (l := B) hb)
      simp [hv, pick3]
    · -- ours' new id: absent in the base and in theirs
      have nb : i ∉ keys B := fun hb => hBX i hb i hx rfl
      have ny : i ∉ keys Y := fun hy => hBXY i (Or.inr hx) i hy rfl
      obtain ⟨v, hv⟩ := Option.ne_none_iff_exists'.mp (look_ne_none (l := X) hx)
      simp [hv, look_eq_none nb, look_eq_none ny, pick3]
    · -- theirs' new id: absent in the base and in ours
      have nb : i ∉ keys B := fun hb => hBXY i (Or.inl hb) i hy rfl
      have nx : i ∉ keys X := fun hx => hBXY i (Or.inr hx) i hy rfl
      simp [look_eq_none nb, look_eq_none nx, pick3]

/-! ## Per-task notes keyed by (entry, task)

A shared string of an entry (a finding's `mechanism`) that several tasks extend is one version of one id: two tasks
that each extend it change that id differently, and `conflict_iff` makes that a conflict (inc-findings-shared-entry,
hero.exit, two hand resolutions). Notes are rows of their own in a separate id-keyed array, keyed by the pair
(entry, task): a task adds its note and never rewrites another task's, so parallel tasks change disjoint keys. The
merge is the same `merge` over the key type `String × String`; `distinct_notes_merge` shows it never clashes for
such branches and keeps every note of both sides. -/

omit [DecidableEq V] in
/-- In a list with distinct ids, a row's id looks up to that row's value.

With distinct ids, membership pins the lookup. -/
theorem look_of_mem {k : K} {v : V} : ∀ {l : List (K × V)}, (keys l).Nodup → (k, v) ∈ l → look k l = some v
  | [], _, h => absurd h List.not_mem_nil
  | (j, w) :: r, hnd, h => by
    simp only [keys, List.map_cons, List.nodup_cons] at hnd
    simp only [look]
    rcases List.mem_cons.mp h with he | hr
    · simp only [Prod.mk.injEq] at he
      obtain ⟨rfl, rfl⟩ := he
      simp
    · have hk : k ∈ keys r := List.mem_map_of_mem (f := (·.1)) hr
      have hne : j ≠ k := fun e => hnd.1 (e ▸ hk)
      simp only [hne, ↓reduceIte]
      exact look_of_mem hnd.2 hr

/-- One side's row survives an add-only merge: if both sides keep every base row unchanged and no id is new on both
sides, the rule keeps ours' value for each row of ours.

The per-id step of `add_only_merge`. -/
theorem pick3_add_only (b o t : List (K × V)) (ho : ∀ k, look k b ≠ none → look k o = look k b)
    (ht : ∀ k, look k b ≠ none → look k t = look k b) (hd : ∀ k, k ∈ keys o → k ∈ keys t → k ∈ keys b)
    (hno : (keys o).Nodup) {k : K} {v : V} (hmem : (k, v) ∈ o) :
    pick3 (look k b) (look k o) (look k t) = some (some v) := by
  have hov : look k o = some v := look_of_mem hno hmem
  by_cases hb : look k b = none
  · have htn : look k t = none := by
      refine Classical.byContradiction fun hn => ?_
      have hkb := hd k (List.mem_map_of_mem (f := (·.1)) hmem) (mem_keys_of_look hn)
      exact look_ne_none hkb hb
    simp [pick3, hb, hov, htn]
  · have h1 := ho k hb
    have h2 := ht k hb
    rw [hov] at h1
    rw [h2, ← h1, hov]
    simp [pick3]

/-- **Add-only branches merge cleanly and keep every row.** If ours and theirs each keep every base row unchanged
(they only add), no id is new on both sides, and each side's ids are distinct, the merge succeeds and holds every row
of ours and every row of theirs.

Position-free: the added rows may sit anywhere in either side's list. -/
theorem add_only_merge (b o t : List (K × V)) (ho : ∀ k, look k b ≠ none → look k o = look k b)
    (ht : ∀ k, look k b ≠ none → look k t = look k b) (hd : ∀ k, k ∈ keys o → k ∈ keys t → k ∈ keys b)
    (hno : (keys o).Nodup) (hnt : (keys t).Nodup) :
    ∃ m, merge b o t = some m ∧ (∀ e ∈ o, e ∈ m) ∧ (∀ e ∈ t, e ∈ m) := by
  have hdis : ∀ k, look k o ≠ look k b → look k t = look k b := by
    intro k hk
    by_cases hb : look k b = none
    · rw [hb] at hk ⊢
      refine Classical.byContradiction fun hn => ?_
      exact look_ne_none (hd k (mem_keys_of_look hk) (mem_keys_of_look hn)) hb
    · exact absurd (ho k hb) hk
  obtain ⟨m, hm⟩ := no_conflict_disjoint_ids b o t hdis
  refine ⟨m, hm, ?_, ?_⟩
  · rintro ⟨k, v⟩ hmem
    rw [mem_merge hm]
    exact ⟨Or.inl (List.mem_map_of_mem (f := (·.1)) hmem), pick3_add_only b o t ho ht hd hno hmem⟩
  · rintro ⟨k, v⟩ hmem
    rw [mem_merge hm, pick3_comm]
    exact ⟨Or.inr (List.mem_map_of_mem (f := (·.1)) hmem),
      pick3_add_only b t o ht ho (fun k h1 h2 => hd k h2 h1) hnt hmem⟩

/-- A note key: the entry the note amends (a finding's merge id) and the task that wrote it.

The merge id of a note row. -/
abbrev NoteKey := String × String

/-- A notes array: note rows keyed by (entry, task), each with a value (the note's text and fields).

The `notes` member of a ledger. -/
abbrev Notes (V : Type) := List (NoteKey × V)

/-- **Two branches adding notes with distinct (entry, task) keys merge with no clash and keep every note.** Ours and
theirs each keep every base note unchanged (append-only), no (entry, task) key is new on both sides, and each side's
keys are distinct: the merge succeeds and holds every note of ours and every note of theirs (so every base note).

Here `k` ranges over (entry, task) pairs; parallel tasks never clash on notes. -/
theorem distinct_notes_merge (b o t : Notes V) (ho : ∀ k, look k b ≠ none → look k o = look k b)
    (ht : ∀ k, look k b ≠ none → look k t = look k b) (hd : ∀ k, k ∈ keys o → k ∈ keys t → k ∈ keys b)
    (hno : (keys o).Nodup) (hnt : (keys t).Nodup) :
    ∃ m, merge b o t = some m ∧ (∀ n ∈ o, n ∈ m) ∧ (∀ n ∈ t, n ∈ m) :=
  add_only_merge b o t ho ht hd hno hnt

/-- **Two tasks appending notes merge to base, ours' notes, theirs' notes.** Ours appends notes `X` to the base notes
`N`, theirs appends `Y`, and all (entry, task) keys are distinct.

The exact result for the usual case, `merge_appends` on note keys. -/
theorem distinct_notes_append (N X Y : Notes V) (hnd : (keys (N ++ X ++ Y)).Nodup) :
    merge N (N ++ X) (N ++ Y) = some (N ++ X ++ Y) :=
  merge_appends N X Y hnd

-- the incident: one shared string per entry, both tasks extend it: conflict
#guard merge [("hero.exit", "m")] [("hero.exit", "m; p1p4")] [("hero.exit", "m; restate")] = none
-- the same two extensions as notes keyed by (entry, task): both kept
#guard merge ([(("hero.exit", "a"), "m")] : Notes String)
    [(("hero.exit", "a"), "m"), (("hero.exit", "wktr-p1p4"), "p1p4")]
    [(("hero.exit", "a"), "m"), (("hero.exit", "hero-exit-restate"), "restate")] =
  some [(("hero.exit", "a"), "m"), (("hero.exit", "wktr-p1p4"), "p1p4"), (("hero.exit", "hero-exit-restate"), "restate")]
-- one task, two entries; two tasks, one entry: all distinct keys
#guard (merge ([] : Notes String) [(("e1", "t"), "x")] [(("e2", "t"), "y"), (("e1", "u"), "z")]).isSome
-- the same (entry, task) key with different texts on both sides: conflict (excluded by distinct keys)
#guard merge ([] : Notes String) [(("e", "t"), "x")] [(("e", "t"), "y")] = none

/-! ## One note per (entry, task): the distinct-keys premise of `distinct_notes_merge` as a decision
`fw land --dry` runs `onePerKey` on the merge tree's notes and names `dupKeys` (inc-ledger-note-key-dup). -/

/-- Whether `k` occurs at least twice in `l` (`twice_iff`). -/
def twice (k : K) : List K → Bool
  | [] => false
  | x :: r => if x = k then decide (k ∈ r) else twice k r

/-- `l` without the later repeats of each element, in first-occurrence order. -/
def firsts : List K → List K
  | [] => []
  | x :: r => x :: (firsts r).filter (fun y => decide (y ≠ x))

/-- The keys that occur more than once in `l`, each once, in first-occurrence order. -/
def dupKeys (l : List (K × V)) : List K := firsts ((keys l).filter (fun k => twice k (keys l)))

/-- **At most one note per key**: no key of `l` repeats (`onePerKey_iff`). -/
def onePerKey (l : List (K × V)) : Bool := (dupKeys l).isEmpty

theorem twice_iff (k : K) : ∀ (l : List K), twice k l = true ↔ ∃ a b, l = a ++ k :: b ∧ k ∈ b
  | [] => by simp [twice]
  | x :: r => by
    have ih := twice_iff k r
    constructor
    · intro h
      by_cases hx : x = k
      · subst hx
        simp only [twice, ↓reduceIte, decide_eq_true_eq] at h
        exact ⟨[], r, rfl, h⟩
      · simp only [twice, hx, ↓reduceIte] at h
        obtain ⟨a, b, he, hb⟩ := ih.mp h
        exact ⟨x :: a, b, by rw [he]; rfl, hb⟩
    · rintro ⟨a, b, he, hb⟩
      cases a with
      | nil =>
        simp only [List.nil_append, List.cons.injEq] at he
        obtain ⟨rfl, rfl⟩ := he
        simp [twice, hb]
      | cons y a =>
        simp only [List.cons_append, List.cons.injEq] at he
        obtain ⟨rfl, rfl⟩ := he
        by_cases hy : x = k
        · subst hy
          simp [twice]
        · simp only [twice, hy, ↓reduceIte]
          exact ih.mpr ⟨a, b, rfl, hb⟩

theorem mem_of_twice {k : K} : ∀ {l : List K}, twice k l = true → k ∈ l
  | [], h => by simp [twice] at h
  | x :: r, h => by
    by_cases hx : x = k
    · rw [hx]; exact List.mem_cons_self
    · simp only [twice, hx, ↓reduceIte] at h
      exact List.mem_cons_of_mem _ (mem_of_twice h)

theorem mem_firsts (y : K) : ∀ (l : List K), y ∈ firsts l ↔ y ∈ l
  | [] => by simp [firsts]
  | x :: r => by
    simp only [firsts, List.mem_cons, List.mem_filter, mem_firsts y r, decide_eq_true_eq]
    by_cases h : y = x <;> simp [h]

theorem firsts_nodup : ∀ (l : List K), (firsts l).Nodup
  | [] => List.nodup_nil
  | x :: r => by
    simp only [firsts, List.nodup_cons, List.mem_filter, decide_eq_true_eq, ne_eq, not_true_eq_false, and_false,
      not_false_eq_true, true_and]
    exact (firsts_nodup r).filter _

theorem nodup_iff_not_twice : ∀ (l : List K), l.Nodup ↔ ∀ k, twice k l = false
  | [] => by simp [twice]
  | x :: r => by
    rw [List.nodup_cons, nodup_iff_not_twice r]
    constructor
    · rintro ⟨hx, hr⟩ k
      by_cases h : x = k
      · subst h; simp [twice, hx]
      · simp only [twice, h, ↓reduceIte]; exact hr k
    · intro h
      refine ⟨fun hx => by simpa [twice, hx] using h x, fun k => ?_⟩
      by_cases hk : x = k
      · subst hk
        refine Bool.eq_false_iff.mpr fun ht => ?_
        have := h x
        simp [twice, mem_of_twice ht] at this
      · have := h k
        simpa [twice, hk] using this

omit [DecidableEq V] in
/-- `k` is named iff some note of `l` with key `k` has a later one. -/
theorem mem_dupKeys (l : List (K × V)) (k : K) : k ∈ dupKeys l ↔ ∃ a b, keys l = a ++ k :: b ∧ k ∈ b := by
  rw [dupKeys, mem_firsts, List.mem_filter, ← twice_iff]
  exact ⟨fun h => h.2, fun h => ⟨mem_of_twice h, h⟩⟩

omit [DecidableEq V] in
/-- `dupKeys` names each repeated key once. -/
theorem dupKeys_nodup (l : List (K × V)) : (dupKeys l).Nodup := firsts_nodup _

omit [DecidableEq V] in
/-- Pass branch: `onePerKey l` iff the keys of `l` are distinct. -/
theorem onePerKey_iff (l : List (K × V)) : onePerKey l = true ↔ (keys l).Nodup := by
  rw [nodup_iff_not_twice, onePerKey, List.isEmpty_iff, List.eq_nil_iff_forall_not_mem]
  refine forall_congr' fun k => ?_
  rw [dupKeys, mem_firsts, List.mem_filter, Bool.eq_false_iff]
  exact ⟨fun h ht => h ⟨mem_of_twice ht, ht⟩, fun h ⟨_, ht⟩ => h ht⟩

omit [DecidableEq V] in
/-- Refusal branch: `onePerKey l` fails iff `dupKeys l` names a key. -/
theorem onePerKey_false (l : List (K × V)) : onePerKey l = false ↔ ∃ k, k ∈ dupKeys l := by
  rw [onePerKey, Bool.eq_false_iff, ne_eq, List.isEmpty_iff, List.eq_nil_iff_forall_not_mem]
  simp

/-- Two add-only branches that pass `onePerKey`, with no key new on both, merge with no clash and keep every note. -/
theorem onePerKey_merge (b o t : Notes V) (hpo : onePerKey o = true) (hpt : onePerKey t = true)
    (ho : ∀ k, look k b ≠ none → look k o = look k b) (ht : ∀ k, look k b ≠ none → look k t = look k b)
    (hd : ∀ k, k ∈ keys o → k ∈ keys t → k ∈ keys b) :
    ∃ m, merge b o t = some m ∧ (∀ n ∈ o, n ∈ m) ∧ (∀ n ∈ t, n ∈ m) :=
  distinct_notes_merge b o t ho ht hd ((onePerKey_iff o).mp hpo) ((onePerKey_iff t).mp hpt)

/-- Two add-only branches of tasks `τo ≠ τt` that pass `onePerKey` and add notes only under their own task merge with
no clash and keep every note. -/
theorem onePerKey_tasks_merge (τo τt : String) (hτ : τo ≠ τt) (b o t : Notes V) (hpo : onePerKey o = true)
    (hpt : onePerKey t = true) (ho : ∀ k, look k b ≠ none → look k o = look k b)
    (ht : ∀ k, look k b ≠ none → look k t = look k b) (hwo : ∀ k ∈ keys o, k ∉ keys b → k.2 = τo)
    (hwt : ∀ k ∈ keys t, k ∉ keys b → k.2 = τt) :
    ∃ m, merge b o t = some m ∧ (∀ n ∈ o, n ∈ m) ∧ (∀ n ∈ t, n ∈ m) :=
  onePerKey_merge b o t hpo hpt ho ht fun k hko hkt =>
    Classical.byContradiction fun hb => hτ ((hwo k hko hb).symm.trans (hwt k hkt hb))

#guard dupKeys ([(("morph.end.release:on", "combo-scroll-fight"), "mechanism"),
    (("morph.end.release:on", "combo-scroll-fight"), "visual"),
    (("morph.end.release:on", "combo-scroll-fight"), "next")] : Notes String) =
  [("morph.end.release:on", "combo-scroll-fight")]
#guard onePerKey ([(("e1", "t"), "x"), (("e1", "u"), "y"), (("e2", "t"), "z")] : Notes String)
#guard dupKeys ([(("b", "t"), "1"), (("a", "t"), "1"), (("a", "t"), "2"), (("b", "t"), "2")] : Notes String) =
  [("b", "t"), ("a", "t")]
#guard merge ([] : Notes String) [(("e", "t"), "a"), (("e", "t"), "b")] [] = some [(("e", "t"), "a"), (("e", "t"), "a")]

end Fw.Ops.LedgerMerge

/-! ## Golden vectors (`packages/contracts/golden/ops/ledger-merge.jsonl`)

One line per case: `{"name", "base", "ours", "theirs", "rows", "merged"}`. An entry is the JSON object
`{"id": i, "v": v}` (id-keyed cases) or `{"entry": e, "task": τ, "v": v}` (note cases, key `(e, τ)`); a row is
`{"keep": entry}`, `{"drop": key}` or `{"clash": key, "base": entry|null, "ours": entry|null, "theirs": entry|null}`,
where `key` is the driver's key string (`i`, or `note:` followed by the JSON array `[e, τ]`); `merged` is the entry
array or `null` on a conflict. `scripts/merge-ledger.mjs` must compute the same rows and result from the same three
entry arrays (`apps/runner/test/ledger-merge.test.ts`). -/

namespace Fw.Wire.LedgerMerge.Golden
open Lean Fw.Ops.LedgerMerge

/-- How a key type is written: its JSON fields in an entry and the driver's key string (`keyOf`). -/
structure KeyJson (K : Type) where
  /-- the key's fields of an entry object -/
  fields : K → List (String × Json)
  /-- the key string of a `drop` or `clash` row -/
  str : K → String

/-- Plain ids: `{"id": i}`, key string `i`. -/
def idKey : KeyJson String := ⟨fun i => [("id", .str i)], id⟩

/-- Note keys: `{"entry": e, "task": τ}`, key string `note:["e","τ"]` (`keyOf` in `scripts/merge-ledger.mjs`). -/
def noteKey : KeyJson NoteKey :=
  ⟨fun k => [("entry", .str k.1), ("task", .str k.2)], fun k => "note:" ++ (Json.arr #[.str k.1, .str k.2]).compress⟩

#guard noteKey.str ("hero.exit", "wktr-p1p4") = "note:[\"hero.exit\",\"wktr-p1p4\"]"

variable {K : Type} [DecidableEq K]

/-- An entry as JSON. -/
def entryJson (kj : KeyJson K) (e : K × String) : Json := Json.mkObj (kj.fields e.1 ++ [("v", .str e.2)])

/-- An optional version as JSON (`null` when absent). -/
def optJson (kj : KeyJson K) (i : K) : Option String → Json
  | some v => entryJson kj (i, v)
  | none => .null

/-- A row as JSON. -/
def rowJson (kj : KeyJson K) : Row K String → Json
  | .keep i v => Json.mkObj [("keep", entryJson kj (i, v))]
  | .drop i => Json.mkObj [("drop", .str (kj.str i))]
  | .clash i b o t => Json.mkObj [("clash", .str (kj.str i)), ("base", optJson kj i b), ("ours", optJson kj i o),
      ("theirs", optJson kj i t)]

/-- An entry list as JSON. -/
def listJson (kj : KeyJson K) (l : List (K × String)) : Json := .arr (l.map (entryJson kj)).toArray

/-- The cases: (name, base, ours, theirs). -/
def cases : List (String × List (String × String) × List (String × String) × List (String × String)) := [
  ("both append different ids (the 2026-10-18 conflict)",
    [("a", "1"), ("b", "1")], [("a", "1"), ("b", "1"), ("c", "1")], [("a", "1"), ("b", "1"), ("d", "1")]),
  ("both append the same entry", [("a", "1")], [("a", "1"), ("c", "1")], [("a", "1"), ("c", "1")]),
  ("both add the same id with different values: clash", [("a", "1")], [("a", "1"), ("c", "1")],
    [("a", "1"), ("c", "2")]),
  ("ours edits, theirs unchanged", [("a", "1"), ("b", "1")], [("a", "2"), ("b", "1")], [("a", "1"), ("b", "1")]),
  ("theirs edits, ours unchanged", [("a", "1"), ("b", "1")], [("a", "1"), ("b", "1")], [("a", "1"), ("b", "2")]),
  ("both edit alike", [("a", "1")], [("a", "2")], [("a", "2")]),
  ("both edit differently: clash", [("a", "1"), ("b", "1")], [("a", "2"), ("b", "1")], [("a", "3"), ("b", "1")]),
  ("ours deletes, theirs unchanged: deleted", [("a", "1"), ("b", "1")], [("b", "1")], [("a", "1"), ("b", "1")]),
  ("theirs deletes, ours unchanged: deleted (drop row)", [("a", "1"), ("b", "1")], [("a", "1"), ("b", "1")],
    [("b", "1")]),
  ("ours deletes, theirs edits: clash", [("a", "1"), ("b", "1")], [("b", "1")], [("a", "2"), ("b", "1")]),
  ("both delete", [("a", "1"), ("b", "1")], [("b", "1")], [("b", "1")]),
  ("ours backfills a field, theirs appends", [("a", "1"), ("b", "1")], [("a", "1+f"), ("b", "1+f")],
    [("a", "1"), ("b", "1"), ("c", "1")]),
  ("ours reorders, theirs appends: ours' order, then theirs' addition", [("a", "1"), ("b", "1")],
    [("b", "1"), ("a", "1")], [("a", "1"), ("b", "1"), ("c", "1")]),
  ("identical sides: the side itself", [("a", "1"), ("b", "1")], [("b", "2"), ("c", "1")], [("b", "2"), ("c", "1")]),
  ("one clash among clean rows", [("a", "1"), ("b", "1")], [("a", "2"), ("b", "1"), ("c", "1")],
    [("a", "3"), ("b", "2"), ("d", "1")]),
  ("all empty", [], [], [])
]

-- the cases' results, decided in Lean
#guard (cases.map fun (_, b, o, t) => (merge b o t).isSome) =
  [true, true, false, true, true, true, false, true, true, false, true, true, true, true, false, true]

/-- The note cases (key (entry, task)): (name, base, ours, theirs). -/
def noteCases : List (String × Notes String × Notes String × Notes String) := [
  ("notes: two tasks append notes to one entry (inc-findings-shared-entry)",
    [(("hero.exit", "a"), "1")], [(("hero.exit", "a"), "1"), (("hero.exit", "wktr-p1p4"), "1")],
    [(("hero.exit", "a"), "1"), (("hero.exit", "hero-exit-restate"), "1")]),
  ("notes: one task notes two entries, another task one", [],
    [(("e1", "t"), "1"), (("e2", "t"), "1")], [(("e1", "u"), "1")]),
  ("notes: same task, same entry, same text on both sides", [(("e", "a"), "1")],
    [(("e", "a"), "1"), (("e", "t"), "1")], [(("e", "a"), "1"), (("e", "t"), "1")]),
  ("notes: same (entry, task) with different texts: clash", [], [(("e", "t"), "1")], [(("e", "t"), "2")]),
  ("notes: a task edits its own note, another appends", [(("e", "t"), "1")], [(("e", "t"), "2")],
    [(("e", "t"), "1"), (("e", "u"), "1")]),
  ("notes: one side deletes a note, the other appends", [(("e", "t"), "1"), (("e", "u"), "1")],
    [(("e", "u"), "1")], [(("e", "t"), "1"), (("e", "u"), "1"), (("f", "t"), "1")])
]

-- the note cases' results, decided in Lean
#guard (noteCases.map fun (_, b, o, t) => (merge b o t).isSome) = [true, true, true, false, true, true]

/-- One golden line. -/
def line (kj : KeyJson K) (name : String) (b o t : List (K × String)) : String :=
  (Json.mkObj [("name", .str name), ("base", listJson kj b), ("ours", listJson kj o), ("theirs", listJson kj t),
    ("rows", .arr ((rows b o t).map (rowJson kj)).toArray),
    ("merged", match merge b o t with | some m => listJson kj m | none => .null)]).compress

/-- The text of the golden file: the id-keyed cases, then the note cases. -/
def fileText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, b, o, t) => line idKey n b o t ++ "\n") ++
    String.join (noteCases.map fun (n, b, o, t) => line noteKey n b o t ++ "\n")

/-- The note-key cases: (name, the notes array of a tree as (entry, task) keys with the note's field). -/
def noteKeyCases : List (String × Notes String) :=
  let hit := (("elements-skip (elementsFromPoint with an allow-list, no pointer-events write)",
    "hittest-elements-proof"), "chromium")
  let morph := "morph.end.release:on (brick C of morph-end-bricks): a close start drops the pin and stops \
    preventDefault until the next open"
  let band := "commission:band-gate: in the c1000 band skip the two custom-property writes \
    (--commission-enter-shrink, --commission-shrink) every follower frame, since the CSS pins scale 1 and radius 0 \
    there; write the current pair on the first frame that reads the band off"
  [("refused: combo-scroll-fight writes three notes under one (entry, task), one field each (tip before 9f59cf85a)",
      [hit, ((morph, "combo-scroll-fight"), "mechanism"), ((morph, "combo-scroll-fight"), "visual"),
        ((morph, "combo-scroll-fight"), "next")]),
    ("refused: commission-band-mech writes two notes under one (entry, task), one field each (tip before fe854965f)",
      [hit, ((morph, "combo-scroll-fight"), "mechanism"), ((band, "commission-band-mech"), "mechanism"),
        ((band, "commission-band-mech"), "missingWhy")]),
    ("passes: both fixes, one note per (entry, task) (fe854965f)",
      [hit, ((morph, "combo-scroll-fight"), "mechanism"), ((band, "commission-band-mech"), "mechanism")]),
    ("passes: two tasks note one entry, one task notes two entries",
      [((band, "commission-band-mech"), "mechanism"), ((band, "second-task"), "next"),
        ((morph, "commission-band-mech"), "visual")]),
    ("refused: two repeated keys, named once each in first-occurrence order",
      [(("b", "t"), "f"), (("a", "t"), "f"), (("a", "t"), "g"), (("b", "t"), "g"), (("a", "t"), "h")]),
    ("passes: no notes", [])]

#guard (noteKeyCases.map fun (_, l) => onePerKey l) = [false, false, true, true, false, true]
#guard (noteKeyCases.map fun (_, l) => (dupKeys l).length) = [1, 1, 0, 0, 2, 0]

/-- A note key as JSON: `{"entry": e, "task": τ}`. -/
def noteKeyJson (k : NoteKey) : Json := Json.mkObj [("entry", .str k.1), ("task", .str k.2)]

/-- One note-key golden line: `{"name", "notes": [{"entry", "task", "field"}], "dups": [key], "onePerKey"}`. -/
def noteKeyLine (name : String) (l : Notes String) : String :=
  (Json.mkObj [("name", .str name),
    ("notes", .arr (l.map fun (k, f) => Json.mkObj [("entry", .str k.1), ("task", .str k.2), ("field", .str f)]).toArray),
    ("dups", .arr ((dupKeys l).map noteKeyJson).toArray), ("onePerKey", .bool (onePerKey l))]).compress

/-- The text of `packages/contracts/golden/ops/ledger-note-key.jsonl`. -/
def noteKeyText (_ : Unit := ()) : String :=
  String.join (noteKeyCases.map fun (n, l) => noteKeyLine n l ++ "\n")

/-- Compare (or write) one golden file; returns 1 if it is stale, else 0. -/
def runFile (p : System.FilePath) (label : String) (count : Nat) (text : String) (write : Bool) : IO Nat := do
  if write then
    IO.FS.writeFile p text
    IO.println s!"{label} golden: {count} cases written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != text then
    IO.println s!"{label} golden: {p} is stale (regenerate: cd lean && lake test -- --write-ledger-merge-golden)"
    return 1
  IO.println s!"{label} golden: {count} cases, 0 stale"
  return 0

/-- Compare (or write) `packages/contracts/golden/ops/ledger-merge.jsonl` and `ledger-note-key.jsonl` under `root`
(the `lean/` directory); returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / ".." / "packages" / "contracts" / "golden" / "ops"
  let a ← runFile (d / "ledger-merge.jsonl") "ledger-merge" (cases.length + noteCases.length) fileText write
  let b ← runFile (d / "ledger-note-key.jsonl") "ledger-note-key" noteKeyCases.length noteKeyText write
  return a + b

end Fw.Wire.LedgerMerge.Golden
