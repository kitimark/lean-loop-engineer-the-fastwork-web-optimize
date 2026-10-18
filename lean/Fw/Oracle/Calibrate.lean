import Fw.Oracle.Core
/-!
# Fw.Oracle.Calibrate: the threshold of a question, computed from labeled replay rows

A replay row is an answer the model gave and the true label a person assigned. For a threshold `τ`, the *covered*
rows are those the policy advises on; the *hits* are the covered rows whose advice equals the label. `calibrate`
returns the least observed gate value `τ` with at least `n` covered rows and precision hits/covered ≥ target (stated
without division: target · covered ≤ hits), or `none`, and `none` makes every outcome escalate.

The precision is MEASURED on the given rows only; nothing here proves it carries over to new questions.
-/
namespace Fw.Oracle

/-- A labeled replay row: the model's answer and the true label.

$$\mathrm{Row} = \mathrm{Answer} \times \mathrm{Advice}$$ -/
structure Row where
  answer : Answer
  label : Advice
deriving Repr, DecidableEq

/-- The number of rows the policy advises on at threshold `τ`.

$$\mathrm{cov}(s, \tau, R) = |[\, r \in R : \lnot\mathrm{isEsc}(\mathrm{policy}(s, \tau, \mathrm{answer}(r.a))) \,]|$$ -/
def covered (s : Spec) (τ : Rat) (rows : List Row) : Nat :=
  (rows.filter fun r => !(policy s (some τ) (.answer r.answer)).isEscalate).length

/-- The number of rows whose advice at threshold `τ` equals the true label.

$$\mathrm{hits}(s, \tau, R) = |[\, r \in R : \mathrm{policy}(s, \tau, \mathrm{answer}(r.a)) = \mathrm{advise}(r.\ell) \,]|$$ -/
def hits (s : Spec) (τ : Rat) (rows : List Row) : Nat :=
  (rows.filter fun r => policy s (some τ) (.answer r.answer) == .advise r.label).length

/-- A threshold is acceptable when it covers at least `n` rows with precision at least `target`.

$$\mathrm{ok}(s, q, n, R, \tau) \iff n \le \mathrm{cov}(s, \tau, R) \land q \cdot \mathrm{cov}(s, \tau, R) \le \mathrm{hits}(s, \tau, R)$$ -/
def okAt (s : Spec) (target : Rat) (n : Nat) (rows : List Row) (τ : Rat) : Bool :=
  decide (n ≤ covered s τ rows) && decide (target * (covered s τ rows : Rat) ≤ (hits s τ rows : Rat))

/-- The least element of a list, `none` for the empty list.

$$\mathrm{least}([\,]) = \bot, \quad \mathrm{least}(x :: xs) = \begin{cases} x & \mathrm{least}(xs) = \bot \\ \min(x, y) & \mathrm{least}(xs) = y \end{cases}$$ -/
def least : List Rat → Option Rat
  | [] => none
  | x :: xs =>
    match least xs with
    | none => some x
    | some y => some (if x ≤ y then x else y)

/-- The least element is an element.

$$\forall L, m:\ \mathrm{least}(L) = m \Rightarrow m \in L$$ -/
theorem least_mem : ∀ (l : List Rat) (m : Rat), least l = some m → m ∈ l
  | [], _, h => by simp [least] at h
  | x :: xs, m, h => by
    unfold least at h
    split at h
    · simp at h; subst h; simp
    · rename_i y hy
      simp at h
      split at h
      · subst h; simp
      · subst h; exact List.mem_cons_of_mem _ (least_mem xs y hy)

/-- The least element is below every element.

$$\forall L, m:\ \mathrm{least}(L) = m \Rightarrow \forall x \in L:\ m \le x$$ -/
theorem least_le : ∀ (l : List Rat) (m : Rat), least l = some m → ∀ x ∈ l, m ≤ x
  | [], _, h, _, _ => by simp [least] at h
  | x :: xs, m, h, w, hw => by
    unfold least at h
    split at h
    · rename_i hn
      simp at h; subst h
      rcases List.mem_cons.mp hw with rfl | hw'
      · exact Rat.le_refl
      · cases xs with
        | nil => simp at hw'
        | cons x' xs' =>
          unfold least at hn
          split at hn <;> simp at hn
    · rename_i y hy
      simp at h
      have hyw : ∀ u ∈ xs, y ≤ u := least_le xs y hy
      split at h
      · rename_i hxy
        subst h
        rcases List.mem_cons.mp hw with rfl | hw'
        · exact Rat.le_refl
        · exact Rat.le_trans hxy (hyw w hw')
      · rename_i hxy
        subst h
        rcases List.mem_cons.mp hw with rfl | hw'
        · exact Rat.le_of_lt (Rat.not_le.mp hxy)
        · exact hyw w hw'

/-- `least` is `none` only for the empty list.

$$\forall L:\ \mathrm{least}(L) = \bot \iff L = [\,]$$ -/
theorem least_none (l : List Rat) : least l = none ↔ l = [] := by
  cases l with
  | nil => simp [least]
  | cons x xs =>
    simp only [least, reduceCtorEq, iff_false]
    split <;> simp

/-- **Calibration** (the `oracle.calibrate` op): the least gate value observed in the rows that is an acceptable
threshold, or `none` when no observed value is.

$$\mathrm{calibrate}(s, q, n, R) = \mathrm{least}([\, \mathrm{gate}(r.a) : r \in R,\ \mathrm{ok}(s, q, n, R, \mathrm{gate}(r.a)) \,])$$ -/
def calibrate (s : Spec) (target : Rat) (n : Nat) (rows : List Row) : Option Rat :=
  least ((rows.map (gate ·.answer)).filter (okAt s target n rows))

/-- **Calibration is sound on its data.** At the returned threshold at least `n` rows are covered and the precision on
them reaches the target.

$$\forall s, q, n, R, \tau:\ \mathrm{calibrate}(s, q, n, R) = \tau \Rightarrow n \le \mathrm{cov}(s, \tau, R) \land q \cdot \mathrm{cov}(s, \tau, R) \le \mathrm{hits}(s, \tau, R)$$ -/
theorem calibrate_sound (s : Spec) (target : Rat) (n : Nat) (rows : List Row) (τ : Rat)
    (h : calibrate s target n rows = some τ) :
    n ≤ covered s τ rows ∧ target * (covered s τ rows : Rat) ≤ (hits s τ rows : Rat) := by
  have hm := least_mem _ τ h
  have hok := (List.mem_filter.mp hm).2
  simp only [okAt, Bool.and_eq_true, decide_eq_true_eq] at hok
  exact hok

/-- **The returned threshold is the least acceptable observed gate value.**

$$\forall s, q, n, R, \tau:\ \mathrm{calibrate}(s, q, n, R) = \tau \Rightarrow \forall r \in R:\ \mathrm{ok}(s, q, n, R, \mathrm{gate}(r.a)) \Rightarrow \tau \le \mathrm{gate}(r.a)$$ -/
theorem calibrate_least (s : Spec) (target : Rat) (n : Nat) (rows : List Row) (τ : Rat)
    (h : calibrate s target n rows = some τ) (r : Row) (hr : r ∈ rows) (hok : okAt s target n rows (gate r.answer) = true) :
    τ ≤ gate r.answer :=
  least_le _ τ h _ (List.mem_filter.mpr ⟨List.mem_map.mpr ⟨r, hr, rfl⟩, hok⟩)

/-- **No calibration, no advice.** When calibration finds no threshold, every outcome escalates under the stored
result.

$$\forall s, q, n, R:\ \mathrm{calibrate}(s, q, n, R) = \bot \Rightarrow \forall o:\ \exists r:\ \mathrm{policy}(s, \mathrm{calibrate}(s, q, n, R), o) = \mathrm{escalate}(r)$$ -/
theorem calibrate_none_escalates (s : Spec) (target : Rat) (n : Nat) (rows : List Row)
    (h : calibrate s target n rows = none) (o : Outcome) :
    ∃ r, policy s (calibrate s target n rows) o = .escalate r := by
  rw [h]; exact uncalibrated_escalates s o

/-- **No acceptable row, no threshold.** Calibration returns `none` exactly when no row's gate value is acceptable
(so an empty replay set, or one with fewer than `n` coverable rows, always escalates).

$$\forall s, q, n, R:\ \mathrm{calibrate}(s, q, n, R) = \bot \iff \forall r \in R:\ \lnot\mathrm{ok}(s, q, n, R, \mathrm{gate}(r.a))$$ -/
theorem calibrate_none_iff (s : Spec) (target : Rat) (n : Nat) (rows : List Row) :
    calibrate s target n rows = none ↔ ∀ r ∈ rows, okAt s target n rows (gate r.answer) = false := by
  unfold calibrate
  rw [least_none, List.filter_eq_nil_iff]
  constructor
  · intro h r hr
    have := h _ (List.mem_map.mpr ⟨r, hr, rfl⟩)
    simpa using this
  · intro h x hx
    obtain ⟨r, hr, rfl⟩ := List.mem_map.mp hx
    simp [h r hr]

end Fw.Oracle
