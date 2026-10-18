import Fw.Measure.WktrLayout
/-!
# Run-to-run variance of the WKTR fixture lane (task `wktr-serial-baseline`)

The fixture lane (`.github/workflows/wktr-fixtures.yml`) classes every count type of every cell (a **key**: arm, variant,
type) from the passes of one workflow run. Two runs of the same code, both serial, need not give the same *kind* of class
for every key: a noisy type (`layoutUpdates`, `compositingUpdates`) can be `stable` in one run and `quarantined` in the next.
`wktr-fixture-speed` found 12 of 144 keys that differed from an earlier run and called that run-to-run variance without a
baseline to back it. This module decides that question.

* A **table** is one run's kind of class per key (keys are unique within a table).
* `differs a b` are the keys whose kind differs between two tables (or that exist in one only).
* `varying rs` are the keys whose kind is not the same in every one of the runs `rs` (same code, serial).
* A diff between a baseline and a candidate is a **finding** only on a key outside `varying rs`: a key that already varies
  between same-code serial runs is explained by variance and is not a finding.
* `verdict`: with at least 2 serial baselines and no finding the claim is `measured`; with fewer baselines it is
  `noBaseline`; otherwise `unexplained` (the claim is downgraded to the unexplained keys).

Proved: a diff between two members of the baseline set is never a finding (`findings_of_mem`); more baselines can only
remove findings (`findings_anti`); the verdict is `measured` exactly when two baselines exist and no finding remains
(`claim_measured_iff`). The timing claim ("no per-job change in step time") uses `overlap` of the sample ranges.

Lean specifies and proves; the tables are CI measurements and the kinds are `Fw.Measure.WktrLayout.Kind`.
-/
namespace Fw.Measure.WktrVariance
open Fw.Measure.WktrLayout

/-- A table: the kind of class per key (arm, variant, type joined by `/`), keys unique.

$$\mathrm{Table} = \mathrm{Key} \rightharpoonup \mathrm{Kind}$$
-/
abbrev Table := List (String × Kind)

/-- The keys of two tables, each once (`b`'s keys not already in `a`).

$$\operatorname{keys}(a, b) = \operatorname{dom}(a) \cup \operatorname{dom}(b)$$
-/
def keys (a b : Table) : List String := a.map Prod.fst ++ (b.map Prod.fst).filter (fun k => !(a.map Prod.fst).contains k)

/-- The keys whose kind of class differs between two tables, or that exist on one side only.

$$\operatorname{differs}(a, b) = \{k \mid a[k] \ne b[k]\}$$
-/
def differs (a b : Table) : List String := (keys a b).filter (fun k => a.lookup k != b.lookup k)

/-- A key absent from both tables looks up to the same nothing, so a differing key is in one of them.

$$a[k] \ne b[k] \Rightarrow k \in \operatorname{dom}(a) \lor k \in \operatorname{dom}(b)$$
-/
theorem key_of_ne (a b : Table) (k : String) (h : a.lookup k ≠ b.lookup k) : (∃ p ∈ a, p.1 = k) ∨ (∃ p ∈ b, p.1 = k) := by
  refine Classical.byContradiction fun hn => ?_
  rw [not_or] at hn
  have h1 : a.lookup k = none := by
    rw [List.lookup_eq_none_iff]
    intro p hp
    simp only [bne_iff_ne, ne_eq]
    intro e
    exact hn.1 ⟨p, hp, e.symm⟩
  have h2 : b.lookup k = none := by
    rw [List.lookup_eq_none_iff]
    intro p hp
    simp only [bne_iff_ne, ne_eq]
    intro e
    exact hn.2 ⟨p, hp, e.symm⟩
  exact h (by rw [h1, h2])

/-- A key is in `differs` exactly when the two lookups disagree.

$$k \in \operatorname{differs}(a, b) \iff a[k] \ne b[k]$$
-/
theorem mem_differs (a b : Table) (k : String) : k ∈ differs a b ↔ a.lookup k ≠ b.lookup k := by
  unfold differs keys
  rw [List.mem_filter]
  constructor
  · intro h
    simpa using h.2
  · intro h
    have h' : (a.lookup k != b.lookup k) = true := by simpa using h
    refine ⟨?_, h'⟩
    by_cases ha : ∃ p ∈ a, p.1 = k
    · obtain ⟨p, hp, e⟩ := ha
      exact List.mem_append_left _ (List.mem_map.2 ⟨p, hp, e⟩)
    · obtain ⟨p, hp, e⟩ := (key_of_ne a b k h).resolve_left ha
      apply List.mem_append_right
      rw [List.mem_filter]
      refine ⟨List.mem_map.2 ⟨p, hp, e⟩, ?_⟩
      simp
      intro q hq
      exact ha ⟨(k, q), hq, rfl⟩


/-- The diff of two tables is symmetric: the baseline and the candidate play the same role.

$$k \in \operatorname{differs}(a, b) \iff k \in \operatorname{differs}(b, a)$$
-/
theorem differs_comm (a b : Table) (k : String) : k ∈ differs a b ↔ k ∈ differs b a := by
  rw [mem_differs, mem_differs]
  exact ⟨fun h e => h e.symm, fun h e => h e.symm⟩

/-- A table does not differ from itself.

$$\operatorname{differs}(a, a) = \emptyset$$
-/
theorem differs_self (a : Table) : differs a a = [] := by
  rw [List.eq_nil_iff_forall_not_mem]
  intro k hk
  exact ((mem_differs a a k).1 hk) rfl

/-- The keys whose kind is not the same in every run of the set: two runs of the set that disagree on the key.

$$\operatorname{varying}(R) = \{k \mid \exists r, s \in R:\ r[k] \ne s[k]\}$$
-/
def varying (rs : List Table) : List String :=
  (rs.flatMap (·.map Prod.fst)).filter (fun k => rs.any (fun r => rs.any (fun s => r.lookup k != s.lookup k)))

/-- A key varies exactly when two runs of the set disagree on it.

$$k \in \operatorname{varying}(R) \iff \exists r, s \in R:\ r[k] \ne s[k]$$
-/
theorem mem_varying (rs : List Table) (k : String) :
    k ∈ varying rs ↔ ∃ r ∈ rs, ∃ s ∈ rs, r.lookup k ≠ s.lookup k := by
  unfold varying
  simp only [List.mem_filter, List.any_eq_true, bne_iff_ne, ne_eq, List.mem_flatMap, List.mem_map]
  constructor
  · rintro ⟨_, r, hr, s, hs, h⟩
    exact ⟨r, hr, s, hs, h⟩
  · rintro ⟨r, hr, s, hs, h⟩
    refine ⟨?_, r, hr, s, hs, h⟩
    rcases key_of_ne r s k h with ⟨p, hp, e⟩ | ⟨p, hp, e⟩
    · exact ⟨r, hr, p, hp, e⟩
    · exact ⟨s, hs, p, hp, e⟩

/-- More runs in the set can only add varying keys.

$$R \subseteq R' \Rightarrow \operatorname{varying}(R) \subseteq \operatorname{varying}(R')$$
-/
theorem varying_mono {rs rs' : List Table} (h : ∀ r, r ∈ rs → r ∈ rs') : ∀ k, k ∈ varying rs → k ∈ varying rs' := by
  intro k hk
  rw [mem_varying] at hk ⊢
  obtain ⟨r, hr, s, hs, hne⟩ := hk
  exact ⟨r, h r hr, s, h s hs, hne⟩

/-- The **findings**: the keys on which the baseline and the candidate differ and which do not vary among the same-code serial
runs.

$$\operatorname{findings}(b, c, R) = \operatorname{differs}(b, c) \setminus \operatorname{varying}(R)$$
-/
def findings (base cand : Table) (rs : List Table) : List String :=
  (differs base cand).filter (fun k => !(varying rs).contains k)

/-- A finding is a key that differs and does not vary.

$$k \in \operatorname{findings}(b, c, R) \iff b[k] \ne c[k] \ \land\ k \notin \operatorname{varying}(R)$$
-/
theorem mem_findings (base cand : Table) (rs : List Table) (k : String) :
    k ∈ findings base cand rs ↔ base.lookup k ≠ cand.lookup k ∧ k ∉ varying rs := by
  unfold findings
  rw [List.mem_filter, mem_differs]
  simp

/-- **No findings iff every diff is a varying key.**

$$\operatorname{findings}(b, c, R) = \emptyset \iff \operatorname{differs}(b, c) \subseteq \operatorname{varying}(R)$$
-/
theorem findings_nil_iff (base cand : Table) (rs : List Table) :
    findings base cand rs = [] ↔ ∀ k, k ∈ differs base cand → k ∈ varying rs := by
  rw [List.eq_nil_iff_forall_not_mem]
  constructor
  · intro h k hk
    refine Classical.byContradiction fun hv => ?_
    exact h k ((mem_findings base cand rs k).2 ⟨(mem_differs base cand k).1 hk, hv⟩)
  · intro h k hk
    rw [mem_findings] at hk
    exact hk.2 (h k ((mem_differs base cand k).2 hk.1))

/-- **Yardstick soundness.** A diff between two runs that are both in the baseline set is never a finding: the set explains
every diff among its own members.

$$b, c \in R \Rightarrow \operatorname{findings}(b, c, R) = \emptyset$$
-/
theorem findings_of_mem {base cand : Table} {rs : List Table} (hb : base ∈ rs) (hc : cand ∈ rs) :
    findings base cand rs = [] := by
  rw [findings_nil_iff]
  intro k hk
  rw [mem_varying]
  exact ⟨base, hb, cand, hc, (mem_differs base cand k).1 hk⟩

/-- **More baselines, fewer findings.**

$$R \subseteq R' \Rightarrow \operatorname{findings}(b, c, R') \subseteq \operatorname{findings}(b, c, R)$$
-/
theorem findings_anti {rs rs' : List Table} (h : ∀ r, r ∈ rs → r ∈ rs') (base cand : Table) :
    ∀ k, k ∈ findings base cand rs' → k ∈ findings base cand rs := by
  intro k hk
  rw [mem_findings] at hk ⊢
  exact ⟨hk.1, fun hv => hk.2 (varying_mono h k hv)⟩

/-- A finding is a diff.

$$\operatorname{findings}(b, c, R) \subseteq \operatorname{differs}(b, c)$$
-/
theorem findings_sub_differs (base cand : Table) (rs : List Table) :
    ∀ k, k ∈ findings base cand rs → k ∈ differs base cand := by
  intro k hk
  rw [mem_findings] at hk
  exact (mem_differs base cand k).2 hk.1

/-- **Coarser yardstick.** The same findings with keys compared through a projection `f` (the count type of a key, say): a diff is
explained when some varying key has the same image.

$$\operatorname{findings}_f(b, c, R) = \{k \in \operatorname{differs}(b, c) \mid f(k) \notin f[\operatorname{varying}(R)]\}$$
-/
def findingsBy (f : String → String) (base cand : Table) (rs : List Table) : List String :=
  (differs base cand).filter (fun k => !((varying rs).map f).contains (f k))

/-- A projected finding is a diff with no varying key of the same image.

$$k \in \operatorname{findings}_f(b, c, R) \iff b[k] \ne c[k] \ \land\ \forall j \in \operatorname{varying}(R):\ f(j) \ne f(k)$$
-/
theorem mem_findingsBy (f : String → String) (base cand : Table) (rs : List Table) (k : String) :
    k ∈ findingsBy f base cand rs ↔ base.lookup k ≠ cand.lookup k ∧ ∀ j, j ∈ varying rs → f j ≠ f k := by
  unfold findingsBy
  rw [List.mem_filter, mem_differs]
  simp only [Bool.not_eq_true']
  refine and_congr Iff.rfl ?_
  constructor
  · intro h j hj e
    have hc : ((varying rs).map f).contains (f k) = true := List.contains_iff_mem.2 (List.mem_map.2 ⟨j, hj, e⟩)
    rw [h] at hc
    exact absurd hc (by decide)
  · intro h
    cases hc : ((varying rs).map f).contains (f k)
    · rfl
    · obtain ⟨j, hj, e⟩ := List.mem_map.1 (List.contains_iff_mem.1 hc)
      exact absurd e (h j hj)

/-- **A coarser yardstick explains at least as much**: every projected finding is a key finding.

$$\operatorname{findings}_f(b, c, R) \subseteq \operatorname{findings}(b, c, R)$$
-/
theorem findingsBy_sub (f : String → String) (base cand : Table) (rs : List Table) :
    ∀ k, k ∈ findingsBy f base cand rs → k ∈ findings base cand rs := by
  intro k hk
  rw [mem_findingsBy] at hk
  rw [mem_findings]
  exact ⟨hk.1, fun hv => hk.2 k hv rfl⟩

/-- With the identity projection the findings are the key findings.

$$\operatorname{findings}_{\mathrm{id}}(b, c, R) = \operatorname{findings}(b, c, R)$$
-/
theorem findingsBy_id (base cand : Table) (rs : List Table) (k : String) :
    k ∈ findingsBy id base cand rs ↔ k ∈ findings base cand rs := by
  rw [mem_findingsBy, mem_findings]
  constructor
  · intro h
    exact ⟨h.1, fun hv => h.2 k hv rfl⟩
  · intro h
    refine ⟨h.1, fun j hj e => h.2 ?_⟩
    have e' : j = k := e
    exact e' ▸ hj

/-- The count type of a key `arm/variant/type`: the last `/` part.

$$\operatorname{typeOf}(\text{arm}/\text{variant}/\text{type}) = \text{type}$$
-/
def typeOf (k : String) : String := (k.splitOn "/").getLast?.getD k

#guard typeOf "control-f1/live/layoutUpdates" == "layoutUpdates" && typeOf "x" == "x"

/-- The status of the claim "the diffs are run-to-run variance".

$$\mathrm{Verdict} = \{\mathrm{measured}, \mathrm{unexplained}, \mathrm{noBaseline}\}$$
-/
inductive Verdict where
  | measured | unexplained | noBaseline
deriving Repr, DecidableEq

/-- The verdict from the number of serial baselines and the findings: fewer than two baselines measure no variance.

$$\operatorname{verdict}(n, F) = \begin{cases} \mathrm{noBaseline} & n < 2 \\ \mathrm{measured} & n \ge 2 \wedge F = \emptyset \\ \mathrm{unexplained} & \text{otherwise} \end{cases}$$
-/
def verdict (n : Nat) (fs : List String) : Verdict :=
  if n < 2 then .noBaseline else if fs.isEmpty then .measured else .unexplained

/-- The claim about a baseline and a candidate over a set of serial runs.

$$\operatorname{claim}(b, c, R) = \operatorname{verdict}(|R|, \operatorname{findings}(b, c, R))$$
-/
def claim (base cand : Table) (rs : List Table) : Verdict := verdict rs.length (findings base cand rs)

/-- **The claim is measured exactly when there are two baselines and every diff varies.**

$$\operatorname{claim}(b, c, R) = \mathrm{measured} \iff |R| \ge 2 \ \land\ \operatorname{differs}(b, c) \subseteq \operatorname{varying}(R)$$
-/
theorem claim_measured_iff (base cand : Table) (rs : List Table) :
    claim base cand rs = .measured ↔ 2 ≤ rs.length ∧ ∀ k, k ∈ differs base cand → k ∈ varying rs := by
  unfold claim verdict
  rw [← findings_nil_iff]
  by_cases h : rs.length < 2
  · simp [h]; omega
  · have h2 : 2 ≤ rs.length := by omega
    simp [h, h2, List.isEmpty_iff]

/-- With fewer than two baselines the claim is never measured.

$$|R| < 2 \Rightarrow \operatorname{claim}(b, c, R) \ne \mathrm{measured}$$
-/
theorem claim_needs_two (base cand : Table) (rs : List Table) (h : rs.length < 2) : claim base cand rs ≠ .measured := by
  intro hm
  have := ((claim_measured_iff base cand rs).1 hm).1
  omega

/-- The claim at the coarser yardstick `f`.

$$\operatorname{claim}_f(b, c, R) = \operatorname{verdict}(|R|, \operatorname{findings}_f(b, c, R))$$
-/
def claimBy (f : String → String) (base cand : Table) (rs : List Table) : Verdict :=
  verdict rs.length (findingsBy f base cand rs)

/-- **The coarser claim never loses a measured key claim.**

$$\operatorname{claim}(b, c, R) = \mathrm{measured} \Rightarrow \operatorname{claim}_f(b, c, R) = \mathrm{measured}$$
-/
theorem claimBy_of_claim (f : String → String) (base cand : Table) (rs : List Table)
    (h : claim base cand rs = .measured) : claimBy f base cand rs = .measured := by
  have h2 := (claim_measured_iff base cand rs).1 h
  have hn : findingsBy f base cand rs = [] := by
    rw [List.eq_nil_iff_forall_not_mem]
    intro k hk
    have hf := findingsBy_sub f base cand rs k hk
    rw [(findings_nil_iff base cand rs).2 h2.2] at hf
    exact absurd hf (by simp)
  have h3 : ¬ rs.length < 2 := by omega
  unfold claimBy verdict
  rw [hn]
  simp [h3]

/-- The diff counts of every pair of runs (the spread of the run-to-run variance).

$$\operatorname{pairDiffs}(r_1 \dots r_n) = [\,|\operatorname{differs}(r_i, r_j)|\,]_{i<j}$$
-/
def pairDiffs : List Table → List Nat
  | [] => []
  | r :: rest => rest.map (fun s => (differs r s).length) ++ pairDiffs rest

/-- Closed intervals `[lo, hi]` of samples (step seconds of a job, say) overlap iff neither lies wholly below the other.

$$[l_1, h_1] \cap [l_2, h_2] \ne \emptyset \iff l_1 \le h_2 \ \land\ l_2 \le h_1$$
-/
def overlap (a b : Nat × Nat) : Bool := a.1 ≤ b.2 && b.1 ≤ a.2

/-- Overlap is symmetric.

$$\operatorname{overlap}(a, b) = \operatorname{overlap}(b, a)$$
-/
theorem overlap_comm (a b : Nat × Nat) : overlap a b = overlap b a := by
  unfold overlap
  exact Bool.and_comm _ _

/-- Two non-empty ranges that share a value overlap.

$$x \in [l_1, h_1] \cap [l_2, h_2] \Rightarrow \operatorname{overlap}$$
-/
theorem overlap_of_mem (a b : Nat × Nat) (x : Nat) (h1 : a.1 ≤ x ∧ x ≤ a.2) (h2 : b.1 ≤ x ∧ x ≤ b.2) :
    overlap a b = true := by
  unfold overlap
  simp only [Bool.and_eq_true, decide_eq_true_eq]
  omega

/-- The range `(min, max)` of a non-empty sample.

$$\operatorname{range}(xs) = (\min xs, \max xs)$$
-/
def rangeOf (xs : List Nat) : Option (Nat × Nat) :=
  match xs.min?, xs.max? with
  | some l, some h => some (l, h)
  | _, _ => none

private def t1 : Table := [("a", .det), ("b", .stable), ("c", .quar)]
private def t2 : Table := [("a", .det), ("b", .quar), ("c", .quar), ("d", .det)]
private def t3 : Table := [("a", .det), ("b", .quar), ("c", .stable)]

#guard (differs t1 t2) == ["b", "d"]
#guard (differs t1 t1).isEmpty
#guard (varying [t1, t2]).eraseDups == ["b", "d"]
#guard (findings t1 t3 [t1, t2]) == ["c"]
#guard (findings t1 t2 [t1, t2]).isEmpty
#guard claim t1 t2 [t1, t2] == .measured
#guard claim t1 t3 [t1, t2] == .unexplained
#guard claim t1 t2 [t1] == .noBaseline
#guard pairDiffs [t1, t2, t3] == [2, 2, 2]
#guard overlap (687, 874) (572, 976) && !overlap (1, 2) (3, 4)
#guard rangeOf [3, 1, 2] == some (1, 3) && (rangeOf []).isNone

private def u1 : Table := [("a/live/lu", .det), ("b/live/lu", .quar), ("a/live/sr", .det)]
private def u2 : Table := [("a/live/lu", .stable), ("b/live/lu", .quar), ("a/live/sr", .det)]
private def u3 : Table := [("a/live/lu", .det), ("b/live/lu", .stable), ("a/live/sr", .det)]
private def u4 : Table := [("a/live/lu", .det), ("b/live/lu", .quar), ("a/live/sr", .stable)]

#guard findings u1 u3 [u1, u2] == ["b/live/lu"]
#guard (findingsBy typeOf u1 u3 [u1, u2]).isEmpty
#guard claimBy typeOf u1 u3 [u1, u2] == .measured && claim u1 u3 [u1, u2] == .unexplained
#guard findingsBy typeOf u1 u4 [u1, u2] == ["a/live/sr"]

end Fw.Measure.WktrVariance
