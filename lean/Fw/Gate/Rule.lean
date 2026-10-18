/-!
# The breakpoint gate's pass/fail rule (PLAN 6.6)

Port of `cellVerdict`, `verdictToStatus` and `rollup` from `packages/gate-breakpoints/src/verdict.mjs`.
Every compared item of a probe gets a `Status`; a cell (one table row at one probe, block or sweep)
gets a `Verdict`:

* no applicable item (empty, or every item `na`) gives `nc` (not comparable);
* some applicable item is not `equal` gives `fail`;
* otherwise `pass`.

A fourth verdict, `unreachable r`, marks a cell the engine port cannot produce, for a reason `r`
proved in `Fw.Gate.Reach` (never a runtime guess). The rule itself never gives it.

Rollups (probe verdicts to a block or sweep cell, row verdicts to a state) reuse the same rule
through `toStatus` (`pass ↦ equal`, `fail ↦ differ`, `nc ↦ na`, `unreachable ↦ na`), except that a
non-empty list of only unreachable verdicts rolls up to `unreachable` with the first reason in a
fixed order. `Tally` adds the counts the table prints; only `pass` and `fail` count as compared.

Proved: the three characterisations (`cellVerdict_nc_iff`, `cellVerdict_fail_iff`,
`cellVerdict_pass_iff`), that only the set of statuses matters (`cellVerdict_congr`, so any
reordering of the rows gives the same verdict: `cellVerdict_perm`), that `na` items never matter
(`cellVerdict_filter_na`), the four rollup cases (`rollup_fail_iff`, `rollup_pass_iff`,
`rollup_nc_iff`, `rollup_unreachable_iff`), order independence (`rollup_congr`, `rollup_perm`),
that rolling up per-group verdicts equals the verdict of all items at once (`rollup_flatten`),
that unreachable rows never pass or fail anything (`rollup_filter_unreachable`,
`tally_filter_unreachable`, `tally_counts`), and that the printed counts agree with the verdict
(`tally_*_iff`).
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

/-- Why a cell cannot be measured on an engine port (`Fw.Gate.Reach` proves each one).

$$\mathcal R = \{\mathrm{primaryPair}, \mathrm{wholeWidth}, \mathrm{widthDpr}\}$$

The port has no such primary hover/pointer pair, its media width is whole but the probe's is not,
or its device pixels are whole but width times dpr is not. -/
inductive Reason where
  | primaryPair
  | wholeWidth
  | widthDpr
  deriving DecidableEq, Repr, Inhabited

/-- Verdict of a cell: the three outcomes of the rule, or unreachable on the port for a reason.

$$\mathcal V = \{\mathrm{pass}, \mathrm{fail}, \mathrm{nc}\} \cup \{\mathrm{unreachable}(r) \mid r \in \mathcal R\}$$

A table cell passes, fails, is not comparable, or cannot be reached on this engine port. -/
inductive Verdict where
  | pass
  | fail
  | nc
  | unreachable (r : Reason)
  deriving DecidableEq, Repr, Inhabited

/-- Whether a verdict is `unreachable` (for any reason).

$$\forall v \in \mathcal V,\quad \operatorname{isU}(v) \iff \exists r \in \mathcal R,\ v = \mathrm{unreachable}(r)$$

True only for the unreachable verdicts. -/
def Verdict.isUnreachable : Verdict → Bool
  | .unreachable _ => true
  | _ => false

/-- Whether a verdict counts as compared: `pass` or `fail`.

$$\forall v \in \mathcal V,\quad \operatorname{isC}(v) \iff v \in \{\mathrm{pass}, \mathrm{fail}\}$$

Only passing and failing cells enter the compared count. -/
def Verdict.isComparable : Verdict → Bool
  | .pass | .fail => true
  | _ => false

/-- **The rule.** Let $A$ be the statuses that are not `na`: not comparable if $A$ is empty, fail if
some status in $A$ is not `equal`, pass otherwise.

$$\operatorname{cell}(ss) = \begin{cases} \mathrm{nc} & A = [\,] \\ \mathrm{pass} & A \ne [\,] \wedge \forall s \in A,\ s = \mathrm{equal} \\ \mathrm{fail} & \text{otherwise} \end{cases}, \qquad A = [\, s \in ss \mid s \ne \mathrm{na} \,]$$

A cell passes when it compared something and everything it compared was equal. -/
def cellVerdict (ss : List Status) : Verdict :=
  let a := ss.filter (· != .na)
  if a.isEmpty then .nc else if a.all (· == .equal) then .pass else .fail

/-- A verdict as a status, so verdicts roll up with the same rule.

$$\mathrm{pass} \mapsto \mathrm{equal},\quad \mathrm{fail} \mapsto \mathrm{differ},\quad \mathrm{nc} \mapsto \mathrm{na},\quad \forall r \in \mathcal R,\ \mathrm{unreachable}(r) \mapsto \mathrm{na}$$

A passing probe counts as an equal item, a failing one as a differing item, an incomparable or
unreachable one not at all. -/
def toStatus : Verdict → Status
  | .pass => .equal
  | .fail => .differ
  | .nc => .na
  | .unreachable _ => .na

/-- The reason a fully unreachable rollup reports: the first of `primaryPair`, `wholeWidth`,
`widthDpr` that occurs among the verdicts (`widthDpr` when none occurs).

$$\forall vs \in \mathcal V^*,\quad \rho(vs) = \begin{cases} \mathrm{primaryPair} & \mathrm{unreachable}(\mathrm{primaryPair}) \in vs \\ \mathrm{wholeWidth} & \text{else, if } \mathrm{unreachable}(\mathrm{wholeWidth}) \in vs \\ \mathrm{widthDpr} & \text{otherwise} \end{cases}$$

A fixed order of reasons, so the reported reason does not depend on row order. -/
def unreachableReason (vs : List Verdict) : Reason :=
  if vs.contains (.unreachable .primaryPair) then .primaryPair
  else if vs.contains (.unreachable .wholeWidth) then .wholeWidth
  else .widthDpr

/-- Verdict of a list of verdicts (a block of probes, the rows of a state, or the stops of a
sweep): unreachable when every verdict is, else the rule over their statuses.

$$\forall vs \in \mathcal V^*,\quad \operatorname{rollup}(vs) = \begin{cases} \mathrm{unreachable}(\rho(vs)) & vs \ne [\,] \wedge \forall v \in vs,\ \operatorname{isU}(v) \\ \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs) & \text{otherwise} \end{cases}$$

A block passes when some probe passed and none failed; it is unreachable only when all of it is.

This lenient rollup is for display, State, Scope and the sweep reduction only. The gate's decision is per reading
(`Fw.Gate.Exit.rollup_pass_iff_all_readings`): a not-comparable reading next to a passing one is not absorbed there. -/
def rollup (vs : List Verdict) : Verdict :=
  if !vs.isEmpty && vs.all (·.isUnreachable) then .unreachable (unreachableReason vs)
  else cellVerdict (vs.map toStatus)

/-- A table cell as printed: the rolled-up verdict, the failing probes, the compared probes, the
unreachable probes.

$$t = (\mathit{verdict},\ \mathit{failing},\ \mathit{total},\ \mathit{unreachable}) \in \mathcal V \times \mathbb N^{3}$$

What `FAIL failing/total` in the summary table shows, plus the unreachable count. -/
structure Tally where
  verdict : Verdict
  failing : Nat
  total : Nat
  unreachable : Nat
  deriving DecidableEq, Repr

/-- The tally of a list of verdicts: only `pass` and `fail` count as compared.

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs) = \bigl(\operatorname{rollup}(vs),\ |[\,v \in vs \mid v = \mathrm{fail}\,]|,\ |[\,v \in vs \mid \operatorname{isC}(v)\,]|,\ |[\,v \in vs \mid \operatorname{isU}(v)\,]|\bigr)$$

The block cell with its counts. -/
def tally (vs : List Verdict) : Tally :=
  { verdict := rollup vs, failing := vs.countP (· == .fail), total := vs.countP (·.isComparable),
    unreachable := vs.countP (·.isUnreachable) }

/-! ## The three cases of the rule -/

/-- The rule never gives `unreachable`: only a proved fact does.

$$\forall ss \in \mathcal S^*,\quad \neg \operatorname{isU}(\operatorname{cell}(ss))$$

Comparing items yields pass, fail or not comparable, never unreachable. -/
theorem cellVerdict_isUnreachable (ss : List Status) : (cellVerdict ss).isUnreachable = false := by
  simp only [cellVerdict]
  split
  · rfl
  · split <;> rfl

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
    | unreachable r =>
      have := cellVerdict_isUnreachable ss
      rw [hv] at this; cases this

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
  | unreachable r =>
    have := cellVerdict_isUnreachable ss
    rw [hv] at this; cases this

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

/-- `toStatus` is `na` exactly on `nc` and the unreachable verdicts, and `equal` exactly on `pass`.

$$\forall v \in \mathcal V,\quad (\operatorname{toStatus}(v) = \mathrm{na} \iff v = \mathrm{nc} \vee \operatorname{isU}(v)) \wedge (\operatorname{toStatus}(v) = \mathrm{equal} \iff v = \mathrm{pass})$$

The rollup sees passes as equal items and skips incomparable and unreachable probes. -/
theorem toStatus_spec (v : Verdict) :
    (toStatus v = .na ↔ v = .nc ∨ v.isUnreachable = true) ∧ (toStatus v = .equal ↔ v = .pass) := by
  cases v <;> simp [toStatus, Verdict.isUnreachable]

/-- The rule over the statuses of verdicts fails exactly when some verdict fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs) = \mathrm{fail} \iff \mathrm{fail} \in vs$$

Only a failing verdict becomes a failing status. -/
theorem cellVerdict_map_fail_iff (vs : List Verdict) :
    cellVerdict (vs.map toStatus) = .fail ↔ .fail ∈ vs := by
  rw [cellVerdict_fail_iff]
  constructor
  · rintro ⟨s, hs, h1, h2⟩
    obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs
    cases v with
    | pass => exact absurd rfl h2
    | fail => exact hv
    | nc => exact absurd rfl h1
    | unreachable r => exact absurd rfl h1
  · intro h
    exact ⟨.differ, List.mem_map.mpr ⟨.fail, h, rfl⟩, by decide, by decide⟩

/-- The rule over the statuses of verdicts is not comparable exactly when no verdict passes or
fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs) = \mathrm{nc} \iff \mathrm{pass} \notin vs \wedge \mathrm{fail} \notin vs$$

Incomparable and unreachable verdicts are both skipped. -/
theorem cellVerdict_map_nc_iff (vs : List Verdict) :
    cellVerdict (vs.map toStatus) = .nc ↔ .pass ∉ vs ∧ .fail ∉ vs := by
  rw [cellVerdict_nc_iff]
  constructor
  · intro h
    exact ⟨fun hp => absurd (h _ (List.mem_map.mpr ⟨_, hp, rfl⟩)) (by decide),
      fun hf => absurd (h _ (List.mem_map.mpr ⟨_, hf, rfl⟩)) (by decide)⟩
  · rintro ⟨hp, hf⟩ s hs
    obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs
    cases v with
    | pass => exact absurd hv hp
    | fail => exact absurd hv hf
    | nc => rfl
    | unreachable r => rfl

/-- The rule over the statuses of verdicts passes exactly when some verdict passes and none fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs) = \mathrm{pass} \iff \mathrm{pass} \in vs \wedge \mathrm{fail} \notin vs$$

One pass and no fail make a pass. -/
theorem cellVerdict_map_pass_iff (vs : List Verdict) :
    cellVerdict (vs.map toStatus) = .pass ↔ .pass ∈ vs ∧ .fail ∉ vs := by
  have hf := cellVerdict_map_fail_iff vs
  have hn := cellVerdict_map_nc_iff vs
  have hu := cellVerdict_isUnreachable (vs.map toStatus)
  cases h : cellVerdict (vs.map toStatus) with
  | pass =>
    simp only [true_iff]
    have hf' : .fail ∉ vs := fun hm => by have := hf.mpr hm; rw [h] at this; cases this
    refine ⟨Classical.byContradiction fun hp => ?_, hf'⟩
    have := hn.mpr ⟨hp, hf'⟩
    rw [h] at this; cases this
  | fail => simp only [reduceCtorEq, false_iff]; exact fun ⟨_, hnf⟩ => hnf (hf.mp h)
  | nc => simp only [reduceCtorEq, false_iff]; exact fun ⟨hp, _⟩ => (hn.mp h).1 hp
  | unreachable r => rw [h] at hu; cases hu

/-- The two cases of a rollup: the rule over the statuses (when the list is empty or holds a
reachable verdict), or unreachable with reason $\rho$ (when the list is non-empty and all
unreachable).

$$\forall vs \in \mathcal V^*,\quad \bigl(\operatorname{rollup}(vs) = \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs) \wedge (vs = [\,] \vee \exists v \in vs,\ \neg \operatorname{isU}(v))\bigr) \vee \bigl(vs \ne [\,] \wedge (\forall v \in vs,\ \operatorname{isU}(v)) \wedge \operatorname{rollup}(vs) = \mathrm{unreachable}(\rho(vs))\bigr)$$

Every rollup is one of the two branches of its definition, with the branch condition. -/
theorem rollup_cases (vs : List Verdict) :
    (rollup vs = cellVerdict (vs.map toStatus) ∧ (vs = [] ∨ ∃ v ∈ vs, v.isUnreachable = false)) ∨
    (vs ≠ [] ∧ (∀ v ∈ vs, v.isUnreachable = true) ∧
      rollup vs = .unreachable (unreachableReason vs)) := by
  by_cases hc : ∃ v ∈ vs, v.isUnreachable = false
  · refine .inl ⟨?_, .inr hc⟩
    have : vs.all (·.isUnreachable) = false := List.all_eq_false.mpr (by simpa using hc)
    simp [rollup, this]
  · have ha : ∀ v ∈ vs, v.isUnreachable = true := fun v hv => by
      cases h : v.isUnreachable
      · exact absurd ⟨v, hv, h⟩ hc
      · rfl
    by_cases hne : vs = []
    · subst hne; exact .inl ⟨rfl, .inl rfl⟩
    · refine .inr ⟨hne, ha, ?_⟩
      have he : vs.isEmpty = false := by cases vs with | nil => exact absurd rfl hne | cons => rfl
      have hall : vs.all (·.isUnreachable) = true := List.all_eq_true.mpr ha
      simp [rollup, he, hall]

/-- A list holding a reachable verdict rolls up by the rule over its statuses.

$$\forall vs \in \mathcal V^*,\quad (\exists v \in vs,\ \neg \operatorname{isU}(v)) \implies \operatorname{rollup}(vs) = \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs)$$

One reachable row makes the cell an ordinary verdict. -/
theorem rollup_of_reachable (vs : List Verdict) (h : ∃ v ∈ vs, v.isUnreachable = false) :
    rollup vs = cellVerdict (vs.map toStatus) := by
  rcases rollup_cases vs with ⟨hr, _⟩ | ⟨_, ha, _⟩
  · exact hr
  · obtain ⟨v, hv, hu⟩ := h
    rw [ha v hv] at hu; cases hu

/-- A list with no unreachable verdict rolls up by the rule over its statuses.

$$\forall vs \in \mathcal V^*,\quad (\forall v \in vs,\ \neg \operatorname{isU}(v)) \implies \operatorname{rollup}(vs) = \operatorname{cell}(\operatorname{map}\ \operatorname{toStatus}\ vs)$$

Without unreachable rows the rollup is the old rule. -/
theorem rollup_no_unreachable (vs : List Verdict) (h : ∀ v ∈ vs, v.isUnreachable = false) :
    rollup vs = cellVerdict (vs.map toStatus) := by
  cases vs with
  | nil => rfl
  | cons v t => exact rollup_of_reachable _ ⟨v, List.mem_cons_self, h v List.mem_cons_self⟩

/-- The reported reason occurs in the list whenever some unreachable verdict does.

$$\forall vs \in \mathcal V^*,\quad (\exists r \in \mathcal R,\ \mathrm{unreachable}(r) \in vs) \implies \mathrm{unreachable}(\rho(vs)) \in vs$$

A rollup never invents a reason its rows do not carry. -/
theorem unreachableReason_mem (vs : List Verdict) (h : ∃ r, .unreachable r ∈ vs) :
    .unreachable (unreachableReason vs) ∈ vs := by
  obtain ⟨r, hr⟩ := h
  unfold unreachableReason
  by_cases h1 : vs.contains (.unreachable .primaryPair) = true
  · simp only [h1, ite_true]; exact List.contains_iff_mem.mp h1
  · by_cases h2 : vs.contains (.unreachable .wholeWidth) = true
    · simp only [h1, h2, ite_true, Bool.false_eq_true, ite_false]; exact List.contains_iff_mem.mp h2
    · simp only [h1, h2, Bool.false_eq_true, ite_false]
      cases r with
      | primaryPair => exact absurd (List.contains_iff_mem.mpr hr) h1
      | wholeWidth => exact absurd (List.contains_iff_mem.mpr hr) h2
      | widthDpr => exact hr

/-- A rollup is unreachable exactly when the list is non-empty and every verdict in it is
unreachable.

$$\forall vs \in \mathcal V^*,\quad (\exists r \in \mathcal R,\ \operatorname{rollup}(vs) = \mathrm{unreachable}(r)) \iff vs \ne [\,] \wedge \forall v \in vs,\ \operatorname{isU}(v)$$

One reachable row, or no row at all, keeps a cell out of the unreachable state. -/
theorem rollup_unreachable_iff (vs : List Verdict) :
    (∃ r, rollup vs = .unreachable r) ↔ vs ≠ [] ∧ ∀ v ∈ vs, v.isUnreachable = true := by
  rcases rollup_cases vs with ⟨hr, hc⟩ | ⟨hne, ha, hr⟩
  · rw [hr]
    constructor
    · rintro ⟨r, h⟩
      have := cellVerdict_isUnreachable (vs.map toStatus)
      rw [h] at this; cases this
    · rintro ⟨hne, ha⟩
      rcases hc with he | ⟨v, hv, hu⟩
      · exact absurd he hne
      · rw [ha v hv] at hu; cases hu
  · exact ⟨fun _ => ⟨hne, ha⟩, fun _ => ⟨_, hr⟩⟩

/-- An unreachable rollup carries a reason from its rows.

$$\forall vs \in \mathcal V^*,\ \forall r \in \mathcal R,\quad \operatorname{rollup}(vs) = \mathrm{unreachable}(r) \implies \mathrm{unreachable}(r) \in vs$$

The reason of a block is the reason of one of its probes. -/
theorem rollup_unreachable_mem (vs : List Verdict) (r : Reason) (h : rollup vs = .unreachable r) :
    .unreachable r ∈ vs := by
  rcases rollup_cases vs with ⟨hr, _⟩ | ⟨hne, ha, hr⟩
  · have := cellVerdict_isUnreachable (vs.map toStatus)
    rw [← hr, h] at this; cases this
  · rw [hr] at h
    cases h
    obtain ⟨v, t, rfl⟩ := List.exists_cons_of_ne_nil hne
    have hv := ha v List.mem_cons_self
    cases v with
    | unreachable r0 => exact unreachableReason_mem _ ⟨r0, List.mem_cons_self⟩
    | _ => cases hv

/-- A rollup fails exactly when some verdict fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{rollup}(vs) = \mathrm{fail} \iff \mathrm{fail} \in vs$$

One failing probe fails its block; unreachable probes never do. -/
theorem rollup_fail_iff (vs : List Verdict) : rollup vs = .fail ↔ .fail ∈ vs := by
  rcases rollup_cases vs with ⟨hr, _⟩ | ⟨_, ha, hr⟩
  · rw [hr, cellVerdict_map_fail_iff]
  · rw [hr]
    exact ⟨fun h => (by cases h), fun hm => (by have := ha _ hm; cases this)⟩

/-- A rollup passes exactly when some verdict passes and none fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{rollup}(vs) = \mathrm{pass} \iff \mathrm{pass} \in vs \wedge \mathrm{fail} \notin vs$$

A block passes when one probe passed and no probe failed; unreachable probes never pass it. -/
theorem rollup_pass_iff (vs : List Verdict) : rollup vs = .pass ↔ .pass ∈ vs ∧ .fail ∉ vs := by
  rcases rollup_cases vs with ⟨hr, _⟩ | ⟨_, ha, hr⟩
  · rw [hr, cellVerdict_map_pass_iff]
  · rw [hr]
    exact ⟨fun h => (by cases h), fun ⟨hm, _⟩ => (by have := ha _ hm; cases this)⟩

/-- A rollup is not comparable exactly when no verdict passes or fails and the list is empty or
holds an `nc`.

$$\forall vs \in \mathcal V^*,\quad \operatorname{rollup}(vs) = \mathrm{nc} \iff \mathrm{pass} \notin vs \wedge \mathrm{fail} \notin vs \wedge (vs = [\,] \vee \mathrm{nc} \in vs)$$

A block is incomparable when nothing in it was compared and not all of it is unreachable. -/
theorem rollup_nc_iff (vs : List Verdict) :
    rollup vs = .nc ↔ .pass ∉ vs ∧ .fail ∉ vs ∧ (vs = [] ∨ .nc ∈ vs) := by
  rcases rollup_cases vs with ⟨hr, hc⟩ | ⟨hne, ha, hr⟩
  · rw [hr, cellVerdict_map_nc_iff]
    constructor
    · rintro ⟨hp, hf⟩
      refine ⟨hp, hf, ?_⟩
      rcases hc with he | ⟨v, hv, hu⟩
      · exact .inl he
      · cases v with
        | pass => exact absurd hv hp
        | fail => exact absurd hv hf
        | nc => exact .inr hv
        | unreachable r => cases hu
    · rintro ⟨hp, hf, _⟩; exact ⟨hp, hf⟩
  · rw [hr]
    refine ⟨fun h => (by cases h), fun ⟨_, _, h⟩ => ?_⟩
    rcases h with he | hm
    · exact absurd he hne
    · have := ha _ hm; cases this

/-- A rollup depends only on which verdicts occur.

$$\forall vs, ws \in \mathcal V^*,\quad (\forall v,\ v \in vs \iff v \in ws) \implies \operatorname{rollup}(vs) = \operatorname{rollup}(ws)$$

Two blocks holding the same verdicts, in any order and multiplicity, roll up alike. -/
theorem rollup_congr (vs ws : List Verdict) (h : ∀ v, v ∈ vs ↔ v ∈ ws) : rollup vs = rollup ws := by
  have e1 : vs.isEmpty = ws.isEmpty := Bool.eq_iff_iff.mpr (by
    simp only [List.isEmpty_iff, List.eq_nil_iff_forall_not_mem, h])
  have e2 : vs.all (·.isUnreachable) = ws.all (·.isUnreachable) := Bool.eq_iff_iff.mpr (by
    simp only [List.all_eq_true, h])
  have hc : ∀ x, vs.contains x = ws.contains x := fun x => Bool.eq_iff_iff.mpr (by
    simp only [List.contains_iff_mem, h])
  have e3 : unreachableReason vs = unreachableReason ws := by simp only [unreachableReason, hc]
  have e4 : cellVerdict (vs.map toStatus) = cellVerdict (ws.map toStatus) :=
    cellVerdict_congr _ _ fun s => by simp only [List.mem_map, h]
  unfold rollup
  rw [e1, e2, e3, e4]

/-- Rollups ignore order: a permutation of the verdicts has the same rollup, unreachable reason
included.

$$\forall vs, ws \in \mathcal V^*,\quad vs \sim ws \implies \operatorname{rollup}(vs) = \operatorname{rollup}(ws)$$

Reordering the probes or rows of a cell keeps its verdict. -/
theorem rollup_perm (vs ws : List Verdict) (h : vs.Perm ws) : rollup vs = rollup ws :=
  rollup_congr vs ws fun _ => h.mem_iff

/-- Rolling up per-group verdicts is the verdict of all items at once.

$$\forall gs \in (\mathcal S^*)^*,\quad \operatorname{rollup}(\operatorname{map}\ \operatorname{cell}\ gs) = \operatorname{cell}(\operatorname{flatten}\ gs)$$

A block verdict equals the verdict over every item of every probe of the block. -/
theorem rollup_flatten (gs : List (List Status)) :
    rollup (gs.map cellVerdict) = cellVerdict gs.flatten := by
  rw [rollup_no_unreachable _ fun v hv => by
    obtain ⟨g, _, rfl⟩ := List.mem_map.mp hv
    exact cellVerdict_isUnreachable g]
  cases hv : cellVerdict gs.flatten with
  | fail =>
    obtain ⟨s, hs, h1, h2⟩ := (cellVerdict_fail_iff _).mp hv
    obtain ⟨g, hg, hsg⟩ := List.mem_flatten.mp hs
    exact (cellVerdict_map_fail_iff _).mpr
      (List.mem_map.mpr ⟨g, hg, (cellVerdict_fail_iff g).mpr ⟨s, hsg, h1, h2⟩⟩)
  | nc =>
    have h := (cellVerdict_nc_iff _).mp hv
    refine (cellVerdict_map_nc_iff _).mpr ⟨fun hm => ?_, fun hm => ?_⟩
    · obtain ⟨g, hg, hp⟩ := List.mem_map.mp hm
      obtain ⟨⟨s, hs, he⟩, _⟩ := (cellVerdict_pass_iff g).mp hp
      have := h s (List.mem_flatten.mpr ⟨g, hg, hs⟩)
      rw [he] at this; cases this
    · obtain ⟨g, hg, hf⟩ := List.mem_map.mp hm
      obtain ⟨s, hs, h1, _⟩ := (cellVerdict_fail_iff g).mp hf
      exact h1 (h s (List.mem_flatten.mpr ⟨g, hg, hs⟩))
  | pass =>
    obtain ⟨⟨s, hs, he⟩, hall⟩ := (cellVerdict_pass_iff _).mp hv
    obtain ⟨g, hg, hsg⟩ := List.mem_flatten.mp hs
    refine (cellVerdict_map_pass_iff _).mpr ⟨List.mem_map.mpr ⟨g, hg, (cellVerdict_pass_iff g).mpr
      ⟨⟨s, hsg, he⟩, fun t ht => hall t (List.mem_flatten.mpr ⟨g, hg, ht⟩)⟩⟩, fun hm => ?_⟩
    obtain ⟨g', hg', hf'⟩ := List.mem_map.mp hm
    obtain ⟨t, ht, h1, h2⟩ := (cellVerdict_fail_iff g').mp hf'
    rcases hall t (List.mem_flatten.mpr ⟨g', hg', ht⟩) with h | h
    · exact h1 h
    · exact h2 h
  | unreachable r =>
    have := cellVerdict_isUnreachable gs.flatten
    rw [hv] at this; cases this

/-- Unreachable rows never matter while a reachable row exists: dropping them keeps the rollup.

$$\forall vs \in \mathcal V^*,\quad (\exists v \in vs,\ \neg \operatorname{isU}(v)) \implies \operatorname{rollup}([\,v \in vs \mid \neg \operatorname{isU}(v)\,]) = \operatorname{rollup}(vs)$$

An unreachable probe can neither pass nor fail a block that has a reachable probe. -/
theorem rollup_filter_unreachable (vs : List Verdict) (h : ∃ v ∈ vs, v.isUnreachable = false) :
    rollup (vs.filter fun v => !v.isUnreachable) = rollup vs := by
  have key : ∀ x, x ∈ vs.filter (fun v => !v.isUnreachable) ↔ x ∈ vs ∧ x.isUnreachable = false := by
    intro x; simp only [List.mem_filter, Bool.not_eq_true']
  rw [rollup_of_reachable vs h, rollup_no_unreachable _ fun v hv => ((key v).mp hv).2]
  have hp : .pass ∈ vs.filter (fun v => !v.isUnreachable) ↔ .pass ∈ vs := by rw [key]; simp [Verdict.isUnreachable]
  have hf : .fail ∈ vs.filter (fun v => !v.isUnreachable) ↔ .fail ∈ vs := by rw [key]; simp [Verdict.isUnreachable]
  cases hv : cellVerdict (vs.map toStatus) with
  | pass =>
    obtain ⟨a, b⟩ := (cellVerdict_map_pass_iff vs).mp hv
    exact (cellVerdict_map_pass_iff _).mpr ⟨hp.mpr a, fun m => b (hf.mp m)⟩
  | fail => exact (cellVerdict_map_fail_iff _).mpr (hf.mpr ((cellVerdict_map_fail_iff vs).mp hv))
  | nc =>
    obtain ⟨a, b⟩ := (cellVerdict_map_nc_iff vs).mp hv
    exact (cellVerdict_map_nc_iff _).mpr ⟨fun m => a (hp.mp m), fun m => b (hf.mp m)⟩
  | unreachable r =>
    have := cellVerdict_isUnreachable (vs.map toStatus)
    rw [hv] at this; cases this

/-- The printed counts agree with the verdict: fail iff some probe fails.

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs).\mathrm{verdict} = \mathrm{fail} \iff 0 < \operatorname{tally}(vs).\mathrm{failing}$$

`FAIL n/m` is printed with n at least 1. -/
theorem tally_fail_iff (vs : List Verdict) : (tally vs).verdict = .fail ↔ 0 < (tally vs).failing := by
  simp only [tally, rollup_fail_iff, List.countP_pos_iff, beq_iff_eq, exists_eq_right]

/-- Pass iff no probe fails and some probe was compared (unreachable probes are not compared).

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs).\mathrm{verdict} = \mathrm{pass} \iff \operatorname{tally}(vs).\mathrm{failing} = 0 \wedge 0 < \operatorname{tally}(vs).\mathrm{total}$$

`pass` is printed exactly when nothing failed and something was compared. -/
theorem tally_pass_iff (vs : List Verdict) :
    (tally vs).verdict = .pass ↔ (tally vs).failing = 0 ∧ 0 < (tally vs).total := by
  simp only [tally, rollup_pass_iff, List.countP_eq_zero, List.countP_pos_iff, beq_iff_eq]
  constructor
  · rintro ⟨hp, hf⟩
    exact ⟨fun a ha he => hf (he ▸ ha), ⟨.pass, hp, rfl⟩⟩
  · rintro ⟨hf, a, ha, hc⟩
    refine ⟨?_, fun hm => hf _ hm rfl⟩
    cases a with
    | pass => exact ha
    | fail => exact absurd rfl (hf _ ha)
    | nc => cases hc
    | unreachable r => cases hc

/-- Unreachable iff some probe is counted and every probe is unreachable.

$$\forall vs \in \mathcal V^*,\quad (\exists r \in \mathcal R,\ \operatorname{tally}(vs).\mathrm{verdict} = \mathrm{unreachable}(r)) \iff 0 < \operatorname{tally}(vs).\mathrm{unreachable} \wedge \operatorname{tally}(vs).\mathrm{unreachable} = |vs|$$

A cell is printed unreachable exactly when all of its probes are. -/
theorem tally_unreachable_iff (vs : List Verdict) :
    (∃ r, (tally vs).verdict = .unreachable r) ↔
      0 < (tally vs).unreachable ∧ (tally vs).unreachable = vs.length := by
  simp only [tally]
  rw [rollup_unreachable_iff, List.countP_eq_length]
  constructor
  · rintro ⟨hne, ha⟩
    refine ⟨?_, ha⟩
    rw [List.countP_eq_length.mpr ha]
    exact List.length_pos_iff.mpr hne
  · rintro ⟨hpos, ha⟩
    refine ⟨fun he => ?_, ha⟩
    subst he; simp at hpos

/-- Not comparable iff nothing was compared and not every probe is unreachable (or there are
none).

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs).\mathrm{verdict} = \mathrm{nc} \iff \operatorname{tally}(vs).\mathrm{total} = 0 \wedge (\operatorname{tally}(vs).\mathrm{unreachable} < |vs| \vee vs = [\,])$$

`NC` is printed exactly when the compared count is zero and either some probe is reachable or there are no probes. -/
theorem tally_nc_iff (vs : List Verdict) :
    (tally vs).verdict = .nc ↔
      (tally vs).total = 0 ∧ ((tally vs).unreachable < vs.length ∨ vs = []) := by
  simp only [tally, rollup_nc_iff, List.countP_eq_zero]
  have hlt : vs.countP (·.isUnreachable) < vs.length ↔ ∃ v ∈ vs, v.isUnreachable = false := by
    have hle := List.countP_le_length (p := (·.isUnreachable)) (l := vs)
    have heq := List.countP_eq_length (p := (·.isUnreachable)) (l := vs)
    constructor
    · intro h
      apply Classical.byContradiction
      intro hn
      have : vs.countP (·.isUnreachable) = vs.length := heq.mpr fun v hv => by
        cases hu : v.isUnreachable
        · exact absurd ⟨v, hv, hu⟩ hn
        · rfl
      omega
    · rintro ⟨v, hv, hu⟩
      have : vs.countP (·.isUnreachable) ≠ vs.length := fun e => by
        have := heq.mp e v hv; rw [hu] at this; cases this
      omega
  rw [hlt]
  constructor
  · rintro ⟨hp, hf, h⟩
    refine ⟨fun a ha hc => ?_, ?_⟩
    · cases a with
      | pass => exact hp ha
      | fail => exact hf ha
      | nc => cases hc
      | unreachable r => cases hc
    · rcases h with he | hm
      · exact .inr he
      · exact .inl ⟨.nc, hm, rfl⟩
  · rintro ⟨hc, h⟩
    refine ⟨fun m => hc _ m rfl, fun m => hc _ m rfl, ?_⟩
    rcases h with ⟨v, hv, hu⟩ | he
    · cases v with
      | pass => exact absurd rfl (hc _ hv)
      | fail => exact absurd rfl (hc _ hv)
      | nc => exact .inr hv
      | unreachable r => cases hu
    · exact .inl he

/-- Every probe is counted exactly once: as compared, as unreachable, or as not comparable.

$$\forall vs \in \mathcal V^*,\quad \operatorname{tally}(vs).\mathrm{total} + \operatorname{tally}(vs).\mathrm{unreachable} + |[\,v \in vs \mid v = \mathrm{nc}\,]| = |vs|$$

An unreachable probe never enters the compared count `total`. -/
theorem tally_counts (vs : List Verdict) :
    (tally vs).total + (tally vs).unreachable + vs.countP (· == .nc) = vs.length := by
  simp only [tally]
  have one : ∀ v : Verdict, ((if v.isComparable = true then 1 else 0) +
      (if v.isUnreachable = true then 1 else 0) + (if (v == .nc) = true then 1 else 0) : Nat) = 1 := by
    intro v; cases v <;> rfl
  induction vs with
  | nil => rfl
  | cons v t ih =>
    simp only [List.countP_cons, List.length_cons]
    have := one v
    omega

/-- Unreachable probes never count as pass or fail: dropping them keeps both printed counts.

$$\forall vs \in \mathcal V^*,\quad \text{with } vs' = [\,v \in vs \mid \neg \operatorname{isU}(v)\,]:\quad \operatorname{tally}(vs').\mathrm{failing} = \operatorname{tally}(vs).\mathrm{failing} \wedge \operatorname{tally}(vs').\mathrm{total} = \operatorname{tally}(vs).\mathrm{total} \wedge \operatorname{tally}(vs').\mathrm{unreachable} = 0$$

Removing the unreachable probes of a block changes neither `failing` nor `total`. -/
theorem tally_filter_unreachable (vs : List Verdict) :
    (tally (vs.filter fun v => !v.isUnreachable)).failing = (tally vs).failing ∧
    (tally (vs.filter fun v => !v.isUnreachable)).total = (tally vs).total ∧
    (tally (vs.filter fun v => !v.isUnreachable)).unreachable = 0 := by
  simp only [tally, List.countP_filter]
  refine ⟨?_, ?_, ?_⟩
  · congr 1; funext v; cases v <;> rfl
  · congr 1; funext v; cases v <;> rfl
  · exact List.countP_eq_zero.mpr fun v _ => by cases v <;> simp [Verdict.isUnreachable]

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
#guard rollup [.unreachable .wholeWidth, .unreachable .primaryPair] == .unreachable .primaryPair
#guard rollup [.unreachable .widthDpr, .unreachable .wholeWidth] == .unreachable .wholeWidth
#guard rollup [.unreachable .widthDpr] == .unreachable .widthDpr
#guard rollup [.unreachable .primaryPair, .nc] == .nc
#guard rollup [.unreachable .primaryPair, .pass] == .pass
#guard rollup [.unreachable .primaryPair, .fail, .pass] == .fail
#guard unreachableReason [] == .widthDpr
#guard tally [.pass, .fail, .nc, .fail] == { verdict := .fail, failing := 2, total := 3, unreachable := 0 }
#guard tally [.pass, .unreachable .primaryPair, .nc] == { verdict := .pass, failing := 0, total := 1, unreachable := 1 }
#guard tally [.unreachable .wholeWidth, .unreachable .wholeWidth] ==
  { verdict := .unreachable .wholeWidth, failing := 0, total := 0, unreachable := 2 }
#guard (Verdict.unreachable .primaryPair).isUnreachable && !Verdict.nc.isUnreachable
#guard Verdict.pass.isComparable && Verdict.fail.isComparable && !Verdict.nc.isComparable &&
  !(Verdict.unreachable .widthDpr).isComparable
#guard toStatus (.unreachable .widthDpr) == .na

end Fw.Gate
