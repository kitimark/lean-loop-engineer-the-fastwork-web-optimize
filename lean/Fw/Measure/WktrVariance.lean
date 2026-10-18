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
* A **run** has an id; the `claim` about a baseline and a candidate uses the other runs of the set (`rivals`, by id) and
  counts them once per id (`nBaselines`): with at least 2 distinct rival runs and no finding it is `measured`; with fewer it
  is `noBaseline`; otherwise `unexplained`. The unit is the key: a key is explained only when that same key varies among the
  rivals. No coarser reading (a count type, say) decides a verdict; `typeOf` only labels keys in descriptive tables.

Proved: a diff between two members of the baseline set is never a finding (`findings_of_mem`), which is why the claim takes the
pair out of its own set (`claim_baseline_free`); more baselines can only remove findings (`findings_anti`); the verdict is
`measured` exactly when two distinct rival runs exist and no finding remains (`claim_measured_iff`); one run listed twice is
one baseline (`claim_repeat_not_measured`). The timing claim uses `overlap` of the sample ranges (`overlap_iff`).

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

/-- The count type of a key `arm/variant/type`: its last `/` part. Descriptive labelling of keys only; no verdict uses it.

$$\operatorname{typeOf}(s_1/\cdots/s_m) = s_m \qquad (m \ge 1,\ s_i \text{ free of } /)$$
-/
def typeOf (k : String) : String := (k.splitOn "/").getLast?.getD k

#guard typeOf "control-f1/live/layoutUpdates" == "layoutUpdates" && typeOf "x" == "x" && typeOf "a/b" == "b"

/-- The status of the claim "the diffs are run-to-run variance".

$$\mathrm{Verdict} = \{\mathrm{measured}, \mathrm{unexplained}, \mathrm{noBaseline}\}$$
-/
inductive Verdict where
  | measured | unexplained | noBaseline
deriving Repr, DecidableEq

/-- The verdict from the number of distinct baselines and the findings: fewer than two baselines measure no variance.

$$\operatorname{verdict}(n, F) = \begin{cases} \mathrm{noBaseline} & n < 2 \\ \mathrm{measured} & n \ge 2 \wedge F = \emptyset \\ \mathrm{unexplained} & \text{otherwise} \end{cases}$$
-/
def verdict (n : Nat) (fs : List String) : Verdict :=
  if n < 2 then .noBaseline else if fs.isEmpty then .measured else .unexplained

/-- A run: its id (the workflow run id) and its table. A run id names one table; the same id twice is one run.

$$\mathrm{Run} = \mathbb{N} \times \mathrm{Table}$$
-/
abbrev Run := Nat × Table

/-- The runs of the set `R` that are neither the baseline nor the candidate of the claim, decided by run id: a run never explains
its own diff.

$$\operatorname{rivals}(b, c, R) = \{ r \in R \mid \mathrm{id}(r) \ne \mathrm{id}(b) \ \land\ \mathrm{id}(r) \ne \mathrm{id}(c) \}$$
-/
def rivals (b c : Run) (rs : List Run) : List Run := rs.filter (fun r => r.1 != b.1 && r.1 != c.1)

/-- A run of the set is a rival exactly when it is in the set and has the id of neither side.

$$r \in \operatorname{rivals}(b, c, R) \iff r \in R \ \land\ \mathrm{id}(r) \ne \mathrm{id}(b) \ \land\ \mathrm{id}(r) \ne \mathrm{id}(c)$$
-/
theorem mem_rivals (b c : Run) (rs : List Run) (r : Run) :
    r ∈ rivals b c rs ↔ r ∈ rs ∧ r.1 ≠ b.1 ∧ r.1 ≠ c.1 := by
  unfold rivals
  simp [List.mem_filter]

/-- The number of distinct runs in a list: ids are counted once.

$$n(R) = \bigl|\{ \mathrm{id}(r) \mid r \in R \}\bigr|$$
-/
def nBaselines (rs : List Run) : Nat := (rs.map Prod.fst).eraseDups.length

/-- The claim about a baseline and a candidate over a set of serial runs: the rivals decide, counted by distinct id.

$$\operatorname{claim}(b, c, R) = \operatorname{verdict}\bigl(n(\operatorname{rivals}(b,c,R)),\ \operatorname{findings}(b, c, \operatorname{tables}(\operatorname{rivals}(b,c,R)))\bigr)$$
-/
def claim (b c : Run) (rs : List Run) : Verdict :=
  verdict (nBaselines (rivals b c rs)) (findings b.2 c.2 ((rivals b c rs).map Prod.snd))

/-- **The claim is measured exactly when there are two distinct rival runs and every diff varies among them.**

$$\operatorname{claim}(b, c, R) = \mathrm{measured} \iff n(\operatorname{rivals}(b,c,R)) \ge 2 \ \land\ \operatorname{differs}(b_2, c_2) \subseteq \operatorname{varying}(\operatorname{tables}(\operatorname{rivals}(b,c,R)))$$
-/
theorem claim_measured_iff (b c : Run) (rs : List Run) :
    claim b c rs = .measured ↔
      2 ≤ nBaselines (rivals b c rs) ∧ ∀ k, k ∈ differs b.2 c.2 → k ∈ varying ((rivals b c rs).map Prod.snd) := by
  unfold claim verdict
  rw [← findings_nil_iff]
  by_cases h : nBaselines (rivals b c rs) < 2
  · simp [h]; omega
  · have h2 : 2 ≤ nBaselines (rivals b c rs) := by omega
    simp [h, h2, List.isEmpty_iff]

/-- With fewer than two distinct rival runs the claim is never measured.

$$n(\operatorname{rivals}(b,c,R)) < 2 \Rightarrow \operatorname{claim}(b, c, R) \ne \mathrm{measured}$$
-/
theorem claim_needs_two (b c : Run) (rs : List Run) (h : nBaselines (rivals b c rs) < 2) : claim b c rs ≠ .measured := by
  intro hm
  have := ((claim_measured_iff b c rs).1 hm).1
  omega

/-- A pair of equal numbers has one distinct element.

$\operatorname{dedup}([n, n]) = [n]$
-/
theorem eraseDups_pair (n : Nat) : [n, n].eraseDups = [n] := by
  simp [List.eraseDups, List.eraseDupsBy, List.eraseDupsBy.loop]

/-- **One run listed twice is one baseline.**

$$\operatorname{claim}(b, c, [x, x]) \ne \mathrm{measured}$$
-/
theorem claim_repeat_not_measured (b c x : Run) : claim b c [x, x] ≠ .measured := by
  apply claim_needs_two
  unfold nBaselines rivals
  simp only [List.filter_cons, List.filter_nil]
  split <;> simp [eraseDups_pair]

/-- **The baseline never explains its own diff.** Adding the baseline run to the set changes nothing.

$$\operatorname{claim}(b, c, \{b\} \cup R) = \operatorname{claim}(b, c, R)$$
-/
theorem claim_baseline_free (b c : Run) (rs : List Run) : claim b c (b :: rs) = claim b c rs := by
  simp [claim, rivals]

/-- The diff count of every pair of runs, as a list of lengths of the `differs` lists, the pairs in lexicographic order of
position (`i` first, then `j`). A length counts list entries; it equals the number of differing keys when each table has
unique keys.

$$\operatorname{pairDiffs}(r_1, \dots, r_n) = \bigl[\ \operatorname{len}(\operatorname{differs}(r_i, r_j))\ \bigr]_{(i,j),\ 1 \le i < j \le n,\ \text{lexicographic}}$$
-/
def pairDiffs : List Table → List Nat
  | [] => []
  | r :: rest => rest.map (fun s => (differs r s).length) ++ pairDiffs rest

/-- Two pairs of numbers, read as closed intervals when `lo ≤ hi`, overlap when neither lies wholly below the other. This is the
definition over ℕ; for an interval with `lo > hi` it is only this test (`overlap_iff` gives the meaning for real intervals).

$$\operatorname{overlap}((l_1,h_1),(l_2,h_2)) = \mathrm{true} \iff l_1 \le h_2 \ \land\ l_2 \le h_1 \qquad (l_i, h_i \in \mathbb{N})$$
-/
def overlap (a b : Nat × Nat) : Bool := a.1 ≤ b.2 && b.1 ≤ a.2

/-- Overlap is symmetric.

$$\operatorname{overlap}(a, b) = \operatorname{overlap}(b, a)$$
-/
theorem overlap_comm (a b : Nat × Nat) : overlap a b = overlap b a := by
  unfold overlap
  exact Bool.and_comm _ _

/-- Two ranges that share a value overlap.

$$x \in [l_1, h_1] \cap [l_2, h_2] \Rightarrow \operatorname{overlap}((l_1,h_1),(l_2,h_2))$$
-/
theorem overlap_of_mem (a b : Nat × Nat) (x : Nat) (h1 : a.1 ≤ x ∧ x ≤ a.2) (h2 : b.1 ≤ x ∧ x ≤ b.2) :
    overlap a b = true := by
  unfold overlap
  simp only [Bool.and_eq_true, decide_eq_true_eq]
  omega

/-- **For non-empty intervals the test is the intersection.**

$$l_1 \le h_1 \ \land\ l_2 \le h_2 \Rightarrow \bigl(\operatorname{overlap}((l_1,h_1),(l_2,h_2)) = \mathrm{true} \iff [l_1,h_1] \cap [l_2,h_2] \ne \emptyset\bigr)$$
-/
theorem overlap_iff (a b : Nat × Nat) (ha : a.1 ≤ a.2) (hb : b.1 ≤ b.2) :
    overlap a b = true ↔ ∃ x, (a.1 ≤ x ∧ x ≤ a.2) ∧ (b.1 ≤ x ∧ x ≤ b.2) := by
  constructor
  · intro h
    unfold overlap at h
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨max a.1 b.1, ⟨Nat.le_max_left _ _, Nat.max_le.2 ⟨ha, h.2⟩⟩, ⟨Nat.le_max_right _ _, Nat.max_le.2 ⟨h.1, hb⟩⟩⟩
  · rintro ⟨x, h1, h2⟩
    exact overlap_of_mem a b x h1 h2

/-- The range of a sample: its minimum and maximum, or nothing for the empty sample.

$$\operatorname{range}(xs) = \begin{cases} \mathrm{some}(\min xs, \max xs) & xs \ne [\,] \\ \mathrm{none} & xs = [\,] \end{cases}$$
-/
def rangeOf (xs : List Nat) : Option (Nat × Nat) :=
  match xs.min?, xs.max? with
  | some l, some h => some (l, h)
  | _, _ => none

private def t1 : Table := [("a", .det), ("b", .stable), ("c", .quar)]
private def t2 : Table := [("a", .det), ("b", .quar), ("c", .quar), ("d", .det)]
private def t3 : Table := [("a", .det), ("b", .quar), ("c", .stable)]

private def r1 : Run := (1, t1)
private def r2 : Run := (2, t2)
private def r3 : Run := (3, t3)
private def r1' : Run := (4, t1)

#guard (differs t1 t2) == ["b", "d"]
#guard (differs t1 t1).isEmpty
#guard (varying [t1, t2]).eraseDups == ["b", "d"]
#guard (findings t1 t3 [t1, t2]) == ["c"]
#guard (findings t1 t2 [t1, t2]).isEmpty
#guard claim r1 r3 [r2, (5, t2)] == .unexplained
#guard claim r1 r3 [r2] == .noBaseline
#guard claim r1 r3 [r2, r2] == .noBaseline
#guard claim r1 (6, t2) [r2, r1', (7, t2)] == .measured
#guard claim r1 r2 [r1, r2, r3] == .noBaseline
#guard claim r1 r2 [r1, r2, r3, r1'] == .unexplained
#guard nBaselines [r1, r1, r2] == 2
#guard pairDiffs [t1, t2, t3] == [2, 2, 2]
#guard overlap (687, 874) (572, 976) && !overlap (1, 2) (3, 4)
#guard overlap (2, 1) (1, 2)
#guard rangeOf [3, 1, 2] == some (1, 3) && (rangeOf []).isNone

end Fw.Measure.WktrVariance
