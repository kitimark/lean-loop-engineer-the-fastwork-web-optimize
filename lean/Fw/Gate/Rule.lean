/-!
# The breakpoint gate's pass/fail rule (PLAN 6.6)

Port of `cellVerdict`, `verdictToStatus` and `rollup` from `packages/gate-breakpoints/src/verdict.mjs`.
Every compared item of a probe gets a `Status`; a cell (one table row at one probe, block or sweep)
gets a `Verdict`:

* no applicable item (empty, or every item `na`) gives `nc` (not comparable);
* some applicable item is not `equal` gives `fail`;
* otherwise `pass`.

Rollups (probe verdicts to a block or sweep cell) reuse the same rule through `toStatus`
(`pass ↦ equal`, `fail ↦ differ`, `nc ↦ na`); `Tally` adds the two counts the table prints.

Proved: the three characterisations (`cellVerdict_nc_iff`, `cellVerdict_fail_iff`,
`cellVerdict_pass_iff`), that only the set of statuses matters (`cellVerdict_congr`, so any
reordering of the rows gives the same verdict: `cellVerdict_perm`), that `na` items never matter
(`cellVerdict_filter_na`), that rolling up per-group verdicts equals the verdict of all items at
once (`rollup_flatten`), and that the printed counts agree with the verdict (`tally_*`).
-/
namespace Fw.Gate

/-- Status of one compared item: `na` items take no part in a verdict.

$$\mathcal S = \{\mathrm{equal}, \mathrm{differ}, \mathrm{missing}, \mathrm{na}\}$$

One of the four outcomes of comparing an item of the original with the rewrite. -/
inductive Status where
  | equal
  | differ
  | missing
  | na
  deriving DecidableEq, Repr, Inhabited

/-- Verdict of a cell.

$$\mathcal V = \{\mathrm{pass}, \mathrm{fail}, \mathrm{nc}\}$$

A table cell passes, fails, or is not comparable. -/
inductive Verdict where
  | pass
  | fail
  | nc
  deriving DecidableEq, Repr, Inhabited

/-- **The rule.** Let $A$ be the statuses that are not `na`: not comparable if $A$ is empty, fail if
some status in $A$ is not `equal`, pass otherwise.

$$\operatorname{cell}(ss) = \begin{cases} \mathrm{nc} & A = [\,] \\ \mathrm{pass} & A \ne [\,] \wedge \forall s \in A,\ s = \mathrm{equal} \\ \mathrm{fail} & \text{otherwise} \end{cases}, \qquad A = [\, s \in ss \mid s \ne \mathrm{na} \,]$$

A cell passes when it compared something and everything it compared was equal. -/
def cellVerdict (ss : List Status) : Verdict :=
  let a := ss.filter (· != .na)
  if a.isEmpty then .nc else if a.all (· == .equal) then .pass else .fail

/-- A verdict as a status, so verdicts roll up with the same rule.

$$\mathrm{pass} \mapsto \mathrm{equal},\quad \mathrm{fail} \mapsto \mathrm{differ},\quad \mathrm{nc} \mapsto \mathrm{na}$$

A passing probe counts as an equal item, a failing one as a differing item, an incomparable one not at all. -/
def toStatus : Verdict → Status
  | .pass => .equal
  | .fail => .differ
  | .nc => .na

/-- Verdict of a list of verdicts (a block of probes, or the stops of a sweep).

$$\operatorname{rollup}(vs) = \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs)$$

A block passes when some probe passed and none failed. -/
def rollup (vs : List Verdict) : Verdict := cellVerdict (vs.map toStatus)

/-- A table cell as printed: the rolled-up verdict, the failing probes, the comparable probes.

$$\operatorname{tally}(vs) = \bigl(\operatorname{rollup}(vs),\ |\{v \in vs \mid v = \mathrm{fail}\}|,\ |\{v \in vs \mid v \ne \mathrm{nc}\}|\bigr)$$

What `FAIL failing/total` in the summary table shows. -/
structure Tally where
  verdict : Verdict
  failing : Nat
  total : Nat
  deriving DecidableEq, Repr

/-- The tally of a list of verdicts.

$$\operatorname{tally}(vs) = \bigl(\operatorname{rollup}(vs),\ \operatorname{count}_{\mathrm{fail}}(vs),\ |vs| - \operatorname{count}_{\mathrm{nc}}(vs)\bigr)$$

The block cell with its two counts. -/
def tally (vs : List Verdict) : Tally :=
  { verdict := rollup vs, failing := vs.countP (· == .fail), total := vs.countP (· != .nc) }

/-! ## The three cases of the rule -/

/-- The rule without the filter: not comparable iff all `na`; else pass iff all `na` or `equal`.

$$\forall ss \in \mathcal S^*,\quad \operatorname{cell}(ss) = \begin{cases} \mathrm{nc} & \forall s \in ss,\ s = \mathrm{na} \\ \mathrm{pass} & \text{else, if } \forall s \in ss,\ s \in \{\mathrm{na}, \mathrm{equal}\} \\ \mathrm{fail} & \text{otherwise} \end{cases}$$

The same rule stated over the whole list. -/
theorem cellVerdict_eq (ss : List Status) : cellVerdict ss =
    if ss.all (· == .na) then .nc else if ss.all (fun s => s == .na || s == .equal) then .pass else .fail := by
  have e2 : (ss.filter (· != .na)).all (· == .equal) = ss.all (fun s => s == .na || s == .equal) := by
    rw [List.all_filter]; congr 1; funext a; cases a <;> rfl
  have e1 : (ss.filter (· != .na)).isEmpty = ss.all (· == .na) := by
    clear e2
    induction ss with
    | nil => rfl
    | cons s t ih => cases s <;> simp only [List.filter_cons] <;> simp_all
  unfold cellVerdict
  simp only [e1, e2]

/-- Not comparable exactly when every status is `na`.

$$\forall ss \in \mathcal S^*,\quad \operatorname{cell}(ss) = \mathrm{nc} \iff \forall s \in ss,\ s = \mathrm{na}$$

A cell is incomparable exactly when nothing in it was comparable. -/
theorem cellVerdict_nc_iff (ss : List Status) : cellVerdict ss = .nc ↔ ∀ s ∈ ss, s = .na := by
  rw [cellVerdict_eq]
  by_cases h1 : ss.all (· == .na) = true
  · simp only [h1, ite_true, true_iff]
    simpa [List.all_eq_true] using h1
  · simp only [h1, Bool.false_eq_true, ite_false]
    have : ¬ ∀ s ∈ ss, s = .na := fun h => h1 (by simpa [List.all_eq_true] using h)
    split <;> simp [this]

/-- Fail exactly when some status is neither `na` nor `equal`.

$$\forall ss \in \mathcal S^*,\quad \operatorname{cell}(ss) = \mathrm{fail} \iff \exists s \in ss,\ s \ne \mathrm{na} \wedge s \ne \mathrm{equal}$$

A cell fails exactly when one compared item differs or is missing. -/
theorem cellVerdict_fail_iff (ss : List Status) :
    cellVerdict ss = .fail ↔ ∃ s ∈ ss, s ≠ .na ∧ s ≠ .equal := by
  rw [cellVerdict_eq]
  by_cases h2 : ss.all (fun s => s == .na || s == .equal) = true
  · have hall : ∀ s ∈ ss, s = .na ∨ s = .equal := by simpa [List.all_eq_true] using h2
    have hno : ¬ ∃ s ∈ ss, s ≠ .na ∧ s ≠ .equal := fun ⟨s, hs, h1, h2⟩ =>
      (hall s hs).elim h1 h2
    simp only [h2, ite_true, hno, iff_false]
    split <;> simp
  · have hex : ∃ s ∈ ss, s ≠ .na ∧ s ≠ .equal := by
      apply Classical.byContradiction
      intro hn
      apply h2
      simp only [List.all_eq_true, Bool.or_eq_true, beq_iff_eq]
      intro s hs
      apply Classical.byContradiction
      intro hs'
      exact hn ⟨s, hs, fun h => hs' (.inl h), fun h => hs' (.inr h)⟩
    have h1 : ¬ ss.all (· == .na) = true := by
      obtain ⟨s, hs, hna, _⟩ := hex
      simp only [List.all_eq_true, beq_iff_eq]
      exact fun h => hna (h s hs)
    simp only [h1, h2, Bool.false_eq_true, ite_false, hex]

/-- Pass exactly when some status is `equal` and every status is `na` or `equal`.

$$\forall ss \in \mathcal S^*,\quad \operatorname{cell}(ss) = \mathrm{pass} \iff (\exists s \in ss,\ s = \mathrm{equal}) \wedge \forall s \in ss,\ s = \mathrm{na} \vee s = \mathrm{equal}$$

A cell passes exactly when it compared something and all it compared was equal. -/
theorem cellVerdict_pass_iff (ss : List Status) :
    cellVerdict ss = .pass ↔ (∃ s ∈ ss, s = .equal) ∧ ∀ s ∈ ss, s = .na ∨ s = .equal := by
  have hnc := cellVerdict_nc_iff ss
  have hf := cellVerdict_fail_iff ss
  constructor
  · intro h
    constructor
    · have : ¬ ∀ s ∈ ss, s = .na := fun h' => by rw [hnc.mpr h'] at h; cases h
      obtain ⟨s, hs, hna⟩ : ∃ s ∈ ss, s ≠ .na := Classical.byContradiction fun hn =>
        this fun s hs => Classical.byContradiction fun h' => hn ⟨s, hs, h'⟩
      refine ⟨s, hs, ?_⟩
      by_cases he : s = .equal
      · exact he
      · exact absurd (hf.mpr ⟨s, hs, hna, he⟩) (by rw [h]; decide)
    · intro s hs
      by_cases hna : s = .na
      · exact .inl hna
      · by_cases he : s = .equal
        · exact .inr he
        · exact absurd (hf.mpr ⟨s, hs, hna, he⟩) (by rw [h]; decide)
  · rintro ⟨⟨s, hs, he⟩, hall⟩
    cases hv : cellVerdict ss with
    | pass => rfl
    | nc => exact absurd (hnc.mp hv s hs) (by rw [he]; decide)
    | fail =>
      obtain ⟨t, ht, hna, hne⟩ := hf.mp hv
      rcases hall t ht with h | h
      · exact absurd h hna
      · exact absurd h hne

/-- The verdict depends only on which statuses occur.

$$\forall ss, ts \in \mathcal S^*,\quad (\forall s,\ s \in ss \iff s \in ts) \implies \operatorname{cell}(ss) = \operatorname{cell}(ts)$$

Two cells holding the same statuses, in any order and multiplicity, have the same verdict. -/
theorem cellVerdict_congr (ss ts : List Status) (h : ∀ s, s ∈ ss ↔ s ∈ ts) :
    cellVerdict ss = cellVerdict ts := by
  cases hv : cellVerdict ss with
  | nc =>
    exact ((cellVerdict_nc_iff ts).mpr fun s hs => (cellVerdict_nc_iff ss).mp hv s ((h s).mpr hs)).symm
  | fail =>
    obtain ⟨s, hs, h1, h2⟩ := (cellVerdict_fail_iff ss).mp hv
    exact ((cellVerdict_fail_iff ts).mpr ⟨s, (h s).mp hs, h1, h2⟩).symm
  | pass =>
    obtain ⟨⟨s, hs, he⟩, hall⟩ := (cellVerdict_pass_iff ss).mp hv
    exact ((cellVerdict_pass_iff ts).mpr ⟨⟨s, (h s).mp hs, he⟩, fun t ht => hall t ((h t).mpr ht)⟩).symm

/-- Row order does not matter: a permutation of the statuses has the same verdict.

$$\forall ss, ts \in \mathcal S^*,\quad ss \sim ts \implies \operatorname{cell}(ss) = \operatorname{cell}(ts)$$

Reordering the compared items (or the probes of a block) never changes a verdict. -/
theorem cellVerdict_perm (ss ts : List Status) (h : ss.Perm ts) : cellVerdict ss = cellVerdict ts :=
  cellVerdict_congr ss ts fun _ => h.mem_iff

/-- `na` items never matter: dropping them keeps the verdict.

$$\forall ss \in \mathcal S^*,\quad \operatorname{cell}([\, s \in ss \mid s \ne \mathrm{na} \,]) = \operatorname{cell}(ss)$$

Items outside any verdict (information, unachieved environments) cannot change a cell. -/
theorem cellVerdict_filter_na (ss : List Status) :
    cellVerdict (ss.filter (· != .na)) = cellVerdict ss := by
  unfold cellVerdict
  rw [List.filter_filter]
  simp only [Bool.and_self]

/-- `toStatus` is `na` exactly on `nc`, and `equal` exactly on `pass`.

$$\forall v \in \mathcal V,\quad (\operatorname{toStatus}(v) = \mathrm{na} \iff v = \mathrm{nc}) \wedge (\operatorname{toStatus}(v) = \mathrm{equal} \iff v = \mathrm{pass})$$

The rollup sees passes as equal items and skips incomparable probes. -/
theorem toStatus_spec (v : Verdict) :
    (toStatus v = .na ↔ v = .nc) ∧ (toStatus v = .equal ↔ v = .pass) := by
  cases v <;> decide

/-- A rollup fails exactly when some verdict fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{rollup}(vs) = \mathrm{fail} \iff \mathrm{fail} \in vs$$

One failing probe fails its block. -/
theorem rollup_fail_iff (vs : List Verdict) : rollup vs = .fail ↔ .fail ∈ vs := by
  unfold rollup
  rw [cellVerdict_fail_iff]
  constructor
  · rintro ⟨s, hs, h1, h2⟩
    obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs
    cases v
    · exact absurd rfl h2
    · exact hv
    · exact absurd rfl h1
  · intro h
    exact ⟨.differ, List.mem_map.mpr ⟨.fail, h, rfl⟩, by decide, by decide⟩

/-- A rollup is not comparable exactly when every verdict is.

$$\forall vs \in \mathcal V^*,\quad \operatorname{rollup}(vs) = \mathrm{nc} \iff \forall v \in vs,\ v = \mathrm{nc}$$

A block is incomparable exactly when all its probes are. -/
theorem rollup_nc_iff (vs : List Verdict) : rollup vs = .nc ↔ ∀ v ∈ vs, v = .nc := by
  unfold rollup
  rw [cellVerdict_nc_iff]
  constructor
  · intro h v hv
    exact ((toStatus_spec v).1).mp (h _ (List.mem_map.mpr ⟨v, hv, rfl⟩))
  · intro h s hs
    obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs
    rw [h v hv]; rfl

/-- A rollup passes exactly when some verdict passes and none fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{rollup}(vs) = \mathrm{pass} \iff \mathrm{pass} \in vs \wedge \mathrm{fail} \notin vs$$

A block passes when one probe passed and no probe failed. -/
theorem rollup_pass_iff (vs : List Verdict) : rollup vs = .pass ↔ .pass ∈ vs ∧ .fail ∉ vs := by
  have hf := rollup_fail_iff vs
  have hn := rollup_nc_iff vs
  constructor
  · intro h
    refine ⟨?_, fun hm => by rw [hf.mpr hm] at h; cases h⟩
    have : ¬ ∀ v ∈ vs, v = .nc := fun h' => by rw [hn.mpr h'] at h; cases h
    obtain ⟨v, hv, hne⟩ : ∃ v ∈ vs, v ≠ .nc := Classical.byContradiction fun hn' =>
      this fun v hv => Classical.byContradiction fun h' => hn' ⟨v, hv, h'⟩
    cases v
    · exact hv
    · rw [hf.mpr hv] at h; cases h
    · exact absurd rfl hne
  · rintro ⟨hp, hnf⟩
    cases hr : rollup vs with
    | pass => rfl
    | fail => exact absurd (hf.mp hr) hnf
    | nc => exact absurd (hn.mp hr _ hp) (by decide)

/-- Rolling up per-group verdicts is the verdict of all items at once.

$$\forall gs \in (\mathcal S^*)^*,\quad \operatorname{rollup}(\operatorname{map}\ \operatorname{cell}\ gs) = \operatorname{cell}(\operatorname{flatten}\ gs)$$

A block verdict equals the verdict over every item of every probe of the block. -/
theorem rollup_flatten (gs : List (List Status)) :
    rollup (gs.map cellVerdict) = cellVerdict gs.flatten := by
  cases hv : cellVerdict gs.flatten with
  | fail =>
    obtain ⟨s, hs, h1, h2⟩ := (cellVerdict_fail_iff _).mp hv
    obtain ⟨g, hg, hsg⟩ := List.mem_flatten.mp hs
    exact (rollup_fail_iff _).mpr (List.mem_map.mpr ⟨g, hg, (cellVerdict_fail_iff g).mpr ⟨s, hsg, h1, h2⟩⟩)
  | nc =>
    have h := (cellVerdict_nc_iff _).mp hv
    refine (rollup_nc_iff _).mpr fun v hv' => ?_
    obtain ⟨g, hg, rfl⟩ := List.mem_map.mp hv'
    exact (cellVerdict_nc_iff g).mpr fun s hs => h s (List.mem_flatten.mpr ⟨g, hg, hs⟩)
  | pass =>
    obtain ⟨⟨s, hs, he⟩, hall⟩ := (cellVerdict_pass_iff _).mp hv
    obtain ⟨g, hg, hsg⟩ := List.mem_flatten.mp hs
    refine (rollup_pass_iff _).mpr ⟨List.mem_map.mpr ⟨g, hg, (cellVerdict_pass_iff g).mpr
      ⟨⟨s, hsg, he⟩, fun t ht => hall t (List.mem_flatten.mpr ⟨g, hg, ht⟩)⟩⟩, fun hm => ?_⟩
    obtain ⟨g', hg', hf'⟩ := List.mem_map.mp hm
    obtain ⟨t, ht, h1, h2⟩ := (cellVerdict_fail_iff g').mp hf'
    rcases hall t (List.mem_flatten.mpr ⟨g', hg', ht⟩) with h | h
    · exact h1 h
    · exact h2 h

/-- Rollups ignore order too.

$$\forall vs, ws \in \mathcal V^*,\quad vs \sim ws \implies \operatorname{rollup}(vs) = \operatorname{rollup}(ws)$$

Reordering the probes of a block keeps its verdict. -/
theorem rollup_perm (vs ws : List Verdict) (h : vs.Perm ws) : rollup vs = rollup ws :=
  cellVerdict_perm _ _ (h.map toStatus)

/-- The printed counts agree with the verdict: fail iff some probe fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs).\mathrm{verdict} = \mathrm{fail} \iff 0 < \operatorname{tally}(vs).\mathrm{failing}$$

`FAIL n/m` is printed with n at least 1. -/
theorem tally_fail_iff (vs : List Verdict) : (tally vs).verdict = .fail ↔ 0 < (tally vs).failing := by
  simp only [tally, rollup_fail_iff, List.countP_pos_iff, beq_iff_eq, exists_eq_right]

/-- Not comparable iff no probe was comparable.

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs).\mathrm{verdict} = \mathrm{nc} \iff \operatorname{tally}(vs).\mathrm{total} = 0$$

`NC` is printed exactly when the comparable count is zero. -/
theorem tally_nc_iff (vs : List Verdict) : (tally vs).verdict = .nc ↔ (tally vs).total = 0 := by
  simp only [tally, rollup_nc_iff, List.countP_eq_zero, bne_iff_ne, ne_eq, Decidable.not_not]

/-- Pass iff no probe fails and some probe was comparable.

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs).\mathrm{verdict} = \mathrm{pass} \iff \operatorname{tally}(vs).\mathrm{failing} = 0 \wedge 0 < \operatorname{tally}(vs).\mathrm{total}$$

`pass` is printed exactly when nothing failed and something was compared. -/
theorem tally_pass_iff (vs : List Verdict) :
    (tally vs).verdict = .pass ↔ (tally vs).failing = 0 ∧ 0 < (tally vs).total := by
  have hf := tally_fail_iff vs
  have hn := tally_nc_iff vs
  cases h : (tally vs).verdict
  · have a : ¬ 0 < (tally vs).failing := fun x => by have := hf.mpr x; rw [h] at this; cases this
    have b : ¬ (tally vs).total = 0 := fun x => by have := hn.mpr x; rw [h] at this; cases this
    simp only [true_iff]; omega
  · have := hf.mp h; simp only [reduceCtorEq, false_iff]; omega
  · have := hn.mp h; simp only [reduceCtorEq, false_iff]; omega

#guard cellVerdict [] == .nc
#guard cellVerdict [.na, .na] == .nc
#guard cellVerdict [.equal, .equal] == .pass
#guard cellVerdict [.equal, .na, .equal] == .pass
#guard cellVerdict [.equal, .differ] == .fail
#guard cellVerdict [.equal, .missing] == .fail
#guard cellVerdict [.na, .missing] == .fail
#guard rollup [.pass, .nc, .pass] == .pass
#guard rollup [.pass, .fail] == .fail
#guard rollup [.nc] == .nc
#guard rollup [] == .nc
#guard tally [.pass, .fail, .nc, .fail] == { verdict := .fail, failing := 2, total := 3 }

end Fw.Gate
