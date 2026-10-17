import Fw.Spec.Verdict
/-!
# The false-"better" rate of the verdict under the null (exact, by enumeration)

Under the null hypothesis the $m + n$ runs are exchangeable and have no ties, so every
assignment of the ranks $0, \dots, m+n-1$ to $m$ control and $n$ variant runs is equally likely.
`falseBetterProb m n` enumerates those assignments and runs the real `verdict` on each one, so the
probability is about the deployed function, not a re-statement of it. `pNull` is the closed form
the wire uses (`1 / C(m+n, n)` once both sides have `minRuns` runs); it is checked against the
enumeration for 3v3, 4v4 and 5v5 by `decide`.
-/
namespace Fw.Null
open Fw.Verdict

/-- All Bool sequences of length `k` with exactly `n` entries `true` (`true` = a variant run),
in a fixed order.

$$\operatorname{arr}(k, n) = \big[\, b \in \{\mathrm{false}, \mathrm{true}\}^{k} \;\big|\; \#\{\, i : b_i = \mathrm{true} \,\} = n \,\big]$$

$$\operatorname{arr}(0, n) = \begin{cases} [\,[\,]\,] & n = 0 \\ [\,] & n > 0 \end{cases}, \qquad \operatorname{arr}(k+1, n) = \mathrm{false} :: \operatorname{arr}(k, n) \ \mathbin{+\!\!+}\ \begin{cases} [\,] & n = 0 \\ \mathrm{true} :: \operatorname{arr}(k, n-1) & n > 0 \end{cases}$$
-/
def arr : Nat → Nat → List (List Bool)
  | 0, n => if n = 0 then [[]] else []
  | k + 1, n =>
    (arr k n).map (false :: ·) ++
      (match n with
       | 0 => []
       | n' + 1 => (arr k n').map (true :: ·))

#guard (arr 2 1) == [[false, true], [true, false]]
#guard (arr 8 4).length == 70 && (arr 10 5).length == 252 && (arr 3 4).length == 0

/-- The runs whose position in `b` has the flag `f`, each run valued by its rank (its position).

$$\operatorname{ranks}(f, b) = [\, i \in \{0, \dots, |b| - 1\} \text{ in order} \mid b_i = f \,] \in \mathbb{Z}^{*}$$
-/
def ranks (f : Bool) (b : List Bool) : List Int :=
  ((b.zipIdx.filter (fun p => p.1 == f)).map (fun p => (p.2 : Int)))

#guard ranks true [false, true, true, false] == [1, 2] && ranks false [false, true, true, false] == [0, 3]

/-- The number of rank assignments (out of all of them) on which the verdict says "better" for
the variant, lower is better, with `m` control runs and `n` variant runs.

$$\operatorname{wins}(m, n) = \#\big\{\, b \in \operatorname{arr}(m+n, n) \;\big|\; \operatorname{verdict}\big(\mathrm{lower},\ \operatorname{ranks}(\mathrm{false}, b),\ \operatorname{ranks}(\mathrm{true}, b)\big) = \mathrm{better} \,\big\}$$
-/
def wins (m n : Nat) : Nat :=
  ((arr (m + n) n).filter (fun b => verdict .lower (ranks false b) (ranks true b) == .better)).length

/-- The probability of a false "better" under the null: the share of equally likely rank
assignments on which the verdict says "better".

$$\operatorname{falseBetterProb}(m, n) = \frac{\operatorname{wins}(m, n)}{\lvert \operatorname{arr}(m+n, n) \rvert} \in \mathbb{Q}$$

Edge: Lean's $x / 0 = 0$, but $\lvert \operatorname{arr}(m+n, n) \rvert = \binom{m+n}{n} \ge 1$ always.
-/
def falseBetterProb (m n : Nat) : Rat := (wins m n : Rat) / ((arr (m + n) n).length : Rat)

/-- The binomial coefficient, computed by the exact multiplicative recurrence
$\binom{k}{i+1} = \binom{k}{i} \cdot (k - i) / (i + 1)$.

$$\operatorname{choose}(k, j) = c_j, \qquad c_0 = 1, \qquad c_{i+1} = \left\lfloor \frac{c_i \cdot (k \mathbin{\dot-} i)}{i + 1} \right\rfloor \qquad \Big(= \tbinom{k}{j} \text{ on every value checked below}\Big)$$
-/
def choose (k j : Nat) : Nat := (List.range j).foldl (fun c i => c * (k - i) / (i + 1)) 1

#guard choose 8 4 == 70 && choose 10 5 == 252 && choose 6 3 == 20 && choose 3 4 == 0 && choose 5 0 == 1

/-- The closed form the wire reports as `pNull`: 0 when either side has fewer than `minRuns`
runs (the verdict is then never "better"), otherwise one assignment in $\binom{m+n}{n}$.

$$\operatorname{pNull}(m, n) = \begin{cases} 0 & \text{if } m < 3 \ \lor\ n < 3 \\ 1 \big/ \operatorname{choose}(m + n, n) & \text{otherwise} \end{cases} \in \mathbb{Q}$$
-/
def pNull (m n : Nat) : Rat :=
  if m < minRuns ∨ n < minRuns then 0 else 1 / (choose (m + n) n : Rat)

/-- The landing verdict (4 control vs 4 variant runs): with no real difference, a false "better"
happens with probability exactly 1/70 (all 70 rank assignments enumerated through `verdict`).

$$\operatorname{falseBetterProb}(4, 4) = 1/70 = \operatorname{pNull}(4, 4)$$
-/
theorem land_null_prob : falseBetterProb 4 4 = 1 / 70 ∧ pNull 4 4 = 1 / 70 := by decide +kernel

/-- 5 vs 5 runs: a false "better" happens with probability exactly 1/252.

$$\operatorname{falseBetterProb}(5, 5) = 1/252 = \operatorname{pNull}(5, 5)$$
-/
theorem null_prob_5v5 : falseBetterProb 5 5 = 1 / 252 ∧ pNull 5 5 = 1 / 252 := by decide +kernel

/-- 3 vs 3 runs (v1's minimum): a false "better" happens with probability exactly 1/20.

$$\operatorname{falseBetterProb}(3, 3) = 1/20 = \operatorname{pNull}(3, 3)$$
-/
theorem null_prob_3v3 : falseBetterProb 3 3 = 1 / 20 ∧ pNull 3 3 = 1 / 20 := by decide +kernel

/-- The multiplicity gate: an experiment that makes `k` comparisons may land only if
$k \cdot p_{\text{null}} \le 1/20$.

$$\operatorname{multOk}(k, p) = \mathrm{true} \iff k \cdot p \le \tfrac{1}{20}, \qquad k \in \mathbb{N},\ p \in \mathbb{Q}$$
-/
def multOk (k : Nat) (p : Rat) : Bool := decide ((k : Rat) * p ≤ 1 / 20)

/-- With 4v4 runs, up to 3 comparisons pass the multiplicity gate and 4 do not.

$$\operatorname{multOk}\big(3, \operatorname{pNull}(4,4)\big) = \mathrm{true} \ \land\ \operatorname{multOk}\big(4, \operatorname{pNull}(4,4)\big) = \mathrm{false}$$
-/
theorem mult_4v4 : multOk 3 (pNull 4 4) = true ∧ multOk 4 (pNull 4 4) = false := by decide +kernel

/-! ## With ties: at most one labeling wins, for any values

The enumeration above uses the distinct ranks $0, \dots, m+n-1$. For arbitrary run values
$v \in \mathbb{Z}^{m+n}$ (ties allowed) we prove that **at most one** of the
$\binom{m+n}{n}$ labelings makes the verdict say "better", for every $m, n$, so under the
uniform-labeling null the false-"better" probability is at most $1/\binom{m+n}{n}$.

What is *not* proved here: (1) that for every set of distinct values exactly one labeling wins
(it is proved for the canonical ranks only, by `decide`); (2) that exchangeable runs make every
labeling equally likely: that is the modeling premise (an L3 assumption about the runs), stated
by defining the probability as the share of labelings. -/

/-- The values at the positions labelled `f` (`true` = variant, `false` = control), in order.

$$\operatorname{sel}(f, b, v) = [\, v_i : i < \min(|b|, |v|),\ b_i = f \,]$$
-/
def sel (f : Bool) (b : List Bool) (v : List Int) : List Int :=
  ((b.zip v).filter (fun p => p.1 == f)).map (·.2)

#guard sel true [false, true, true] [7, 8, 9] == [8, 9] && sel false [false, true, true] [7, 8, 9] == [7]

/-- A value whose position carries label `f` is among the selected values.

$$i < |b| \ \land\ i < |v| \ \land\ b_i = f \;\Rightarrow\; v_i \in \operatorname{sel}(f, b, v)$$
-/
theorem mem_sel {f : Bool} {b : List Bool} {v : List Int} {i : Nat} (hb : i < b.length)
    (hv : i < v.length) (h : b[i] = f) : v[i] ∈ sel f b v := by
  unfold sel
  apply List.mem_map.mpr
  refine ⟨(b[i], v[i]), ?_, rfl⟩
  apply List.mem_filter.mpr
  refine ⟨?_, by simp [h]⟩
  have hz : i < (b.zip v).length := by simp [List.length_zip]; omega
  have := List.getElem_mem hz
  simpa [List.getElem_zip] using this

/-- If every `true` of `b` is a `true` of `b'` (position by position), `b` has no more `true`s.

$$|b| = |b'| \ \land\ (\forall i:\ b_i \Rightarrow b'_i) \;\Rightarrow\; \#_{\mathrm{true}}(b) \le \#_{\mathrm{true}}(b')$$
-/
theorem count_le_of_imp : ∀ (b b' : List Bool), b.length = b'.length →
    (∀ (i : Nat) (h : i < b.length) (h' : i < b'.length), b[i] = true → b'[i] = true) →
    b.count true ≤ b'.count true
  | [], _, _, _ => by simp
  | _ :: _, [], h, _ => by simp at h
  | x :: xs, y :: ys, hl, hi => by
    have ih := count_le_of_imp xs ys (by simpa using hl)
      (fun i h h' hx => hi (i + 1) (by simp; omega) (by simp; omega) hx)
    have h0 := hi 0 (by simp) (by simp)
    simp only [List.getElem_cons_zero] at h0
    simp only [List.count_cons]
    cases x <;> cases y <;> simp_all <;> omega

/-- If every `true` of `b` is a `true` of `b'` and both have the same number of `true`s, they are
equal.

$$|b| = |b'| \ \land\ (\forall i:\ b_i \Rightarrow b'_i) \ \land\ \#_{\mathrm{true}}(b) = \#_{\mathrm{true}}(b') \;\Rightarrow\; b = b'$$
-/
theorem eq_of_imp_count : ∀ (b b' : List Bool), b.length = b'.length →
    (∀ (i : Nat) (h : i < b.length) (h' : i < b'.length), b[i] = true → b'[i] = true) →
    b.count true = b'.count true → b = b'
  | [], [], _, _, _ => rfl
  | [], _ :: _, h, _, _ => by simp at h
  | _ :: _, [], h, _, _ => by simp at h
  | x :: xs, y :: ys, hl, hi, hc => by
    have hl' : xs.length = ys.length := by simpa using hl
    have hi' : ∀ (i : Nat) (h : i < xs.length) (h' : i < ys.length), xs[i] = true → ys[i] = true :=
      fun i h h' hx => hi (i + 1) (by simp; omega) (by simp; omega) hx
    have hle := count_le_of_imp xs ys hl' hi'
    have h0 := hi 0 (by simp) (by simp)
    simp only [List.getElem_cons_zero] at h0
    simp only [List.count_cons] at hc
    cases x <;> cases y
    · simp at hc; rw [eq_of_imp_count xs ys hl' hi' hc]
    · simp at hc; omega
    · simp at h0
    · simp at hc; rw [eq_of_imp_count xs ys hl' hi' hc]

/-- Two different labelings with the same number of `true`s: some position is `true` in the
first and `false` in the second.

$$|b| = |b'| \ \land\ \#_{\mathrm{true}}(b) = \#_{\mathrm{true}}(b') \ \land\ b \ne b' \;\Rightarrow\; \exists i:\ b_i = \mathrm{true} \land b'_i = \mathrm{false}$$
-/
theorem exists_true_false (b b' : List Bool) (hl : b.length = b'.length)
    (hc : b.count true = b'.count true) (hne : b ≠ b') :
    ∃ (i : Nat) (h : i < b.length) (h' : i < b'.length), b[i] = true ∧ b'[i] = false := by
  apply Classical.byContradiction
  intro hno
  apply hne
  apply eq_of_imp_count b b' hl _ hc
  intro i h h' hb
  cases e : b'[i]
  · exact absurd ⟨i, h, h', hb, e⟩ hno
  · rfl

/-- **At most one winning labeling, ties allowed.** For any run values, two labelings with the same
number of variant runs on which the verdict says "better" (lower is better) are equal.

$$\forall v \in \mathbb{Z}^{*},\ \forall b, b' \in \{0,1\}^{|v|}:\quad \#_{\mathrm{true}}(b) = \#_{\mathrm{true}}(b') \ \land\ \operatorname{verdict}(\mathrm{lower}, \operatorname{sel}(\mathrm{false}, b, v), \operatorname{sel}(\mathrm{true}, b, v)) = \mathrm{better} \ \land\ \operatorname{verdict}(\mathrm{lower}, \operatorname{sel}(\mathrm{false}, b', v), \operatorname{sel}(\mathrm{true}, b', v)) = \mathrm{better} \;\Rightarrow\; b = b'$$
-/
theorem better_labeling_unique {v : List Int} {b b' : List Bool} (hb : b.length = v.length)
    (hb' : b'.length = v.length) (hc : b.count true = b'.count true)
    (h1 : verdict .lower (sel false b v) (sel true b v) = .better)
    (h2 : verdict .lower (sel false b' v) (sel true b' v) = .better) : b = b' := by
  apply Classical.byContradiction
  intro hne
  obtain ⟨i, hi, hi', hbi, hbi'⟩ := exists_true_false b b' (by omega) hc hne
  obtain ⟨j, hj', hj, hbj', hbj⟩ := exists_true_false b' b (by omega) hc.symm (Ne.symm hne)
  have s1 := better_sound h1
  have s2 := better_sound h2
  have a := s1 v[i] (mem_sel hi (by omega) hbi) v[j] (mem_sel hj (by omega) hbj)
  have c := s2 v[j] (mem_sel hj' (by omega) hbj') v[i] (mem_sel hi' (by omega) hbi')
  omega

/-- Every labeling in `arr k n` has length `k` and exactly `n` entries `true`.

$$\forall b \in \operatorname{arr}(k, n):\quad |b| = k \ \land\ \#_{\mathrm{true}}(b) = n$$
-/
theorem mem_arr : ∀ {k n : Nat} {b : List Bool}, b ∈ arr k n → b.length = k ∧ b.count true = n
  | 0, n, b, h => by
    by_cases hn : n = 0
    · simp [arr, hn] at h; subst h; simp [hn]
    · simp [arr, hn] at h
  | k + 1, n, b, h => by
    simp only [arr, List.mem_append, List.mem_map] at h
    rcases h with ⟨b0, hb0, rfl⟩ | h
    · have := mem_arr hb0; simp [this.1, this.2]
    · cases n with
      | zero => simp at h
      | succ n' =>
        simp only [List.mem_map] at h
        obtain ⟨b0, hb0, rfl⟩ := h
        have := mem_arr hb0; simp [this.1, this.2]

/-- `arr k n` lists each labeling once.

$$\operatorname{arr}(k, n) \text{ has no repeated element}$$
-/
theorem arr_nodup : ∀ (k n : Nat), (arr k n).Nodup
  | 0, n => by by_cases hn : n = 0 <;> simp [arr, hn]
  | k + 1, n => by
    simp only [arr]
    rw [List.nodup_append]
    refine ⟨List.Pairwise.map (false :: ·) (fun _ _ h e => h (List.cons.inj e).2) (arr_nodup k n), ?_, ?_⟩
    · cases n with
      | zero => simp
      | succ n' =>
        exact List.Pairwise.map (true :: ·) (fun _ _ h e => h (List.cons.inj e).2) (arr_nodup k n')
    · intro a ha c hc
      simp only [List.mem_map] at ha
      obtain ⟨a0, _, rfl⟩ := ha
      cases n with
      | zero => simp at hc
      | succ n' =>
        simp only [List.mem_map] at hc
        obtain ⟨c0, _, rfl⟩ := hc
        simp

/-- The number of labelings on which the verdict says "better" for the run values `v`.

$$\operatorname{winsAt}(v, m, n) = \#\big\{\, b \in \operatorname{arr}(m+n, n) \;\big|\; \operatorname{verdict}\big(\mathrm{lower},\ \operatorname{sel}(\mathrm{false}, b, v),\ \operatorname{sel}(\mathrm{true}, b, v)\big) = \mathrm{better} \,\big\}$$
-/
def winsAt (v : List Int) (m n : Nat) : Nat :=
  ((arr (m + n) n).filter (fun b => verdict .lower (sel false b v) (sel true b v) == .better)).length

#guard winsAt [1, 1, 1, 1, 1, 1, 1, 1] 4 4 == 0 && winsAt [3, 1, 4, 1, 5, 9, 2, 6] 4 4 == 1
-- a tie across the split point leaves no winning labeling; a tie inside one side does not matter
#guard winsAt [1, 2, 3, 4, 4, 5, 6, 7] 4 4 == 0 && winsAt [1, 2, 3, 3, 4, 4, 5, 6] 4 4 == 1

/-- **Combinatorial core, ties allowed.** For any $m + n$ run values, at most one of the
$\binom{m+n}{n}$ labelings gives "better".

$$\forall m, n \in \mathbb{N},\ \forall v \in \mathbb{Z}^{m+n}:\quad \operatorname{winsAt}(v, m, n) \le 1$$
-/
theorem winsAt_le_one (v : List Int) (m n : Nat) (hv : v.length = m + n) : winsAt v m n ≤ 1 := by
  unfold winsAt
  generalize hl : (arr (m + n) n).filter _ = l
  have hnd : l.Nodup := hl ▸ (arr_nodup (m + n) n).filter _
  have hall : ∀ b ∈ l, b ∈ arr (m + n) n ∧
      verdict .lower (sel false b v) (sel true b v) = .better := by
    intro b hb; rw [← hl] at hb
    simp only [List.mem_filter, beq_iff_eq] at hb
    exact hb
  match l, hnd, hall with
  | [], _, _ => simp
  | [_], _, _ => simp
  | a :: c :: _, hnd, hall =>
    exfalso
    have ha := hall a (by simp)
    have hc := hall c (by simp)
    have ma := mem_arr ha.1
    have mc := mem_arr hc.1
    have : a = c := better_labeling_unique (by omega) (by omega) (by omega) ha.2 hc.2
    subst this
    simp at hnd

/-- The false-"better" probability for given run values under the uniform-labeling null: the
share of labelings on which the verdict says "better".

$$\operatorname{pAt}(v, m, n) = \frac{\operatorname{winsAt}(v, m, n)}{\lvert \operatorname{arr}(m+n, n) \rvert} \in \mathbb{Q}$$
-/
def pAt (v : List Int) (m n : Nat) : Rat := (winsAt v m n : Rat) / ((arr (m + n) n).length : Rat)

/-- The bound: for any values (ties allowed), the false-"better" probability is at most one
labeling's share.

$$\forall m, n,\ \forall v \in \mathbb{Z}^{m+n}:\quad \operatorname{pAt}(v, m, n) \le \frac{1}{\lvert \operatorname{arr}(m+n, n) \rvert}$$
-/
theorem pAt_le (v : List Int) (m n : Nat) (hv : v.length = m + n) :
    pAt v m n ≤ 1 / ((arr (m + n) n).length : Rat) := by
  unfold pAt
  rw [Rat.div_def, Rat.div_def]
  have hw : ((winsAt v m n : Nat) : Rat) ≤ ((1 : Nat) : Rat) :=
    Rat.natCast_le_natCast.mpr (winsAt_le_one v m n hv)
  have hinv : (0 : Rat) ≤ (((arr (m + n) n).length : Nat) : Rat)⁻¹ := by
    cases h : (arr (m + n) n).length with
    | zero => simp
    | succ k =>
      have hpos : ((0 : Nat) : Rat) < ((k + 1 : Nat) : Rat) := Rat.natCast_lt_natCast.mpr (by omega)
      exact Rat.le_of_lt (Rat.inv_pos.mpr (by simpa using hpos))
  have := Rat.mul_le_mul_of_nonneg_right hw hinv
  simpa using this

/-- 4v4 and 5v5 with ties allowed: the false-"better" probability is at most 1/70 and 1/252
(equality for the distinct ranks is `land_null_prob` and `null_prob_5v5`).

$$\forall v \in \mathbb{Z}^{8}:\ \operatorname{pAt}(v, 4, 4) \le \tfrac{1}{70}, \qquad \forall v \in \mathbb{Z}^{10}:\ \operatorname{pAt}(v, 5, 5) \le \tfrac{1}{252}$$
-/
theorem null_bound_4v4_5v5 :
    (∀ v : List Int, v.length = 8 → pAt v 4 4 ≤ 1 / 70) ∧
    (∀ v : List Int, v.length = 10 → pAt v 5 5 ≤ 1 / 252) := by
  have h8 : ((arr (4 + 4) 4).length : Rat) = 70 := by decide +kernel
  have h10 : ((arr (5 + 5) 5).length : Rat) = 252 := by decide +kernel
  exact ⟨fun v hv => h8 ▸ pAt_le v 4 4 hv, fun v hv => h10 ▸ pAt_le v 5 5 hv⟩

end Fw.Null
