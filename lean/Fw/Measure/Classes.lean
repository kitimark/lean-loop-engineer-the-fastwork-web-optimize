import Fw.Measure.Zones
/-!
# Determinism classes of a count type (the counts lane's run-to-run check, PLAN V-i)

A count type observed over one run is a *series*: its value in frame 0, 1, 2, … (a frame missing
at the end of a shorter run counts as 0, as in `src/compare.mjs`). Two series are compared by

* `diffFrames a b`: the number of frames whose values differ, and
* `totalGap a b`: the absolute difference of the run totals.

The three classes, as properties of a pair of runs (`Within`) and of a set of runs (`Holds`: every
pair):

| class | pair condition |
|---|---|
| `deterministic` | no frame differs |
| `stable k t` | at most `k` frames differ and the totals differ by at most `t` |
| `quarantined` | none |

"Shifted by one" in the measurement notes (a unit of work landing one frame early or late) is a
special case: it changes two adjacent frames and leaves the total unchanged; the class bounds the
number of differing frames and the total gap and does not require the shift structure.

`classify p rs` picks the strictest class the runs satisfy within the policy `p = (kMax, tMax)`:
`deterministic` when no pair differs, else `stable k t` with the observed maxima `k`, `t` when
`k ≤ kMax` and `t ≤ tMax`, else `quarantined`. Proved: the class holds (`classify_sound`), it is the
strictest admissible one (`classify_strictest`), deterministic is exactly stable(0,0)
(`holds_det_iff_stable00`), and adding runs never makes the class stricter (`classify_mono`).
-/
namespace Fw.Measure

/-- One count type over the frames of one run.

$$\mathrm{Series} = \mathbb{Z}^{*}$$
-/
abbrev Series := List Int

/-- The value in frame `i`, 0 past the end.

$$r[i] = \begin{cases} r_i & i < |r| \\ 0 & i \ge |r| \end{cases}$$
-/
def valAt (r : Series) (i : Nat) : Int := r.getD i 0

/-- The run total.

$$\Sigma r = \sum_{i < |r|} r_i$$
-/
def total (r : Series) : Int := sumBy id r

/-- The number of frames whose values differ (the shorter series padded with zeros).

$$\operatorname{diff}(a, b) = \big|\{\, i < \max(|a|, |b|) \mid a[i] \ne b[i] \,\}\big|$$
-/
def diffFrames : Series → Series → Nat
  | [], [] => 0
  | x :: xs, [] => (if x = 0 then 0 else 1) + diffFrames xs []
  | [], y :: ys => (if 0 = y then 0 else 1) + diffFrames [] ys
  | x :: xs, y :: ys => (if x = y then 0 else 1) + diffFrames xs ys

/-- The absolute difference of the run totals.

$$\operatorname{gap}(a, b) = \big|\Sigma a - \Sigma b\big| \in \mathbb{N}$$
-/
def totalGap (a b : Series) : Nat := (total a - total b).natAbs

#guard diffFrames [1, 2, 3] [1, 3, 2] == 2
#guard diffFrames [1, 2] [1, 2, 0, 0] == 0
#guard diffFrames [1, 2] [1, 2, 0, 5] == 1
#guard totalGap [1, 2, 3] [1, 3, 2] == 0
#guard totalGap [4] [1, 1] == 2

/-- The determinism classes.

$$\mathrm{Class} = \{\mathrm{det}\} \cup \{\mathrm{stable}(k, t) \mid k, t \in \mathbb{N}\} \cup \{\mathrm{quar}\}$$
-/
inductive Class where
  | deterministic
  | stable (k t : Nat)
  | quarantined
deriving Repr, DecidableEq

/-- What a class promises about a pair of runs of one count type.

$$\operatorname{Within}(c, a, b) \iff \begin{cases} \operatorname{diff}(a, b) = 0 & c = \mathrm{det} \\ \operatorname{diff}(a, b) \le k \ \land\ \operatorname{gap}(a, b) \le t & c = \mathrm{stable}(k, t) \\ \top & c = \mathrm{quar} \end{cases}$$
-/
def Within : Class → Series → Series → Prop
  | .deterministic, a, b => diffFrames a b = 0
  | .stable k t, a, b => diffFrames a b ≤ k ∧ totalGap a b ≤ t
  | .quarantined, _, _ => True

/-- A class holds for a set of runs when every pair of them is within it.

$$\operatorname{Holds}(c, R) \iff \forall a, b \in R:\ \operatorname{Within}(c, a, b)$$
-/
def Holds (c : Class) (rs : List Series) : Prop := ∀ a ∈ rs, ∀ b ∈ rs, Within c a b

/-- The syntactic strictness order: `c.le c'` implies every pair within `c` is within `c'` (`within_mono`); the
converse fails for `stable 0 t` (`deterministic` ≤ `stable k t` ≤ `stable k' t'` (k ≤ k', t ≤ t') ≤ `quarantined`).

$$c \preceq c' \iff \begin{cases} \top & c = \mathrm{det} \ \lor\ c' = \mathrm{quar} \\ k \le k' \land t \le t' & c = \mathrm{stable}(k, t),\ c' = \mathrm{stable}(k', t') \\ \bot & \text{otherwise} \end{cases}$$
-/
def Class.le : Class → Class → Bool
  | .deterministic, _ => true
  | _, .quarantined => true
  | .stable k t, .stable k' t' => decide (k ≤ k') && decide (t ≤ t')
  | _, _ => false

/-- The least class above two classes (used to combine the class of the baseline's runs with the
variant's).

$$c \sqcup c' = \begin{cases} c' & c = \mathrm{det} \\ c & c' = \mathrm{det} \\ \mathrm{stable}(\max(k, k'), \max(t, t')) & c = \mathrm{stable}(k, t),\ c' = \mathrm{stable}(k', t') \\ \mathrm{quar} & \text{otherwise} \end{cases}$$
-/
def Class.join : Class → Class → Class
  | .deterministic, c => c
  | c, .deterministic => c
  | .stable k t, .stable k' t' => .stable (max k k') (max t t')
  | _, _ => .quarantined

/-- The classification policy: the largest number of differing frames and the largest total gap a
stable type may show.

$$\mathrm{Policy} = (k_{\max}, t_{\max}) \in \mathbb{N}^2$$
-/
structure Policy where
  kMax : Nat
  tMax : Nat
deriving Repr, DecidableEq

/-- The largest element of a list of naturals (0 for the empty list).

$$\max{}^{*}(L) = \max(\{0\} \cup L)$$
-/
def maxOf (l : List Nat) : Nat := l.foldr max 0

/-- The values of a pair statistic over all ordered pairs of runs.

$$\operatorname{pairs}_g(R) = [\, g(a, b) \,]_{a \in R,\ b \in R}$$
-/
def pairVals (g : Series → Series → Nat) (rs : List Series) : List Nat :=
  rs.flatMap fun a => rs.map fun b => g a b

/-- The largest number of differing frames over all pairs of runs.

$$k(R) = \max{}^{*}\{\operatorname{diff}(a, b) \mid a, b \in R\}$$
-/
def kObs (rs : List Series) : Nat := maxOf (pairVals diffFrames rs)

/-- The largest total gap over all pairs of runs.

$$t(R) = \max{}^{*}\{\operatorname{gap}(a, b) \mid a, b \in R\}$$
-/
def tObs (rs : List Series) : Nat := maxOf (pairVals totalGap rs)

/-- **The classification** of one count type from its runs.

$$\operatorname{classify}_p(R) = \begin{cases} \mathrm{det} & k(R) = 0 \\ \mathrm{stable}(k(R), t(R)) & 1 \le k(R) \le k_{\max} \ \land\ t(R) \le t_{\max} \\ \mathrm{quar} & \text{otherwise} \end{cases}$$
-/
def classify (p : Policy) (rs : List Series) : Class :=
  if kObs rs = 0 then .deterministic
  else if kObs rs ≤ p.kMax ∧ tObs rs ≤ p.tMax then .stable (kObs rs) (tObs rs)
  else .quarantined

/-- A class the policy allows: deterministic, quarantined, or stable within the policy's bounds.

$$\operatorname{adm}_p(c) \iff c = \mathrm{det} \ \lor\ c = \mathrm{quar} \ \lor\ \exists k, t \in \mathbb{N}:\ (c = \mathrm{stable}(k, t) \land k \le k_{\max} \land t \le t_{\max})$$
-/
def Admissible (p : Policy) : Class → Prop
  | .stable k t => k ≤ p.kMax ∧ t ≤ p.tMax
  | _ => True

-- the README's three behaviours (policy kMax = 4, tMax = 24)
#guard classify ⟨4, 24⟩ [[1, 0, 2], [1, 0, 2], [1, 0, 2]] == .deterministic
#guard classify ⟨4, 24⟩ [[1, 0, 2], [0, 1, 2], [1, 0, 2]] == .stable 2 0
#guard classify ⟨4, 24⟩ [[1, 0, 2], [0, 1, 3], [1, 0, 2]] == .stable 3 1
#guard classify ⟨1, 24⟩ [[1, 0, 2], [0, 1, 2]] == .quarantined
#guard classify ⟨4, 0⟩ [[1, 0, 2], [1, 0, 3]] == .quarantined
#guard classify ⟨4, 24⟩ [] == .deterministic
#guard classify ⟨4, 24⟩ [[5, 5]] == .deterministic
#guard Class.le .deterministic (.stable 0 0) && Class.le (.stable 1 2) (.stable 1 3) && Class.le (.stable 9 9) .quarantined
#guard !Class.le (.stable 2 0) (.stable 1 5) && !Class.le .quarantined (.stable 9 9) && !Class.le (.stable 0 0) .deterministic
#guard Class.join (.stable 1 5) (.stable 3 2) == .stable 3 5

/-! ## Pair statistics -/

/-- Frames differ symmetrically.

$$\forall a, b:\ \operatorname{diff}(a, b) = \operatorname{diff}(b, a)$$
-/
theorem diffFrames_comm : ∀ a b : Series, diffFrames a b = diffFrames b a
  | [], [] => rfl
  | x :: xs, [] => by
    simp only [diffFrames, diffFrames_comm xs []]
    by_cases h : x = 0 <;> simp [h, eq_comm]
  | [], y :: ys => by
    simp only [diffFrames, diffFrames_comm [] ys]
    by_cases h : y = 0 <;> simp [h, eq_comm]
  | x :: xs, y :: ys => by
    simp only [diffFrames, diffFrames_comm xs ys]
    by_cases h : x = y <;> simp [h, eq_comm]

/-- A run never differs from itself.

$$\forall a:\ \operatorname{diff}(a, a) = 0$$
-/
theorem diffFrames_self : ∀ a : Series, diffFrames a a = 0
  | [] => by simp [diffFrames]
  | _ :: xs => by simp [diffFrames, diffFrames_self xs]

/-- Total gaps are symmetric.

$$\forall a, b:\ \operatorname{gap}(a, b) = \operatorname{gap}(b, a)$$
-/
theorem totalGap_comm (a b : Series) : totalGap a b = totalGap b a := by
  simp only [totalGap]; omega

/-- Runs with no differing frame have equal totals.

$$\forall a, b:\ \operatorname{diff}(a, b) = 0 \;\Rightarrow\; \Sigma a = \Sigma b$$
-/
theorem total_eq_of_diff_zero : ∀ a b : Series, diffFrames a b = 0 → total a = total b
  | [], [], _ => rfl
  | x :: xs, [], h => by
    simp only [diffFrames] at h
    have hx : x = 0 := by by_cases hx : x = 0 <;> simp_all
    have := total_eq_of_diff_zero xs [] (by omega)
    simp only [total, sumBy] at this ⊢; simp [hx, this]
  | [], y :: ys, h => by
    simp only [diffFrames] at h
    have hy : y = 0 := by by_cases hy : 0 = y <;> simp_all
    have := total_eq_of_diff_zero [] ys (by omega)
    simp only [total, sumBy] at this ⊢; simp [hy, ← this]
  | x :: xs, y :: ys, h => by
    simp only [diffFrames] at h
    have hxy : x = y := by by_cases hxy : x = y <;> simp_all
    have := total_eq_of_diff_zero xs ys (by omega)
    simp only [total, sumBy] at this ⊢; simp [hxy, this]

/-- The pair statistic of two runs is among the values over all pairs.

$$\forall g, R, a, b:\ a, b \in R \;\Rightarrow\; g(a, b) \in \operatorname{pairs}_g(R)$$
-/
theorem mem_pairVals {g : Series → Series → Nat} {rs : List Series} {a b : Series}
    (ha : a ∈ rs) (hb : b ∈ rs) : g a b ∈ pairVals g rs := by
  simp only [pairVals, List.mem_flatMap, List.mem_map]
  exact ⟨a, ha, b, hb, rfl⟩

/-- Every value over all pairs comes from a pair of runs.

$$\forall g, R, x:\ x \in \operatorname{pairs}_g(R) \;\Rightarrow\; \exists a, b \in R:\ x = g(a, b)$$
-/
theorem of_mem_pairVals {g : Series → Series → Nat} {rs : List Series} {x : Nat}
    (h : x ∈ pairVals g rs) : ∃ a ∈ rs, ∃ b ∈ rs, g a b = x := by
  simp only [pairVals, List.mem_flatMap, List.mem_map] at h
  exact h

/-- Every element is at most the maximum.

$$\forall L, x:\ x \in L \;\Rightarrow\; x \le \max{}^{*}(L)$$
-/
theorem le_maxOf : ∀ {l : List Nat} {x : Nat}, x ∈ l → x ≤ maxOf l
  | y :: ys, x, h => by
    simp only [maxOf, List.foldr_cons] at *
    rcases List.mem_cons.mp h with h | h
    · subst h; exact Nat.le_max_left _ _
    · exact Nat.le_trans (le_maxOf h) (Nat.le_max_right _ _)

/-- The maximum is at most any common upper bound.

$$\forall L, m:\ (\forall x \in L:\ x \le m) \;\Rightarrow\; \max{}^{*}(L) \le m$$
-/
theorem maxOf_le : ∀ {l : List Nat} {m : Nat}, (∀ x ∈ l, x ≤ m) → maxOf l ≤ m
  | [], _, _ => Nat.zero_le _
  | y :: ys, m, h => by
    simp only [maxOf, List.foldr_cons]
    exact Nat.max_le.mpr ⟨h y (by simp), maxOf_le (fun x hx => h x (by simp [hx]))⟩

/-- The observed maxima bound every pair.

$$\forall R, a, b:\ a, b \in R \;\Rightarrow\; \operatorname{diff}(a, b) \le k(R) \ \land\ \operatorname{gap}(a, b) \le t(R)$$
-/
theorem le_obs {rs : List Series} {a b : Series} (ha : a ∈ rs) (hb : b ∈ rs) :
    diffFrames a b ≤ kObs rs ∧ totalGap a b ≤ tObs rs :=
  ⟨le_maxOf (mem_pairVals ha hb), le_maxOf (mem_pairVals ha hb)⟩

/-- The observed maxima are at most any bound that holds for every pair.

$$\forall R, k, t:\ (\forall a, b \in R:\ \operatorname{diff}(a, b) \le k \land \operatorname{gap}(a, b) \le t) \;\Rightarrow\; k(R) \le k \ \land\ t(R) \le t$$
-/
theorem obs_le {rs : List Series} {k t : Nat}
    (h : ∀ a ∈ rs, ∀ b ∈ rs, diffFrames a b ≤ k ∧ totalGap a b ≤ t) : kObs rs ≤ k ∧ tObs rs ≤ t := by
  constructor
  · apply maxOf_le; intro x hx
    obtain ⟨a, ha, b, hb, rfl⟩ := of_mem_pairVals hx; exact (h a ha b hb).1
  · apply maxOf_le; intro x hx
    obtain ⟨a, ha, b, hb, rfl⟩ := of_mem_pairVals hx; exact (h a ha b hb).2

/-! ## The class order -/

/-- **Strictness is semantic.** A pair within a class is within every less strict class.

$$\forall c, c', a, b:\ c \preceq c' \ \land\ \operatorname{Within}(c, a, b) \;\Rightarrow\; \operatorname{Within}(c', a, b)$$
-/
theorem within_mono {c c' : Class} {a b : Series} (hle : c.le c' = true) (h : Within c a b) :
    Within c' a b := by
  cases c <;> cases c' <;> simp_all [Class.le, Within]
  · rename_i k t
    have := total_eq_of_diff_zero a b h
    simp [totalGap, this]
  · omega

/-- A class holding for a set of runs holds for every less strict class.

$$\forall c, c', R:\ c \preceq c' \ \land\ \operatorname{Holds}(c, R) \;\Rightarrow\; \operatorname{Holds}(c', R)$$
-/
theorem holds_mono {c c' : Class} {rs : List Series} (hle : c.le c' = true) (h : Holds c rs) :
    Holds c' rs := fun a ha b hb => within_mono hle (h a ha b hb)

/-- A class holding for a set of runs holds for each of its subsets.

$$\forall c, R, R':\ R \subseteq R' \ \land\ \operatorname{Holds}(c, R') \;\Rightarrow\; \operatorname{Holds}(c, R)$$
-/
theorem holds_subset {c : Class} {rs rs' : List Series} (hs : ∀ r ∈ rs, r ∈ rs') (h : Holds c rs') :
    Holds c rs := fun a ha b hb => h a (hs a ha) b (hs b hb)

/-- The order is reflexive.

$$\forall c:\ c \preceq c$$
-/
theorem Class.le_refl : ∀ c : Class, c.le c = true
  | .deterministic => rfl
  | .stable _ _ => by simp [Class.le]
  | .quarantined => rfl

/-- The order is transitive.

$$\forall c, c', c'':\ c \preceq c' \ \land\ c' \preceq c'' \;\Rightarrow\; c \preceq c''$$
-/
theorem Class.le_trans : ∀ {c c' c'' : Class}, c.le c' = true → c'.le c'' = true → c.le c'' = true := by
  intro c c' c'' h1 h2
  cases c <;> cases c' <;> cases c'' <;> simp_all [Class.le] <;> omega

/-- The join is above its left argument.

$$\forall c, c':\ c \preceq c \sqcup c'$$
-/
theorem Class.le_join_left : ∀ c c' : Class, c.le (c.join c') = true := by
  intro c c'; cases c <;> cases c' <;> simp [Class.le, Class.join] <;> omega

/-- The join is above its right argument.

$$\forall c, c':\ c' \preceq c \sqcup c'$$
-/
theorem Class.le_join_right : ∀ c c' : Class, c'.le (c.join c') = true := by
  intro c c'; cases c <;> cases c' <;> simp [Class.le, Class.join] <;> omega

/-! ## Deterministic and stable(0, 0) -/

/-- **Deterministic is stable(0, 0).** A set of runs is deterministic exactly when it is stable
with no differing frame and no total gap; in particular deterministic implies stable(0, 0).

$$\forall R:\ \operatorname{Holds}(\mathrm{det}, R) \iff \operatorname{Holds}(\mathrm{stable}(0, 0), R)$$
-/
theorem holds_det_iff_stable00 (rs : List Series) :
    Holds .deterministic rs ↔ Holds (.stable 0 0) rs := by
  constructor
  · exact holds_mono (by rfl)
  · intro h a ha b hb
    have := (h a ha b hb).1
    simp only [Within]; omega

/-- Deterministic implies stable(0, 0) (the direction asked for, as its own statement).

$$\forall R:\ \operatorname{Holds}(\mathrm{det}, R) \;\Rightarrow\; \operatorname{Holds}(\mathrm{stable}(0, 0), R)$$
-/
theorem det_stable00 {rs : List Series} (h : Holds .deterministic rs) : Holds (.stable 0 0) rs :=
  (holds_det_iff_stable00 rs).mp h

/-! ## Classification -/

/-- **Soundness.** The class that `classify` returns holds for the runs it was computed from.

$$\forall p, R:\ \operatorname{Holds}(\operatorname{classify}_p(R), R)$$
-/
theorem classify_sound (p : Policy) (rs : List Series) : Holds (classify p rs) rs := by
  intro a ha b hb
  have hk := (le_obs ha hb).1
  have ht := (le_obs ha hb).2
  unfold classify
  split
  · simp only [Within]; omega
  · split
    · exact ⟨hk, ht⟩
    · trivial

/-- The class returned is always one the policy allows.

$$\forall p, R:\ \operatorname{adm}_p(\operatorname{classify}_p(R))$$
-/
theorem classify_admissible (p : Policy) (rs : List Series) : Admissible p (classify p rs) := by
  unfold classify
  split
  · trivial
  · split
    · rename_i h; exact h
    · trivial

/-- **Strictest.** Any class the policy allows and the runs satisfy is at most as strict as the
one `classify` returns.

$$\forall p, R, c:\ \operatorname{adm}_p(c) \ \land\ \operatorname{Holds}(c, R) \;\Rightarrow\; \operatorname{classify}_p(R) \preceq c$$
-/
theorem classify_strictest (p : Policy) (rs : List Series) (c : Class) (hc : Admissible p c)
    (h : Holds c rs) : (classify p rs).le c = true := by
  cases c with
  | quarantined => unfold classify; split <;> (try split) <;> rfl
  | deterministic =>
    have : kObs rs = 0 := by
      have := (obs_le (rs := rs) (k := 0) (t := 0) fun a ha b hb => by
        have h0 := h a ha b hb; simp only [Within] at h0
        exact ⟨by omega, by simp [totalGap, total_eq_of_diff_zero a b h0]⟩).1
      omega
    simp [classify, this, Class.le]
  | stable k t =>
    obtain ⟨hk, ht⟩ := obs_le (rs := rs) (k := k) (t := t) h
    obtain ⟨hkp, htp⟩ := hc
    unfold classify
    split
    · rfl
    · have hc' : kObs rs ≤ p.kMax ∧ tObs rs ≤ p.tMax := ⟨Nat.le_trans hk hkp, Nat.le_trans ht htp⟩
      simp [hc', Class.le, hk, ht]

/-- **Monotone in the runs.** Classifying a superset of the runs never gives a stricter class:
adding a run can only keep the class or move it towards quarantined.

$$\forall p, R, R':\ R \subseteq R' \;\Rightarrow\; \operatorname{classify}_p(R) \preceq \operatorname{classify}_p(R')$$
-/
theorem classify_mono (p : Policy) {rs rs' : List Series} (hs : ∀ r ∈ rs, r ∈ rs') :
    (classify p rs).le (classify p rs') = true :=
  classify_strictest p rs _ (classify_admissible p rs') (holds_subset hs (classify_sound p rs'))

/-- Adding one more run never gives a stricter class.

$$\forall p, R, r:\ \operatorname{classify}_p(R) \preceq \operatorname{classify}_p(R \mathbin{+\!\!+} [r])$$
-/
theorem classify_snoc (p : Policy) (rs : List Series) (r : Series) :
    (classify p rs).le (classify p (rs ++ [r])) = true :=
  classify_mono p (fun _ hx => List.mem_append_left _ hx)

/-- `classify` says deterministic exactly when the runs are deterministic.

$$\forall p, R:\ \operatorname{classify}_p(R) = \mathrm{det} \iff \operatorname{Holds}(\mathrm{det}, R)$$
-/
theorem classify_det_iff (p : Policy) (rs : List Series) :
    classify p rs = .deterministic ↔ Holds .deterministic rs := by
  constructor
  · intro h; have := classify_sound p rs; rw [h] at this; exact this
  · intro h
    have := classify_strictest p rs .deterministic trivial h
    revert this; unfold classify; split <;> (try split) <;> simp [Class.le]

/-- `classify` says quarantined exactly when the runs are not stable within the policy bounds.

$$\forall p, R:\ \operatorname{classify}_p(R) = \mathrm{quar} \iff \neg\operatorname{Holds}(\mathrm{stable}(k_{\max}, t_{\max}), R)$$
-/
theorem classify_quarantined_iff (p : Policy) (rs : List Series) :
    classify p rs = .quarantined ↔ ¬ Holds (.stable p.kMax p.tMax) rs := by
  constructor
  · intro h hs
    have := classify_strictest p rs (.stable p.kMax p.tMax)
      (show p.kMax ≤ p.kMax ∧ p.tMax ≤ p.tMax from ⟨Nat.le_refl _, Nat.le_refl _⟩) hs
    rw [h] at this; simp [Class.le] at this
  · intro h
    unfold classify
    split
    · rename_i hk
      exfalso; apply h; intro a ha b hb
      have := (le_obs ha hb).1
      have h0 : diffFrames a b = 0 := by omega
      exact ⟨by omega, by simp [totalGap, total_eq_of_diff_zero a b h0]⟩
    · split
      · rename_i hb
        exfalso; apply h; intro a ha b' hb'
        exact ⟨Nat.le_trans (le_obs ha hb').1 hb.1, Nat.le_trans (le_obs ha hb').2 hb.2⟩
      · rfl

/-! ## Many count types at once (the `measure.classify` op) -/

/-- The series of count type `k` in a run given as per-frame count lists.

$$\operatorname{series}_k([C_1, \dots, C_m]) = [\operatorname{countIn}(C_i, k)]_{i=1}^{m}$$
-/
def seriesOf (k : String) (run : List Counts) : Series := run.map (countIn · k)

/-- One row of the classification table: type, class, observed maxima.

$$\mathrm{Row} = \Sigma^{*} \times \mathrm{Class} \times \mathbb{N} \times \mathbb{N}$$
-/
structure ClassRow where
  type : String
  cls : Class
  k : Nat
  t : Nat
deriving Repr, DecidableEq

/-- Classify every count type that occurs in any frame of any run (sorted by name).

$$\operatorname{classifyAll}_p(\mathcal{R}) = \big[\,(k,\ \operatorname{classify}_p(R_k),\ k(R_k),\ t(R_k))\,\big]_{k \in \operatorname{keys}(\mathcal{R})},\quad R_k = [\operatorname{series}_k(r)]_{r \in \mathcal{R}}$$
-/
def classifyAll (p : Policy) (runs : List (List Counts)) : List ClassRow :=
  (keysOf runs.flatten).map fun k =>
    let rs := runs.map (seriesOf k)
    ⟨k, classify p rs, kObs rs, tObs rs⟩

#guard classifyAll ⟨4, 24⟩ [[[("a", 1)], [("a", 0), ("b", 2)]], [[("a", 1)], [("b", 2)]]] ==
  [⟨"a", .deterministic, 0, 0⟩, ⟨"b", .deterministic, 0, 0⟩]
#guard classifyAll ⟨4, 24⟩ [[[("a", 1)], [("a", 0)]], [[("a", 0)], [("a", 1)]]] == [⟨"a", .stable 2 0, 2, 0⟩]

/-- Each row's class holds for that type's series over all the runs.

$$\forall p, \mathcal{R}, (k, c, \cdot, \cdot) \in \operatorname{classifyAll}_p(\mathcal{R}):\ \operatorname{Holds}(c, [\operatorname{series}_k(r)]_{r \in \mathcal{R}})$$
-/
theorem classifyAll_sound (p : Policy) (runs : List (List Counts)) :
    ∀ row ∈ classifyAll p runs, Holds row.cls (runs.map (seriesOf row.type)) := by
  intro row h
  simp only [classifyAll, List.mem_map] at h
  obtain ⟨k, _, rfl⟩ := h
  exact classify_sound p _

end Fw.Measure
