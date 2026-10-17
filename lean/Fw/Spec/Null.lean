import Fw.Spec.Verdict
/-!
# The false-"better" rate of the verdict under the null (exact, by enumeration)

Under the null hypothesis the $m + n$ runs are exchangeable and have no ties, so every
assignment of the ranks $0, \dots, m+n-1$ to $m$ control and $n$ variant runs is equally likely.
`falseBetterProb m n` enumerates those assignments and runs the real `verdict` on each one, so the
probability is about the deployed function, not a re-statement of it. `pNull` is the closed form
the wire uses (`1 / C(m+n, n)` once both sides have `minRuns` runs). It is checked against the
enumeration for 3v3, 4v4 and 5v5 by `decide`, and proved equal to it for every m, n
(`falseBetterProb_eq_pNull`, at the end of this file).
-/
namespace Fw.Null
open Fw.Verdict

/-- All Bool sequences of length `k` with exactly `n` entries `true` (`true` = a variant run),
in a fixed order.

$$\operatorname{arr}(k, n) = \big[\, b \in \{\mathrm{false}, \mathrm{true}\}^{k} \;\big|\; \#\{\, i : b_i = \mathrm{true} \,\} = n \,\big]$$

$$\operatorname{arr}(0, n) = \begin{cases} [\,[\,]\,] & n = 0 \\ [\,] & n > 0 \end{cases}, \qquad \operatorname{arr}(k+1, n) = \operatorname{map}\big(\mathrm{false} :: \cdot,\ \operatorname{arr}(k, n)\big) \ \mathbin{+\!\!+}\ \begin{cases} [\,] & n = 0 \\ \operatorname{map}\big(\mathrm{true} :: \cdot,\ \operatorname{arr}(k, n-1)\big) & n > 0 \end{cases}$$
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

Edge: Lean's $x / 0 = 0$, but $\lvert \operatorname{arr}(m+n, n) \rvert = \operatorname{choose}(m+n, n) = \binom{m+n}{n} \ge 1$
for all $m, n$ (proved: `arr_length_choose`, `choose_eq_binom`, `binom_pos`).
-/
def falseBetterProb (m n : Nat) : Rat := (wins m n : Rat) / ((arr (m + n) n).length : Rat)

/-- The binomial coefficient, computed by the exact multiplicative recurrence
$\binom{k}{i+1} = \binom{k}{i} \cdot (k - i) / (i + 1)$; the floor never discards anything, and
$\operatorname{choose}(k, j) = \binom{k}{j}$ for all $k, j$ is proved below (`choose_eq_binom`).

$$\operatorname{choose}(k, j) = c_j, \qquad c_0 = 1, \qquad c_{i+1} = \left\lfloor \frac{c_i \cdot (k \mathbin{\dot-} i)}{i + 1} \right\rfloor$$
-/
def choose (k j : Nat) : Nat := (List.range j).foldl (fun c i => c * (k - i) / (i + 1)) 1

#guard choose 8 4 == 70 && choose 10 5 == 252 && choose 6 3 == 20 && choose 3 4 == 0 && choose 5 0 == 1

/-- The closed form the wire reports as `pNull`: 0 when either side has fewer than `minRuns`
runs (the verdict is then never "better"), otherwise one assignment in $\binom{m+n}{n}$. Proved for
all $m, n$: it equals the enumerated `falseBetterProb` (`falseBetterProb_eq_pNull`), equals the
false-"better" share for any distinct run values (`pAt_distinct`), and bounds that share for any
values, ties allowed (`pAt_le_pNull`).

$$\operatorname{pNull}(m, n) = \begin{cases} 0 & \text{if } m < 3 \ \lor\ n < 3 \\ 1 \big/ \operatorname{choose}(m + n, n) & \text{otherwise} \end{cases} \in \mathbb{Q}$$
-/
def pNull (m n : Nat) : Rat :=
  if m < minRuns ∨ n < minRuns then 0 else 1 / (choose (m + n) n : Rat)

/-- The landing verdict (4 control vs 4 variant runs): if the 8 run values are distinct and every
labeling is equally likely (the L3 premise), a false "better" has probability exactly 1/70 (all 70
rank assignments enumerated through `verdict`; any distinct values: `pAt_distinct`); with ties it
is at most 1/70 (`null_bound_4v4_5v5`).

$$\operatorname{falseBetterProb}(4, 4) = 1/70 = \operatorname{pNull}(4, 4)$$
-/
theorem land_null_prob : falseBetterProb 4 4 = 1 / 70 ∧ pNull 4 4 = 1 / 70 := by decide +kernel

/-- 5 vs 5 runs: if every labeling is equally likely (the L3 premise), a false "better" has
probability exactly 1/252 (all 252 rank assignments enumerated through `verdict`; any distinct
values: `pAt_distinct`); with ties it is at most 1/252 (`null_bound_4v4_5v5`).

$$\operatorname{falseBetterProb}(5, 5) = 1/252 = \operatorname{pNull}(5, 5)$$
-/
theorem null_prob_5v5 : falseBetterProb 5 5 = 1 / 252 ∧ pNull 5 5 = 1 / 252 := by decide +kernel

/-- 3 vs 3 runs (v1's minimum): if every labeling is equally likely (the L3 premise), a false
"better" has probability exactly 1/20 (all 20 rank assignments enumerated through `verdict`; any
distinct values: `pAt_distinct`); with ties it is at most 1/20 (`pAt_le_pNull`).

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
$\lvert \operatorname{arr}(m+n, n) \rvert = \binom{m+n}{n}$ labelings makes the verdict say
"better", for every $m, n$, so under the uniform-labeling null the false-"better" probability is
at most $1/\binom{m+n}{n}$ (`pAt_le`, then `pAt_le_choose` and `pAt_le_pNull` in the next section,
where $\lvert \operatorname{arr}(k, n) \rvert = \binom{k}{n}$ is proved for all $k, n$).

For *distinct* values and $m, n \ge 3$, exactly one labeling wins (`winsAt_distinct`, any distinct
values, any $m, n$), so the probability is exactly $1/\binom{m+n}{n} = \operatorname{pNull}(m, n)$
(`pAt_distinct`, `falseBetterProb_eq_pNull`).

What is *not* proved here: that exchangeable runs make every labeling equally likely. That is the
modeling premise (an L3 assumption about the runs), stated by defining the probability as the
share of labelings. -/

/-- The values at the positions labelled `f` (`true` = variant, `false` = control), in order.

$$\operatorname{sel}(f, b, v) = [\, v_i : i < \min(|b|, |v|),\ b_i = f \,]$$
-/
def sel (f : Bool) (b : List Bool) (v : List Int) : List Int :=
  ((b.zip v).filter (fun p => p.1 == f)).map (·.2)

#guard sel true [false, true, true] [7, 8, 9] == [8, 9] && sel false [false, true, true] [7, 8, 9] == [7]

/-- A value whose position carries label `f` is among the selected values.

$$\forall f \in \{\mathrm{false}, \mathrm{true}\},\ \forall b \in \{\mathrm{false}, \mathrm{true}\}^{*},\ \forall v \in \mathbb{Z}^{*},\ \forall i \in \mathbb{N}:\quad i < |b| \ \land\ i < |v| \ \land\ b_i = f \;\Rightarrow\; v_i \in \operatorname{sel}(f, b, v)$$
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

$$\forall b, b' \in \{\mathrm{false}, \mathrm{true}\}^{*}:\quad |b| = |b'| \ \land\ (\forall i < |b|:\ b_i \Rightarrow b'_i) \;\Rightarrow\; \#_{\mathrm{true}}(b) \le \#_{\mathrm{true}}(b')$$
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

$$\forall b, b' \in \{\mathrm{false}, \mathrm{true}\}^{*}:\quad |b| = |b'| \ \land\ (\forall i < |b|:\ b_i \Rightarrow b'_i) \ \land\ \#_{\mathrm{true}}(b) = \#_{\mathrm{true}}(b') \;\Rightarrow\; b = b'$$
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

$$\forall b, b' \in \{\mathrm{false}, \mathrm{true}\}^{*}:\quad |b| = |b'| \ \land\ \#_{\mathrm{true}}(b) = \#_{\mathrm{true}}(b') \ \land\ b \ne b' \;\Rightarrow\; \exists i < |b|:\ b_i = \mathrm{true} \land b'_i = \mathrm{false}$$
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

$$\forall v \in \mathbb{Z}^{*},\ \forall b, b' \in \{\mathrm{false}, \mathrm{true}\}^{|v|}:\quad \#_{\mathrm{true}}(b) = \#_{\mathrm{true}}(b') \ \land\ \operatorname{verdict}(\mathrm{lower}, \operatorname{sel}(\mathrm{false}, b, v), \operatorname{sel}(\mathrm{true}, b, v)) = \mathrm{better} \ \land\ \operatorname{verdict}(\mathrm{lower}, \operatorname{sel}(\mathrm{false}, b', v), \operatorname{sel}(\mathrm{true}, b', v)) = \mathrm{better} \;\Rightarrow\; b = b'$$
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

$$\forall k, n \in \mathbb{N},\ \forall b \in \operatorname{arr}(k, n):\quad |b| = k \ \land\ \#_{\mathrm{true}}(b) = n$$
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

$$\forall k, n \in \mathbb{N}:\quad \operatorname{arr}(k, n) \text{ has no repeated element}$$
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
labelings in $\operatorname{arr}(m+n, n)$ gives "better" (there are $\binom{m+n}{n}$ of them:
`arr_length_choose`).

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

$$\forall m, n \in \mathbb{N},\ \forall v \in \mathbb{Z}^{m+n}:\quad \operatorname{pAt}(v, m, n) \le \frac{1}{\lvert \operatorname{arr}(m+n, n) \rvert}$$
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
(equality for distinct values is `pAt_distinct`; for the ranks $0, \dots, m+n-1$ the enumerated
`falseBetterProb` of `land_null_prob` and `null_prob_5v5` is this `pAt` by `falseBetterProb_eq_pAt`).

$$\forall v \in \mathbb{Z}^{8}:\ \operatorname{pAt}(v, 4, 4) \le \tfrac{1}{70}, \qquad \forall v \in \mathbb{Z}^{10}:\ \operatorname{pAt}(v, 5, 5) \le \tfrac{1}{252}$$
-/
theorem null_bound_4v4_5v5 :
    (∀ v : List Int, v.length = 8 → pAt v 4 4 ≤ 1 / 70) ∧
    (∀ v : List Int, v.length = 10 → pAt v 5 5 ≤ 1 / 252) := by
  have h8 : ((arr (4 + 4) 4).length : Rat) = 70 := by decide +kernel
  have h10 : ((arr (5 + 5) 5).length : Rat) = 252 := by decide +kernel
  exact ⟨fun v hv => h8 ▸ pAt_le v 4 4 hv, fun v hv => h10 ▸ pAt_le v 5 5 hv⟩

/-! ## Counting labelings: $\lvert \operatorname{arr}(k, n) \rvert = \binom{k}{n}$ for all $k, n$

`binom` is the binomial coefficient by Pascal's rule. We prove that `arr k n` has `binom k n`
elements and that the wire's multiplicative `choose` equals `binom`, so the bound `pAt_le` reads
$\operatorname{pAt} \le 1/\binom{m+n}{n}$ for every $m, n$, and $\operatorname{pAt} \le \operatorname{pNull}$. -/

/-- The binomial coefficient by Pascal's rule.

$$\operatorname{binom}(k, 0) = 1, \qquad \operatorname{binom}(0, n+1) = 0, \qquad \operatorname{binom}(k+1, n+1) = \operatorname{binom}(k, n) + \operatorname{binom}(k, n+1) \qquad (k, n \in \mathbb{N})$$
-/
def binom : Nat → Nat → Nat
  | _, 0 => 1
  | 0, _ + 1 => 0
  | k + 1, n + 1 => binom k n + binom k (n + 1)

#guard binom 8 4 == 70 && binom 10 5 == 252 && binom 6 3 == 20 && binom 3 4 == 0 && binom 0 0 == 1

/-- Choosing nothing: one way.

$$\forall k \in \mathbb{N}:\quad \operatorname{binom}(k, 0) = 1$$
-/
theorem binom_zero_right (k : Nat) : binom k 0 = 1 := by cases k <;> rfl

/-- `arr k n` has exactly `binom k n` labelings.

$$\forall k, n \in \mathbb{N}:\quad \lvert \operatorname{arr}(k, n) \rvert = \operatorname{binom}(k, n)$$
-/
theorem arr_length : ∀ k n, (arr k n).length = binom k n
  | 0, 0 => rfl
  | 0, _ + 1 => rfl
  | k + 1, 0 => by simp [arr, arr_length k 0, binom_zero_right]
  | k + 1, n + 1 => by simp [arr, arr_length k n, arr_length k (n + 1), binom]; omega

/-- More to choose than there are: no way.

$$\forall k, n \in \mathbb{N}:\quad k < n \;\Rightarrow\; \operatorname{binom}(k, n) = 0$$
-/
theorem binom_eq_zero : ∀ {k n : Nat}, k < n → binom k n = 0
  | _, 0, h => absurd h (by omega)
  | 0, _ + 1, _ => rfl
  | k + 1, n + 1, h => by
    simp only [binom]; rw [binom_eq_zero (by omega), binom_eq_zero (by omega)]

/-- At most as many as there are: at least one way.

$$\forall k, n \in \mathbb{N}:\quad n \le k \;\Rightarrow\; 0 < \operatorname{binom}(k, n)$$
-/
theorem binom_pos : ∀ {k n : Nat}, n ≤ k → 0 < binom k n
  | k, 0, _ => by simp [binom_zero_right]
  | 0, _ + 1, h => absurd h (by omega)
  | k + 1, n + 1, h => by
    simp only [binom]; have := binom_pos (k := k) (n := n) (by omega); omega

/-- The multiplicative step of the binomial coefficient, on $\mathbb{N}$ with truncated
subtraction (both sides are 0 when $i \ge k$).

$$\forall k, i \in \mathbb{N}:\quad \operatorname{binom}(k, i+1) \cdot (i + 1) = \operatorname{binom}(k, i) \cdot (k \mathbin{\dot-} i)$$
-/
theorem binom_succ_mul : ∀ k i, binom k (i + 1) * (i + 1) = binom k i * (k - i)
  | 0, i => by simp [binom]
  | k + 1, 0 => by
    have := binom_succ_mul k 0
    simp [binom, binom_zero_right] at this ⊢
    omega
  | k + 1, j + 1 => by
    have h1 := binom_succ_mul k (j + 1)
    have h0 := binom_succ_mul k j
    simp only [binom]
    by_cases hk : j + 1 ≤ k
    · obtain ⟨r, rfl⟩ : ∃ r, k = j + 1 + r := ⟨k - (j + 1), by omega⟩
      have e1 : j + 1 + r - (j + 1) = r := by omega
      have e2 : j + 1 + r + 1 - (j + 1) = r + 1 := by omega
      have e3 : j + 1 + r - j = r + 1 := by omega
      rw [e1] at h1; rw [e3] at h0; rw [e2]
      grind
    · rw [binom_eq_zero (k := k) (n := j + 1) (by omega),
        binom_eq_zero (k := k) (n := j + 1 + 1) (by omega)]
      have : k + 1 - (j + 1) = 0 := by omega
      simp [this]

/-- The wire's multiplicative `choose` is the binomial coefficient (each floor division is exact).

$$\forall k, j \in \mathbb{N}:\quad \operatorname{choose}(k, j) = \operatorname{binom}(k, j)$$
-/
theorem choose_eq_binom (k : Nat) : ∀ j, choose k j = binom k j
  | 0 => by simp [choose, binom]
  | j + 1 => by
    rw [choose, List.range_succ, List.foldl_append, ← choose, choose_eq_binom k j]
    simp only [List.foldl_cons, List.foldl_nil]
    rw [← binom_succ_mul, Nat.mul_div_cancel _ (by omega)]

/-- **Gap B closed.** The number of labelings is the binomial coefficient, for all $k, n$.

$$\forall k, n \in \mathbb{N}:\quad \lvert \operatorname{arr}(k, n) \rvert = \operatorname{choose}(k, n) = \binom{k}{n}$$
-/
theorem arr_length_choose (k n : Nat) : (arr k n).length = choose k n := by
  rw [arr_length, choose_eq_binom]

/-- The bound with the binomial coefficient: for any values (ties allowed), the false-"better"
probability is at most $1/\binom{m+n}{n}$; the denominator is at least 1 (`binom_pos`).

$$\forall m, n \in \mathbb{N},\ \forall v \in \mathbb{Z}^{m+n}:\quad \operatorname{pAt}(v, m, n) \le \frac{1}{\operatorname{choose}(m+n, n)}$$
-/
theorem pAt_le_choose (v : List Int) (m n : Nat) (hv : v.length = m + n) :
    pAt v m n ≤ 1 / (choose (m + n) n : Rat) := by
  rw [← arr_length_choose]; exact pAt_le v m n hv

/-- `arr k n` lists every labeling of length `k` with `n` entries `true` (the converse of
`mem_arr`).

$$\forall k, n \in \mathbb{N},\ \forall b \in \{\mathrm{false}, \mathrm{true}\}^{*}:\quad b \in \operatorname{arr}(k, n) \iff |b| = k \ \land\ \#_{\mathrm{true}}(b) = n$$
-/
theorem mem_arr_iff : ∀ {k n : Nat} {b : List Bool}, b ∈ arr k n ↔ b.length = k ∧ b.count true = n
  | k, n, b => by
    constructor
    · exact mem_arr
    · intro ⟨hl, hc⟩
      induction b generalizing k n with
      | nil => subst hl; simp at hc; subst hc; simp [arr]
      | cons x b ih =>
        cases k with
        | zero => simp at hl
        | succ k =>
          simp at hl
          simp only [arr, List.mem_append, List.mem_map]
          cases x with
          | false =>
            left; exact ⟨b, ih _ _ hl (by simpa using hc), rfl⟩
          | true =>
            right
            cases n with
            | zero => simp at hc
            | succ n =>
              simp only [List.mem_map]
              exact ⟨b, ih _ _ hl (by simpa using hc), rfl⟩

/-- `sel` on a cons: the head value is kept exactly when its label is `f`.

$$\forall f, x \in \{\mathrm{false}, \mathrm{true}\},\ \forall b, y, v:\quad \operatorname{sel}(f, x :: b, y :: v) = \begin{cases} y :: \operatorname{sel}(f, b, v) & x = f \\ \operatorname{sel}(f, b, v) & x \ne f \end{cases}$$
-/
theorem sel_cons (f x : Bool) (b : List Bool) (y : Int) (v : List Int) :
    sel f (x :: b) (y :: v) = if x = f then y :: sel f b v else sel f b v := by
  by_cases h : x = f <;> simp [sel, h]

/-- With as many labels as values, `sel` keeps one value per label `f`.

$$\forall f,\ \forall b \in \{\mathrm{false}, \mathrm{true}\}^{*},\ \forall v \in \mathbb{Z}^{*}:\quad |b| = |v| \;\Rightarrow\; \lvert \operatorname{sel}(f, b, v) \rvert = \#_{f}(b)$$
-/
theorem length_sel (f : Bool) : ∀ (b : List Bool) (v : List Int), b.length = v.length →
    (sel f b v).length = b.count f
  | [], _, _ => by simp [sel]
  | _ :: _, [], h => by simp at h
  | x :: b, y :: v, h => by
    rw [sel_cons, List.count_cons]
    have := length_sel f b v (by simpa using h)
    by_cases hx : x = f <;> simp [hx, this]

/-- Every label is `true` or `false`.

$$\forall b \in \{\mathrm{false}, \mathrm{true}\}^{*}:\quad \#_{\mathrm{true}}(b) + \#_{\mathrm{false}}(b) = |b|$$
-/
theorem count_true_add_false : ∀ (b : List Bool), b.count true + b.count false = b.length
  | [] => rfl
  | x :: b => by
    have := count_true_add_false b
    cases x <;> simp <;> omega

/-- With fewer than 3 runs on a side, no labeling gives "better" (the verdict is `tooFew`).

$$\forall m, n \in \mathbb{N},\ \forall v \in \mathbb{Z}^{m+n}:\quad m < 3 \ \lor\ n < 3 \;\Rightarrow\; \operatorname{winsAt}(v, m, n) = 0$$
-/
theorem winsAt_tooFew {v : List Int} {m n : Nat} (hl : v.length = m + n)
    (h : m < minRuns ∨ n < minRuns) : winsAt v m n = 0 := by
  unfold winsAt
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro b hb
  obtain ⟨hbl, hbc⟩ := mem_arr hb
  have l1 : (sel true b v).length = n := by rw [length_sel _ _ _ (by omega)]; exact hbc
  have l0 : (sel false b v).length = m := by
    rw [length_sel _ _ _ (by omega)]; have := count_true_add_false b; omega
  simp [verdict, l0, l1, h]

/-- **The wire's `pNull` bounds the false-"better" probability**, for any values (ties allowed)
and any $m, n$.

$$\forall m, n \in \mathbb{N},\ \forall v \in \mathbb{Z}^{m+n}:\quad \operatorname{pAt}(v, m, n) \le \operatorname{pNull}(m, n)$$
-/
theorem pAt_le_pNull (v : List Int) (m n : Nat) (hv : v.length = m + n) : pAt v m n ≤ pNull m n := by
  unfold pNull
  split
  · rename_i h; simp [pAt, winsAt_tooFew hv h, Rat.div_def]
  · exact pAt_le_choose v m n hv

/-! ## Distinct values: exactly one labeling wins (Gap A closed)

For distinct values the winning labeling marks the $n$ smallest values as variant runs. We find a
threshold $t$ with exactly $n$ values below it (sort the values; take the $(n+1)$-th smallest),
label $v_i < t$ as variant, and combine with `winsAt_le_one`. -/

/-- In a strictly increasing list, exactly $n$ entries lie below the $n$-th one (0-based).

$$\forall s \in \mathbb{Z}^{*}\ \text{with}\ \forall i < j < |s|:\ s_i < s_j,\quad \forall n < |s|:\quad \#\{\, i < |s| : s_i < s_n \,\} = n$$
-/
theorem countP_lt_getElem : ∀ (s : List Int), s.Pairwise (· < ·) → ∀ (n : Nat) (h : n < s.length),
    s.countP (fun x => decide (x < s[n])) = n
  | [], _, n, h => by simp at h
  | a :: s, hp, 0, _ => by
    simp only [List.getElem_cons_zero, List.countP_cons]
    rw [List.pairwise_cons] at hp
    have : s.countP (fun x => decide (x < a)) = 0 := by
      rw [List.countP_eq_zero]; intro x hx; have := hp.1 x hx; simp; omega
    simp [this]
  | a :: s, hp, n + 1, h => by
    rw [List.pairwise_cons] at hp
    simp only [List.getElem_cons_succ, List.countP_cons]
    have hn : n < s.length := by simp at h; omega
    have hlt : a < s[n] := hp.1 _ (List.getElem_mem _)
    rw [countP_lt_getElem s hp.2 n (by simpa using h)]
    simp [hlt]

/-- Distinct values can be split at any count: some threshold has exactly $n$ values below it.

$$\forall v \in \mathbb{Z}^{*}\ \text{with pairwise distinct entries},\ \forall n \in \mathbb{N}:\quad n < |v| \;\Rightarrow\; \exists t \in \mathbb{Z}:\ \#\{\, i < |v| : v_i < t \,\} = n$$
-/
theorem exists_threshold (v : List Int) (hv : v.Nodup) (n : Nat) (hn : n < v.length) :
    ∃ t : Int, v.countP (fun x => decide (x < t)) = n := by
  let s := v.mergeSort (fun a b => decide (a ≤ b))
  have hperm : s.Perm v := List.mergeSort_perm _ _
  have hsorted : s.Pairwise (fun a b => decide (a ≤ b) = true) :=
    List.pairwise_mergeSort (by intro a b c h1 h2; simp at *; omega) (by intro a b; simp; omega) v
  have hnd : s.Nodup := hperm.nodup_iff.mpr hv
  have hlt : s.Pairwise (· < ·) :=
    (hsorted.and hnd).imp (fun ⟨h1, h2⟩ => by simp at h1; omega)
  have hlen : n < s.length := by rw [hperm.length_eq]; exact hn
  exact ⟨s[n], by rw [← hperm.countP_eq]; exact countP_lt_getElem s hlt n hlen⟩

/-- Labeling each value by a test `g` and selecting label `f` is filtering by $g = f$.

$$\forall f,\ \forall g : \mathbb{Z} \to \{\mathrm{false}, \mathrm{true}\},\ \forall v \in \mathbb{Z}^{*}:\quad \operatorname{sel}\big(f,\ [g(v_0), \dots, g(v_{|v|-1})],\ v\big) = [\, v_i : g(v_i) = f \,] \text{ (in order)}$$
-/
theorem sel_map (f : Bool) (g : Int → Bool) :
    ∀ v : List Int, sel f (v.map g) v = v.filter (fun x => g x == f)
  | [] => rfl
  | y :: v => by
    rw [List.map_cons, sel_cons, sel_map f g v]; by_cases h : g y = f <;> simp [h]

/-- **Exactly one winning labeling for distinct values**, for every $m, n \ge 3$.

$$\forall m, n \in \mathbb{N},\ \forall v \in \mathbb{Z}^{m+n}:\quad v \text{ has pairwise distinct entries} \ \land\ 3 \le m \ \land\ 3 \le n \;\Rightarrow\; \operatorname{winsAt}(v, m, n) = 1$$
-/
theorem winsAt_distinct {v : List Int} {m n : Nat} (hv : v.Nodup) (hl : v.length = m + n)
    (hm : minRuns ≤ m) (hn : minRuns ≤ n) : winsAt v m n = 1 := by
  obtain ⟨t, ht⟩ := exists_threshold v hv n (by simp [minRuns] at hm; omega)
  have hbl : (v.map (fun x => decide (x < t))).length = v.length := by simp
  have hb_cnt : (v.map (fun x => decide (x < t))).count true = n := by
    rw [← length_sel true _ v hbl, sel_map, ← List.countP_eq_length_filter, ← ht]; simp
  have hmem : v.map (fun x => decide (x < t)) ∈ arr (m + n) n :=
    mem_arr_iff.mpr ⟨by simp [hl], hb_cnt⟩
  have l1 := length_sel true _ v hbl
  have l0 := length_sel false _ v hbl
  have hc := count_true_add_false (v.map (fun x => decide (x < t)))
  have hbelow : below (sel true (v.map (fun x => decide (x < t))) v)
      (sel false (v.map (fun x => decide (x < t))) v) = true := by
    rw [below_spec, sel_map, sel_map]; intro y hy x hx; simp at hy hx; omega
  have hwin : verdict .lower (sel false (v.map (fun x => decide (x < t))) v)
      (sel true (v.map (fun x => decide (x < t))) v) = .better := by
    have : ¬ ((sel false (v.map (fun x => decide (x < t))) v).length < minRuns ∨
        (sel true (v.map (fun x => decide (x < t))) v).length < minRuns) := by
      rw [l0, l1]; simp at hc; omega
    simp [verdict, this, hbelow]
  have hle := winsAt_le_one v m n hl
  have hpos : 0 < winsAt v m n := by
    unfold winsAt; apply List.length_pos_of_mem (a := v.map (fun x => decide (x < t)))
    simp only [List.mem_filter, beq_iff_eq]; exact ⟨hmem, hwin⟩
  omega

/-- **Exact null rate for distinct values.** Under the uniform-labeling premise, distinct run values
give a false "better" with probability exactly `pNull`, for every $m, n$.

$$\forall m, n \in \mathbb{N},\ \forall v \in \mathbb{Z}^{m+n} \text{ with pairwise distinct entries}:\quad \operatorname{pAt}(v, m, n) = \operatorname{pNull}(m, n)$$
-/
theorem pAt_distinct (v : List Int) (m n : Nat) (hd : v.Nodup) (hv : v.length = m + n) :
    pAt v m n = pNull m n := by
  unfold pNull pAt
  split
  · rename_i h; simp [winsAt_tooFew hv h, Rat.div_def]
  · rename_i h
    rw [winsAt_distinct hd hv (by omega) (by omega), arr_length_choose]; simp

/-- The ranks as integers, $0$ to $k-1$.

$$\operatorname{idx}(k) = [0, 1, \dots, k-1] \in \mathbb{Z}^{k}$$
-/
def idx (k : Nat) : List Int := (List.range k).map (fun (i : Nat) => (i : Int))

#guard idx 4 == [0, 1, 2, 3] && idx 0 == []

/-- The ranks are distinct.

$$\forall k \in \mathbb{N}:\quad \operatorname{idx}(k) \text{ has no repeated element}$$
-/
theorem idx_nodup (k : Nat) : (idx k).Nodup :=
  List.Pairwise.map _ (fun a b h e => h (by omega)) List.nodup_range

/-- Selecting from consecutive integers starting at $s$ returns the positions (offset by $s$) of
the label `f`.

$$\forall f,\ \forall b \in \{\mathrm{false}, \mathrm{true}\}^{*},\ \forall s \in \mathbb{N}:\quad \operatorname{sel}\big(f,\ b,\ [s, s+1, \dots, s+|b|-1]\big) = [\, s + i : i < |b|,\ b_i = f \,] \text{ (in order)}$$
-/
theorem sel_range'_zipIdx (f : Bool) : ∀ (b : List Bool) (s : Nat),
    sel f b ((List.range' s b.length).map (fun (i : Nat) => (i : Int))) =
      ((b.zipIdx s).filter (fun p => p.1 == f)).map (fun p => (p.2 : Int))
  | [], _ => by simp [sel]
  | x :: b, s => by
    rw [List.length_cons, List.range'_succ, List.map_cons, sel_cons, List.zipIdx_cons,
      List.filter_cons, sel_range'_zipIdx f b (s + 1)]
    by_cases hx : x = f <;> simp [hx]

/-- `ranks` is `sel` on the values $0, \dots, |b|-1$ (the link from the enumeration to `pAt`).

$$\forall f,\ \forall b \in \{\mathrm{false}, \mathrm{true}\}^{*}:\quad \operatorname{sel}\big(f,\ b,\ \operatorname{idx}(|b|)\big) = \operatorname{ranks}(f, b)$$
-/
theorem sel_idx (f : Bool) (b : List Bool) : sel f b (idx b.length) = ranks f b := by
  rw [idx, List.range_eq_range', sel_range'_zipIdx]
  rfl

/-- The enumeration counts the winning labelings of the ranks $0, \dots, m+n-1$.

$$\forall m, n \in \mathbb{N}:\quad \operatorname{wins}(m, n) = \operatorname{winsAt}\big(\operatorname{idx}(m+n), m, n\big)$$
-/
theorem wins_eq_winsAt (m n : Nat) : wins m n = winsAt (idx (m + n)) m n := by
  unfold wins winsAt
  congr 1
  apply List.filter_congr
  intro b hb
  have := (mem_arr hb).1
  rw [← this, sel_idx, sel_idx]

/-- The enumerated probability is `pAt` at the ranks.

$$\forall m, n \in \mathbb{N}:\quad \operatorname{falseBetterProb}(m, n) = \operatorname{pAt}\big(\operatorname{idx}(m+n), m, n\big)$$
-/
theorem falseBetterProb_eq_pAt (m n : Nat) : falseBetterProb m n = pAt (idx (m + n)) m n := by
  rw [falseBetterProb, pAt, wins_eq_winsAt]

/-- **The wire's closed form is the enumerated probability**, for every $m, n$ (not only 3v3,
4v4, 5v5).

$$\forall m, n \in \mathbb{N}:\quad \operatorname{falseBetterProb}(m, n) = \operatorname{pNull}(m, n)$$
-/
theorem falseBetterProb_eq_pNull (m n : Nat) : falseBetterProb m n = pNull m n := by
  rw [falseBetterProb_eq_pAt]; exact pAt_distinct _ m n (idx_nodup _) (by simp [idx])

end Fw.Null
