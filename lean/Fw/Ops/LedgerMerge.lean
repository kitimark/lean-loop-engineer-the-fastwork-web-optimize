import Lean.Data.Json
/-!
# Three-way merge of id-keyed ledgers (`scripts/merge-ledger.mjs`)

The JSON ledgers (`docs/team/incidents/ledger.json`, `research/findings/ledger.json`,
`research/mistakes/ledger.json`) are lists of entries keyed by an id. Two branches that each append an entry edit
the same lines at the end of the array, so git's line merge reports a conflict although the entries do not clash
(three `fw land` refusals on 2026-10-18). The git merge driver `scripts/merge-ledger.mjs` merges such lists per id
with the decision below; reading, writing and rendering JSON is glue.

* An entry is a pair $(i, v)$ of an id and a value; $\ell(i, L)$ is the first value of id $i$ in $L$, or
  $\bot$ (absent).
* Per id, the three-way rule `pick3` on $(\ell(i,B), \ell(i,O), \ell(i,T))$: a side that left the base unchanged
  takes the other side's version (an addition, an edit or a deletion), equal versions agree, and the id is a
  conflict iff both sides changed it differently.
* Output order: ours' ids in ours' order, then theirs' ids that ours lacks, in theirs' order. A ledger branch keeps
  the base order and appends, so this is "base order, then ours' additions, then theirs'"; taking ours' order (not
  the base's) is what makes `merge_idempotent` hold exactly.

Theorems: `conflict_iff`, `merge_comm_up_to_order`, `no_conflict_disjoint_ids`, `merge_idempotent` and
`merge_appends` (two branches that append different entries merge to base, ours' entries, theirs' entries: the
2026-10-18 conflict). Golden vectors: `packages/contracts/golden/ops/ledger-merge.jsonl`
(`Fw.Wire.LedgerMerge.Golden.run`, checked by `lake test`).
-/

namespace Fw.Ops.LedgerMerge

variable {V : Type} [DecidableEq V]

/-- The ids of an entry list, in order.

$$\kappa([(i_1, v_1), \dots, (i_n, v_n)]) = [i_1, \dots, i_n]$$

The id column of a ledger. -/
def keys (l : List (String × V)) : List String := l.map (·.1)

/-- The value of the first entry with id $i$, or none.

$$\ell(i, [\,]) = \bot, \qquad \ell(i, (j, v) :: L) = \begin{cases} v & j = i \\ \ell(i, L) & j \ne i \end{cases}$$

Looks an id up in a ledger. -/
def look (i : String) : List (String × V) → Option V
  | [] => none
  | (j, v) :: r => if j = i then some v else look i r

/-- The three-way rule for one id: base $b$, ours $o$, theirs $t$ (each a value or $\bot$ for absent); the result
is $\mathrm{some}(r)$ with the merged version $r$ (again possibly $\bot$, a deletion) or $\mathrm{none}$ for a
conflict.

$$\operatorname{pick}(b, o, t) = \begin{cases} \mathrm{some}(t) & o = b \\ \mathrm{some}(o) & o \ne b \wedge t = b \\ \mathrm{some}(o) & o \ne b \wedge t \ne b \wedge o = t \\ \mathrm{none} & o \ne b \wedge t \ne b \wedge o \ne t \end{cases}$$

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

$$\operatorname{ids}(O, T) = \kappa(O) \mathbin{+\!\!+} [\, i \in \kappa(T) \mid i \notin \kappa(O) \,]$$

The bracket keeps theirs' order (a filtered list, not a set). -/
def ids (o t : List (String × V)) : List String :=
  keys o ++ (keys t).filter (fun i => decide (i ∉ keys o))

/-- One row of the merge: keep id $i$ with value $v$, drop id $i$ (deleted), or a clash with the base, ours' and
theirs' versions.

$$\rho \in \{\mathrm{keep}(i, v),\ \mathrm{drop}(i),\ \mathrm{clash}(i, b, o, t)\}$$

What the driver renders per id. -/
inductive Row (V : Type) where
  /-- id kept with this value -/
  | keep (i : String) (v : V)
  /-- id deleted -/
  | drop (i : String)
  /-- both sides changed the id differently -/
  | clash (i : String) (b o t : Option V)
  deriving DecidableEq, Repr

/-- The row of id $i$.

$$\operatorname{row}(B, O, T, i) = \begin{cases} \mathrm{keep}(i, v) & \operatorname{pick}(\ell(i,B), \ell(i,O), \ell(i,T)) = \mathrm{some}(\mathrm{some}(v)) \\ \mathrm{drop}(i) & \operatorname{pick}(\dots) = \mathrm{some}(\bot) \\ \mathrm{clash}(i, \ell(i,B), \ell(i,O), \ell(i,T)) & \operatorname{pick}(\dots) = \mathrm{none} \end{cases}$$

Applies the three-way rule to one id. -/
def row (b o t : List (String × V)) (i : String) : Row V :=
  match pick3 (look i b) (look i o) (look i t) with
  | some (some v) => .keep i v
  | some none => .drop i
  | none => .clash i (look i b) (look i o) (look i t)

/-- All rows, in merge order.

$$\operatorname{rows}(B, O, T) = [\operatorname{row}(B, O, T, i) \mid i \in \operatorname{ids}(O, T)]$$

The per-id decisions the driver renders. -/
def rows (b o t : List (String × V)) : List (Row V) := (ids o t).map (row b o t)

/-- The entry a row keeps, if any.

$$\operatorname{entry}(\mathrm{keep}(i,v)) = \mathrm{some}(i,v), \quad \operatorname{entry}(\mathrm{drop}(i)) = \operatorname{entry}(\mathrm{clash}(\dots)) = \mathrm{none}$$

Kept rows become entries. -/
def Row.entry? : Row V → Option (String × V)
  | .keep i v => some (i, v)
  | _ => none

/-- Whether a row is a clash.

$$\operatorname{isClash}(\rho) \iff \exists i, b, o, t,\ \rho = \mathrm{clash}(i, b, o, t)$$

Any clash fails the merge. -/
def Row.isClash : Row V → Bool
  | .clash .. => true
  | _ => false

/-- **The ledger merge.** No clash: the kept entries in merge order; a clash: none (git reports a conflict).

$$\operatorname{merge}(B, O, T) = \begin{cases} \mathrm{none} & \exists \rho \in \operatorname{rows}(B,O,T),\ \operatorname{isClash}(\rho) \\ \mathrm{some}\,[\, e \mid \rho \in \operatorname{rows}(B,O,T),\ \operatorname{entry}(\rho) = \mathrm{some}(e) \,] & \text{otherwise} \end{cases}$$

The whole decision of `scripts/merge-ledger.mjs`; JSON in and out is glue. -/
def merge (b o t : List (String × V)) : Option (List (String × V)) :=
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

$$\forall i, L,\quad \ell(i, L) \ne \bot \implies i \in \kappa(L)$$

A looked-up value names a listed id. -/
theorem mem_keys_of_look {i : String} : ∀ {l : List (String × V)}, look i l ≠ none → i ∈ keys l
  | [], h => absurd rfl h
  | (j, v) :: r, h => by
    simp only [look] at h
    simp only [keys, List.map_cons, List.mem_cons]
    by_cases hj : j = i
    · exact Or.inl hj.symm
    · simp only [hj, ↓reduceIte] at h; exact Or.inr (mem_keys_of_look h)

omit [DecidableEq V] in
/-- A listed id looks up to a value.

$$\forall i, L,\quad i \in \kappa(L) \implies \ell(i, L) \ne \bot$$

The converse of `mem_keys_of_look`. -/
theorem look_ne_none {i : String} : ∀ {l : List (String × V)}, i ∈ keys l → look i l ≠ none
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

$$\forall i, L, M,\quad \ell(i, L \mathbin{+\!\!+} M) = \begin{cases} \ell(i, L) & \ell(i, L) \ne \bot \\ \ell(i, M) & \ell(i, L) = \bot \end{cases}$$

Used for appended ledgers. -/
theorem look_append (i : String) : ∀ (l m : List (String × V)), look i (l ++ m) = (look i l).or (look i m)
  | [], _ => rfl
  | (j, v) :: r, m => by
    simp only [List.cons_append, look]
    split
    · rfl
    · exact look_append i r m

omit [DecidableEq V] in
/-- An id not listed looks up to nothing.

$$\forall i, L,\quad i \notin \kappa(L) \implies \ell(i, L) = \bot$$

Contrapositive of `mem_keys_of_look`. -/
theorem look_eq_none {i : String} {l : List (String × V)} (h : i ∉ keys l) : look i l = none :=
  Classical.byContradiction fun hn => h (mem_keys_of_look hn)

omit [DecidableEq V] in
/-- A filter-map over the ids that yields each id's own entry rebuilds the list.

$$\forall L, g,\quad \operatorname{nodup}(\kappa(L)) \wedge \big(\forall i \in \kappa(L),\ g(i) = \operatorname{map}(v \mapsto (i, v), \ell(i, L))\big) \implies \operatorname{filterMap}(g, \kappa(L)) = L$$

A list with distinct ids is its ids, each with its value. -/
theorem filterMap_keys_look : ∀ (l : List (String × V)) (g : String → Option (String × V)), (keys l).Nodup →
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

$$\forall b, o, t,\quad \operatorname{pick}(b, o, t) = \mathrm{none} \iff o \ne b \wedge t \ne b \wedge o \ne t$$

The conflict condition per id. -/
theorem pick3_eq_none (b o t : Option V) : pick3 b o t = none ↔ o ≠ b ∧ t ≠ b ∧ o ≠ t := by
  unfold pick3
  by_cases h1 : o = b <;> by_cases h2 : t = b <;> by_cases h3 : o = t <;> simp [h1, h2, h3]

/-- `pick3` is symmetric in ours and theirs.

$$\forall b, o, t,\quad \operatorname{pick}(b, o, t) = \operatorname{pick}(b, t, o)$$

Swapping the sides changes no per-id decision. -/
theorem pick3_comm (b o t : Option V) : pick3 b o t = pick3 b t o := by
  unfold pick3
  by_cases h1 : o = b <;> by_cases h2 : t = b <;> by_cases h3 : o = t <;> simp_all [eq_comm]

omit [DecidableEq V] in
/-- Membership in the merge order.

$$\forall i, O, T,\quad i \in \operatorname{ids}(O, T) \iff i \in \kappa(O) \vee i \in \kappa(T)$$

Every id of either side gets a row. -/
theorem mem_ids (i : String) (o t : List (String × V)) : i ∈ ids o t ↔ i ∈ keys o ∨ i ∈ keys t := by
  unfold ids
  simp only [List.mem_append, List.mem_filter, decide_eq_true_eq]
  by_cases h : i ∈ keys o <;> simp [h]

/-- No clash among the rows iff no id is a two-sided different change.

$$\forall B, O, T,\quad (\exists \rho \in \operatorname{rows}(B,O,T),\ \operatorname{isClash}(\rho)) \iff \exists i,\ \ell(i,O) \ne \ell(i,B) \wedge \ell(i,T) \ne \ell(i,B) \wedge \ell(i,O) \ne \ell(i,T)$$

Ids outside both sides cannot clash, since absent equals absent there. -/
theorem any_clash_iff (b o t : List (String × V)) :
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

$$\forall B, O, T,\quad \operatorname{merge}(B, O, T) = \mathrm{none} \iff \exists i,\ \ell(i,O) \ne \ell(i,B) \wedge \ell(i,T) \ne \ell(i,B) \wedge \ell(i,O) \ne \ell(i,T)$$

Here $\ell(i, \cdot) = \bot$ when $i$ is absent. -/
theorem conflict_iff (b o t : List (String × V)) :
    merge b o t = none ↔ ∃ i, look i o ≠ look i b ∧ look i t ≠ look i b ∧ look i o ≠ look i t := by
  rw [← any_clash_iff]
  dsimp only [merge]
  split <;> simp_all

/-- What a successful merge holds: exactly the ids of either side whose rule keeps a value, with that value.

$$\forall B, O, T, M,\quad \operatorname{merge}(B,O,T) = \mathrm{some}(M) \implies \forall (i, v),\ (i, v) \in M \iff (i \in \kappa(O) \vee i \in \kappa(T)) \wedge \operatorname{pick}(\ell(i,B), \ell(i,O), \ell(i,T)) = \mathrm{some}(\mathrm{some}(v))$$

Membership in the merged list, independent of its order. -/
theorem mem_merge {b o t m : List (String × V)} (h : merge b o t = some m) (i : String) (v : V) :
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

$$\forall B, O, T,\quad \big(\operatorname{merge}(B,O,T) = \mathrm{none} \iff \operatorname{merge}(B,T,O) = \mathrm{none}\big) \wedge \forall M, M',\ \operatorname{merge}(B,O,T) = \mathrm{some}(M) \wedge \operatorname{merge}(B,T,O) = \mathrm{some}(M') \implies \forall e,\ e \in M \iff e \in M'$$

The driver's result does not depend on which branch is merged into which, up to order. -/
theorem merge_comm_up_to_order (b o t : List (String × V)) :
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

$$\forall B, O, T,\quad \big(\forall i,\ \ell(i,O) \ne \ell(i,B) \implies \ell(i,T) = \ell(i,B)\big) \implies \exists M,\ \operatorname{merge}(B,O,T) = \mathrm{some}(M)$$

The ids ours changed and the ids theirs changed are disjoint sets; a change is an addition, edit or deletion. -/
theorem no_conflict_disjoint_ids (b o t : List (String × V))
    (h : ∀ i, look i o ≠ look i b → look i t = look i b) : ∃ m, merge b o t = some m := by
  cases hm : merge b o t with
  | some m => exact ⟨m, rfl⟩
  | none =>
    obtain ⟨i, h1, h2, _⟩ := (conflict_iff b o t).mp hm
    exact absurd (h i h1) h2

/-- A merge whose rule keeps exactly the entries of $L$, in $L$'s id order, returns $L$.

$$\forall B, O, T, L,\quad \operatorname{nodup}(\kappa(L)) \wedge \operatorname{ids}(O,T) = \kappa(L) \wedge \big(\forall i \in \kappa(L),\ \operatorname{pick}(\ell(i,B), \ell(i,O), \ell(i,T)) = \mathrm{some}(\ell(i,L))\big) \implies \operatorname{merge}(B,O,T) = \mathrm{some}(L)$$

The common step of `merge_idempotent` and `merge_appends`. -/
theorem merge_eq_of_pick (b o t l : List (String × V)) (hnd : (keys l).Nodup) (hids : ids o t = keys l)
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

$$\forall B, X,\quad \operatorname{nodup}(\kappa(X)) \implies \operatorname{merge}(B, X, X) = \mathrm{some}(X)$$

Idempotence: a merge of identical sides is a no-op, order included. -/
theorem merge_idempotent (b x : List (String × V)) (hnd : (keys x).Nodup) : merge b x x = some x := by
  apply merge_eq_of_pick b x x x hnd
  · unfold ids
    have : (keys x).filter (fun i => decide (i ∉ keys x)) = [] := by
      rw [List.filter_eq_nil_iff]; intro i hi; simp [hi]
    rw [this, List.append_nil]
  · intro i _
    unfold pick3
    by_cases h : look i x = look i b <;> simp [h]

/-- **Two branches that append different entries merge cleanly** (the 2026-10-18 incident-ledger conflict): ours
appends $X$ to the base $B$, theirs appends $Y$, and all ids are distinct; the merge is $B$, then $X$, then $Y$.

$$\forall B, X, Y,\quad \operatorname{nodup}(\kappa(B \mathbin{+\!\!+} X \mathbin{+\!\!+} Y)) \implies \operatorname{merge}(B,\ B \mathbin{+\!\!+} X,\ B \mathbin{+\!\!+} Y) = \mathrm{some}(B \mathbin{+\!\!+} X \mathbin{+\!\!+} Y)$$

The textual conflict of two appends is no conflict per id. -/
theorem merge_appends (B X Y : List (String × V)) (hnd : (keys (B ++ X ++ Y)).Nodup) :
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

end Fw.Ops.LedgerMerge

/-! ## Golden vectors (`packages/contracts/golden/ops/ledger-merge.jsonl`)

One line per case: `{"name", "base", "ours", "theirs", "rows", "merged"}`. An entry is the JSON object
`{"id": i, "v": v}`; a row is `{"keep": entry}`, `{"drop": id}` or
`{"clash": id, "base": entry|null, "ours": entry|null, "theirs": entry|null}`; `merged` is the entry array or
`null` on a conflict. `scripts/merge-ledger.mjs` must compute the same rows and result from the same three entry
arrays (`apps/runner/test/ledger-merge.test.ts`). -/

namespace Fw.Wire.LedgerMerge.Golden
open Lean Fw.Ops.LedgerMerge

/-- An entry as JSON. -/
def entryJson (e : String × String) : Json := Json.mkObj [("id", .str e.1), ("v", .str e.2)]

/-- An optional version as JSON (`null` when absent). -/
def optJson (i : String) : Option String → Json
  | some v => entryJson (i, v)
  | none => .null

/-- A row as JSON. -/
def rowJson : Row String → Json
  | .keep i v => Json.mkObj [("keep", entryJson (i, v))]
  | .drop i => Json.mkObj [("drop", .str i)]
  | .clash i b o t => Json.mkObj [("clash", .str i), ("base", optJson i b), ("ours", optJson i o),
      ("theirs", optJson i t)]

/-- An entry list as JSON. -/
def listJson (l : List (String × String)) : Json := .arr (l.map entryJson).toArray

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

/-- One golden line. -/
def line (name : String) (b o t : List (String × String)) : String :=
  (Json.mkObj [("name", .str name), ("base", listJson b), ("ours", listJson o), ("theirs", listJson t),
    ("rows", .arr ((rows b o t).map rowJson).toArray),
    ("merged", match merge b o t with | some m => listJson m | none => .null)]).compress

/-- The text of the golden file. -/
def fileText : String := String.join (cases.map fun (n, b, o, t) => line n b o t ++ "\n")

/-- Compare (or write) `packages/contracts/golden/ops/ledger-merge.jsonl` under `root` (the `lean/` directory);
returns 1 if the file is stale, else 0. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "ops" / "ledger-merge.jsonl"
  if write then
    IO.FS.writeFile p fileText
    IO.println s!"ledger-merge golden: {cases.length} cases written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != fileText then
    IO.println s!"ledger-merge golden: {p} is stale (regenerate: cd lean && lake test -- --write-ledger-merge-golden)"
    return 1
  IO.println s!"ledger-merge golden: {cases.length} cases, 0 stale"
  return 0

end Fw.Wire.LedgerMerge.Golden
