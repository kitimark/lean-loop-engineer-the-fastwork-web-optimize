import Fw.Oracle.Core
/-!
# Fw.Oracle.Calibrate: a threshold per option, computed from that option's labeled replay rows

A replay row is an answer the model gave and the true label a person assigned. Calibration is per option, with no
pooling: for an option `o` and a threshold `τ`, the *advised* rows are those the policy advises as `o`, and the
*hits* are the advised rows labeled `o`. `calibrateOpt` returns the least observed gate value `τ` at which at least
`max 1 k` rows are hits and the precision hits/advised reaches the target `q` (stated without division:
`q · advised ≤ hits`), or `none`. `calibrate` keeps one such threshold per advisable option (`Spec.advisable`); an
option without one is absent from the table.

`decideOpt` is the decision the client runs: an answer is advised only under the threshold of its own option, so a
weak option cannot ride on a strong one (`decideOpt_local`: advising `o` depends on `o`'s entry alone). On the rows
it was calibrated on, every advice `o` the table gives has precision at least `q` and at least `max 1 k` hits among
the rows it advises as `o` (`per_option_sound`). An option with fewer than `max 1 k` labeled rows, or one the model
never answers, gets no threshold (`calibrate_none_of_sparse`, `never_answered_none`).

Held-out certification: the replay rows are split by id (`heldOut`: the code points of the id sum to an odd number),
so no author chooses which rows test a threshold. `certify` (the table `oracle.calibrate` returns) chooses each
option's threshold on the choose part and keeps it only when the same value passes `holdOk` on the holdout part:
`okOpt` there, and the Wilson score lower bound (`wilsonOk`, one-sided, `z = 1.645`) of that option's held-out
precision is at least `q`. Any advice under the certified table has at least `max 1 k` hits and point precision at
least `q` on both parts, and a held-out Wilson lower bound of at least `q` (`holdout_certified`, `wilsonOk_sound`);
at `q = 9/10` that takes at least 25 held-out rows advised as the option. The holdout rows can remove a threshold but
never change one (`choose_independent_of_holdout`), and an option with fewer than `max 1 k` holdout rows gets none
(`certify_none_of_sparse_holdout`). `evalBy` (the `oracle.eval` op, on the holdout part) counts coverage and hits.

The Wilson bound treats the held-out rows advised as an option as independent draws with one hit rate; that is an
assumption about the replay set, not something Lean checks. Nothing here proves the precision carries over to new
questions.
-/
namespace Fw.Oracle

/-- A labeled replay row: the model's answer and the true label. -/
structure Row where
  answer : Answer
  label : Advice
deriving Repr, DecidableEq

/-- The advice values a question can give (the no-match option is never advised): every option of a Choice but the
no-match option, yes and no for a Noul, every level index of a Score. -/
def Spec.advisable : Spec → List Advice
  | .choice os z => (os.filter (· != z)).map .pick
  | .noul => [.yes, .no]
  | .score ls => (List.range ls.length).map .level

/-! ## The decision under a per-option table -/

/-- A threshold table: a threshold per option (the first entry of an option counts; an option without an entry has
no threshold). -/
abbrev Thresholds := List (Advice × Rat)

/-- **The decision** (the `oracle.decide` op): a failure escalates with it; an answer goes through `policy` under the
threshold of its own advice, or with no threshold (so it escalates as uncalibrated) when the table has no entry for
that advice. -/
def decideOpt (s : Spec) (th : Thresholds) : Outcome → Action
  | .failure f => .escalate (.failure f)
  | .answer a => policy s (th.lookup (adviceOf a)) (.answer a)

/-- The policy advises only an answer's own advice. -/
theorem policy_advise_eq (s : Spec) (t : Option Rat) (a : Answer) (v : Advice)
    (h : policy s t (.answer a) = .advise v) : v = adviceOf a := by
  obtain ⟨a', _, ho, _, _, _, _, _, _, _, hv⟩ := advise_sound s t _ v h
  cases ho; exact hv

/-- **What an advice under a table certifies.** It comes from an answer whose own advice it is, under that advice's
entry `τ` of the table, with `τ` in (0, 1] reached by the gate value, from a well-typed answer of a well-formed
question that is not the no-match option. -/
theorem decideOpt_advise (s : Spec) (th : Thresholds) (o : Outcome) (v : Advice) (h : decideOpt s th o = .advise v) :
    ∃ a τ, o = .answer a ∧ th.lookup v = some τ ∧ s.wf = true ∧ wt s a = true ∧ 0 < τ ∧ τ ≤ 1 ∧ τ ≤ gate a ∧
      isNoMatch s a = false ∧ v = adviceOf a := by
  cases o with
  | failure f => simp [decideOpt] at h
  | answer a =>
    obtain ⟨a', τ, ho, ht, hw, hwt, h0, h1, hg, hn, hv⟩ :=
      advise_sound s (th.lookup (adviceOf a)) (.answer a) v h
    simp only [Outcome.answer.injEq] at ho
    subst ho
    exact ⟨a, τ, rfl, by rw [hv]; exact ht, hw, hwt, h0, h1, hg, hn, hv⟩

/-- **Advising `o` reads only `o`'s entry.** Two tables with the same entry for `o` advise `o` on exactly the same
outcomes, whatever their other entries. -/
theorem decideOpt_local (s : Spec) (th th' : Thresholds) (v : Advice) (o : Outcome)
    (h : th.lookup v = th'.lookup v) : decideOpt s th o = .advise v ↔ decideOpt s th' o = .advise v := by
  cases o with
  | failure f => simp [decideOpt]
  | answer a =>
    by_cases hv : adviceOf a = v
    · simp only [decideOpt, hv, h]
    · constructor
      · intro hp; exact absurd (policy_advise_eq s _ a v hp).symm hv
      · intro hp; exact absurd (policy_advise_eq s _ a v hp).symm hv

/-- **An empty table never advises.** -/
theorem decideOpt_empty (s : Spec) (o : Outcome) : ∃ r, decideOpt s [] o = .escalate r := by
  cases o with
  | failure f => exact ⟨_, rfl⟩
  | answer a => exact uncalibrated_escalates s (.answer a)

/-- **An option without an entry never advises**: an answer whose advice has no entry escalates. -/
theorem decideOpt_missing (s : Spec) (th : Thresholds) (a : Answer) (h : th.lookup (adviceOf a) = none) :
    ∃ r, decideOpt s th (.answer a) = .escalate r := by
  simp only [decideOpt, h]; exact uncalibrated_escalates s (.answer a)

/-! ## Counting one option's rows -/

/-- The rows the policy at threshold `τ` advises as `o`. -/
def advisedAs (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => policy s (some τ) (.answer r.answer) == .advise o).length

/-- The hits on option `o`: the rows on which the policy at threshold `τ` advises `o` and whose true label is `o`. -/
def hitsAs (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => policy s (some τ) (.answer r.answer) == .advise o && r.label == o).length

/-- The rows the decision under table `T` advises as `o`. -/
def advisedBy (s : Spec) (th : Thresholds) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => decideOpt s th (.answer r.answer) == .advise o).length

/-- The rows the decision under table `T` advises as `o` whose true label is `o`. -/
def hitsBy (s : Spec) (th : Thresholds) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => decideOpt s th (.answer r.answer) == .advise o && r.label == o).length

/-- Under a table whose entry for `o` is `τ`, the decision advises `o` exactly when the policy at `τ` does. -/
theorem decideOpt_iff_policy (s : Spec) (th : Thresholds) (o : Advice) (τ : Rat) (a : Answer)
    (h : th.lookup o = some τ) :
    decideOpt s th (.answer a) = .advise o ↔ policy s (some τ) (.answer a) = .advise o := by
  by_cases hv : adviceOf a = o
  · simp only [decideOpt, hv, h]
  · constructor
    · intro hp; exact absurd (policy_advise_eq s _ a o hp).symm hv
    · intro hp; exact absurd (policy_advise_eq s _ a o hp).symm hv

/-- Under a table whose entry for `o` is `τ`, the rows advised as `o` and their hits are those of the policy at `τ`. -/
theorem counts_by_entry (s : Spec) (th : Thresholds) (rows : List Row) (o : Advice) (τ : Rat)
    (h : th.lookup o = some τ) :
    advisedBy s th rows o = advisedAs s τ rows o ∧ hitsBy s th rows o = hitsAs s τ rows o := by
  have e : ∀ r : Row, (decideOpt s th (.answer r.answer) == .advise o) =
      (policy s (some τ) (.answer r.answer) == .advise o) := fun r =>
    Bool.eq_iff_iff.mpr (by simpa only [beq_iff_eq] using decideOpt_iff_policy s th o τ r.answer h)
  simp [advisedBy, advisedAs, hitsBy, hitsAs, e]

/-- The least element of a list, `none` for the empty list. -/
def least : List Rat → Option Rat
  | [] => none
  | x :: xs =>
    match least xs with
    | none => some x
    | some y => some (if x ≤ y then x else y)

/-- The least element is an element. -/
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

/-- The least element is below every element. -/
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

/-- `least` is `none` only for the empty list. -/
theorem least_none (l : List Rat) : least l = none ↔ l = [] := by
  cases l with
  | nil => simp [least]
  | cons x xs =>
    simp only [least, reduceCtorEq, iff_false]
    split <;> simp

/-! ## Calibration, one option at a time -/

/-- A threshold `τ` is acceptable for option `o` when at least `max 1 k` rows advised as `o` at `τ` are hits and the
precision on the rows advised as `o` is at least `q`. -/
def okOpt (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat) : Bool :=
  decide (max 1 k ≤ hitsAs s τ rows o) && decide (q * (advisedAs s τ rows o : Rat) ≤ (hitsAs s τ rows o : Rat))

/-- The threshold of one option: the least gate value observed in the rows that is acceptable for `o`, or `none`. -/
def calibrateOpt (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) : Option Rat :=
  least ((rows.map (gate ·.answer)).filter (okOpt s q k rows o))

/-- **Calibration** on one row set (`certify` applies `calibrateOpt` to the choose part): for each advisable option in order, its
threshold when it has one. -/
def calibrate (s : Spec) (q : Rat) (k : Nat) (rows : List Row) : Thresholds :=
  s.advisable.filterMap fun o => (calibrateOpt s q k rows o).map (o, ·)

/-- Looking up an option in a table built from a list of options gives that option's value when it is listed. -/
theorem lookup_filterMap (f : Advice → Option Rat) (o : Advice) :
    ∀ L : List Advice, (L.filterMap fun x => (f x).map (x, ·)).lookup o = if o ∈ L then f o else none
  | [] => by simp
  | x :: xs => by
    have ih := lookup_filterMap f o xs
    cases hx : f x with
    | none =>
      simp only [List.filterMap_cons, hx, Option.map_none, ih, List.mem_cons]
      by_cases hox : o = x
      · subst hox; simp [hx]
      · simp [hox]
    | some t =>
      simp only [List.filterMap_cons, hx, Option.map_some, List.lookup_cons, List.mem_cons]
      by_cases hox : o = x
      · subst hox; simp [hx]
      · have : (o == x) = false := by simpa using hox
        simp [this, ih, hox]

/-- **The table's entry for `o` is `o`'s own calibration** (and none for an option the question cannot advise). -/
theorem calibrate_lookup (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) :
    (calibrate s q k rows).lookup o = if o ∈ s.advisable then calibrateOpt s q k rows o else none :=
  lookup_filterMap _ o _

/-- **One option's calibration is sound on its data.** At the returned threshold at least `max 1 k` rows advised as
`o` are hits, and the precision on the rows advised as `o` reaches `q`. -/
theorem calibrateOpt_sound (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat)
    (h : calibrateOpt s q k rows o = some τ) :
    max 1 k ≤ hitsAs s τ rows o ∧ q * (advisedAs s τ rows o : Rat) ≤ (hitsAs s τ rows o : Rat) := by
  have hm := least_mem _ τ h
  have hτ : okOpt s q k rows o τ = true := (List.mem_filter.mp hm).2
  simpa only [okOpt, Bool.and_eq_true, decide_eq_true_eq] using hτ

/-- **One option's threshold is its least acceptable observed gate value.** -/
theorem calibrateOpt_least (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat)
    (h : calibrateOpt s q k rows o = some τ) (r : Row) (hr : r ∈ rows)
    (hok : okOpt s q k rows o (gate r.answer) = true) : τ ≤ gate r.answer :=
  least_le _ τ h _ (List.mem_filter.mpr ⟨List.mem_map.mpr ⟨r, hr, rfl⟩, hok⟩)

/-- **Per-option soundness.** If the decision under the calibrated table advises `o` on any outcome, then `o` is an
advisable option and, on the calibration rows, among the rows that same decision advises as `o` at least `max 1 k`
are labeled `o` and the precision is at least `q`. No other option's rows enter this count. -/
theorem per_option_sound (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (x : Outcome) (o : Advice)
    (h : decideOpt s (calibrate s q k rows) x = .advise o) :
    o ∈ s.advisable ∧ max 1 k ≤ hitsBy s (calibrate s q k rows) rows o ∧
      q * (advisedBy s (calibrate s q k rows) rows o : Rat) ≤ (hitsBy s (calibrate s q k rows) rows o : Rat) := by
  obtain ⟨_, τ, _, hl, _⟩ := decideOpt_advise s _ x o h
  have hl' := hl
  rw [calibrate_lookup] at hl'
  by_cases ho : o ∈ s.advisable
  · simp only [ho, ite_true] at hl'
    have hs := calibrateOpt_sound s q k rows o τ hl'
    obtain ⟨ha, hh⟩ := counts_by_entry s _ rows o τ hl
    rw [ha, hh]
    exact ⟨ho, hs⟩
  · simp [ho] at hl'

/-- The hits on `o` are among the rows labeled `o`. -/
theorem hitsAs_le (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) :
    hitsAs s τ rows o ≤ (rows.filter (·.label == o)).length := by
  unfold hitsAs
  induction rows with
  | nil => simp
  | cons r rs ih =>
    simp only [List.filter_cons]
    by_cases h1 : r.label == o <;> by_cases h2 : policy s (some τ) (.answer r.answer) == .advise o <;>
      simp [h1, h2] <;> omega

/-- A model whose answers never give the advice `o` has no hits on `o`. -/
theorem hitsAs_eq_zero (s : Spec) (τ : Rat) (rows : List Row) (o : Advice)
    (h : ∀ r ∈ rows, adviceOf r.answer ≠ o) : hitsAs s τ rows o = 0 := by
  unfold hitsAs
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro r hr hp
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact h r hr (policy_advise_eq s _ _ o hp.1).symm

/-- **A sparse option gets no threshold.** If fewer than `max 1 k` rows are labeled `o`, the table has no entry for
`o` (so an answer advising `o` escalates), whatever the model answered. -/
theorem calibrate_none_of_sparse (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice)
    (hk : (rows.filter (·.label == o)).length < max 1 k) : (calibrate s q k rows).lookup o = none := by
  rw [calibrate_lookup]
  split
  · cases hc : calibrateOpt s q k rows o with
    | none => rfl
    | some τ =>
      have := (calibrateOpt_sound s q k rows o τ hc).1
      have := hitsAs_le s τ rows o
      omega
  · rfl

/-- **An option the model never answers gets no threshold.** In particular a model that gives the same advice `o₀`
on every row gets a threshold for no other option, however the rows are labeled. -/
theorem never_answered_none (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice)
    (h : ∀ r ∈ rows, adviceOf r.answer ≠ o) : (calibrate s q k rows).lookup o = none := by
  rw [calibrate_lookup]
  split
  · cases hc : calibrateOpt s q k rows o with
    | none => rfl
    | some τ =>
      have := (calibrateOpt_sound s q k rows o τ hc).1
      have := hitsAs_eq_zero s τ rows o h
      omega
  · rfl

-- the replay probes: a question with three advisable options and the no-match option `unknown`
private def triSpec : Spec := .choice ["flake", "infra", "real", "unknown"] "unknown"
private def says (pick l : String) : Row :=
  { answer := .choice pick (["flake", "infra", "real", "unknown"].map fun x => if x == pick then 1 else 0)
    label := .pick l }
#guard triSpec.advisable == [.pick "flake", .pick "infra", .pick "real"]
-- round 1: always `real` on 27 `real` and 1 `flake` rows: only `real` gets a threshold
#guard calibrate triSpec (9/10) 1 (List.replicate 27 (says "real" "real") ++ [says "real" "flake"]) ==
  [(.pick "real", 1)]
-- round 2: always `real` on 5 `flake`, 5 `infra`, 90 `real` rows: `flake` and `infra` get none
#guard calibrate triSpec (9/10) 5
  (List.replicate 5 (says "real" "flake") ++ List.replicate 5 (says "real" "infra") ++
    List.replicate 90 (says "real" "real")) == [(.pick "real", 1)]
-- round 3: `flake` advised 16 times with 5 right (precision 5/16) is never advisable; `infra` and `real` are
#guard calibrate triSpec (9/10) 5
  (List.replicate 5 (says "flake" "flake") ++ List.replicate 11 (says "flake" "real") ++
    List.replicate 5 (says "infra" "infra") ++ List.replicate 90 (says "real" "real")) ==
  [(.pick "infra", 1), (.pick "real", 1)]
#guard decideOpt triSpec [(.pick "infra", 1), (.pick "real", 1)] (.answer (says "flake" "flake").answer) ==
  .escalate .uncalibrated
-- a confident model that is right on every row of the same set calibrates every option
#guard calibrate triSpec (9/10) 5
  (List.replicate 5 (says "flake" "flake") ++ List.replicate 5 (says "infra" "infra") ++
    List.replicate 90 (says "real" "real")) == [(.pick "flake", 1), (.pick "infra", 1), (.pick "real", 1)]
-- k = 0 still needs one hit
#guard calibrate triSpec 0 0 [{ answer := .choice "real" [1/4, 1/4, 1/4, 1/4], label := .pick "real" }] == []
#guard calibrate triSpec 0 0 [] == []

/-! ## The Wilson lower bound -/

/-- The one-sided 95 % normal quantile used by the held-out test, rounded to three places. -/
def wilsonZ : Rat := 1645 / 1000

/-- **The Wilson score test**: `h` hits among `n` advised rows show a hit rate of at least `q` when `n > 0`, `q < 1`,
`h ≥ q · n` and the score statistic at `q` reaches `z`, stated without square roots or division. By `wilsonOk_sound`
this holds only when the Wilson score lower bound of `h/n` at quantile `z` is at least `q`. The Wilson bound is used
rather than Clopper-Pearson because it is a polynomial inequality over the rationals (no beta quantiles), so Lean
decides it exactly. -/
def wilsonOk (z q : Rat) (h n : Nat) : Bool :=
  decide (0 < n) && decide (q < 1) && decide (q * n ≤ h) &&
    decide (z * z * n * q * (1 - q) ≤ (h - q * n) * (h - q * n))

private theorem wilson_core (N H q p Z : Rat) (hN : 0 < N) (hZ : 0 < Z) (hq1 : q < 1) (hHN : H ≤ N)
    (ha : q * N ≤ H) (hw : Z * N * q * (1 - q) ≤ (H - q * N) * (H - q * N)) (hp : p < q) :
    Z * q ≤ N * (1 - q) ∧ N * p < H ∧ Z * N * p * (1 - p) < (H - N * p) * (H - N * p) := by
  have ha0 : 0 ≤ H - q * N := by grind
  have haN : H - q * N ≤ N * (1 - q) := by grind
  have hm : 0 < N * (1 - q) := Rat.mul_pos hN (by grind)
  have h1 : (H - q * N) * (H - q * N) ≤ (H - q * N) * (N * (1 - q)) :=
    Rat.mul_le_mul_of_nonneg_left haN ha0
  have h2 : (Z * q) * (N * (1 - q)) ≤ (H - q * N) * (N * (1 - q)) := by
    have : (Z * q) * (N * (1 - q)) = Z * N * q * (1 - q) := by grind
    grind
  have hzq : Z * q ≤ H - q * N := Rat.le_of_mul_le_mul_right h2 hm
  have hX1 : 0 < N * (2 * (H - q * N) + Z * (1 - 2 * q)) := Rat.mul_pos hN (by grind)
  have hA : 0 < N * N + Z * N := by
    have := Rat.mul_pos hN hN
    have := Rat.mul_pos hZ hN
    grind
  have hX2 : 0 < (N * N + Z * N) * (q - p) := Rat.mul_pos hA (by grind)
  have hX : 0 < (q - p) * (N * (2 * (H - q * N) + Z * (1 - 2 * q)) + (N * N + Z * N) * (q - p)) :=
    Rat.mul_pos (by grind) (by grind)
  have e : (H - N * p) * (H - N * p) - Z * N * p * (1 - p) =
      ((H - q * N) * (H - q * N) - Z * N * q * (1 - q)) +
        (q - p) * (N * (2 * (H - q * N) + Z * (1 - 2 * q)) + (N * N + Z * N) * (q - p)) := by
    grind
  have hnp : N * (q - p) > 0 := Rat.mul_pos hN (by grind)
  refine ⟨by grind, by grind, by grind⟩

/-- **The Wilson test bounds the rate from below.** If `wilsonOk z q h n` (with `z > 0` and `h ≤ n`), then every rate
`p < q` lies below the observed rate and is rejected by the one-sided score test: `h/n` is more than `z` standard
errors above `p`. So the Wilson score lower bound `L` of `h/n` (the least `p` the test does not reject) is at least
`q`. It also needs `z² q ≤ n (1 − q)` rows: at `q = 9/10` and `z = 1.645`, at least 25. -/
theorem wilsonOk_sound (z q : Rat) (h n : Nat) (hz : 0 < z) (hn : h ≤ n) (hw : wilsonOk z q h n = true) :
    z * z * q ≤ n * (1 - q) ∧
      ∀ p : Rat, p < q → n * p < h ∧ z * z * n * p * (1 - p) < (h - n * p) * (h - n * p) := by
  simp only [wilsonOk, Bool.and_eq_true, decide_eq_true_eq] at hw
  obtain ⟨⟨⟨h0, hq1⟩, ha⟩, hw⟩ := hw
  have hN : (0 : Rat) < n := by exact_mod_cast h0
  have hHN : (h : Rat) ≤ n := by exact_mod_cast hn
  have hZ := Rat.mul_pos hz hz
  refine ⟨?_, fun p hp => ?_⟩
  · have := (wilson_core n h q (q - 1) (z * z) hN hZ hq1 hHN ha hw (by grind)).1
    exact this
  · have := wilson_core n h q p (z * z) hN hZ hq1 hHN ha hw hp
    exact ⟨this.2.1, this.2.2⟩

#guard !wilsonOk wilsonZ (9/10) 5 16
#guard !wilsonOk wilsonZ (9/10) 15 16
#guard !wilsonOk wilsonZ (9/10) 24 24
#guard wilsonOk wilsonZ (9/10) 25 25
#guard !wilsonOk wilsonZ (9/10) 44 50
#guard wilsonOk wilsonZ (9/10) 100 104
#guard !wilsonOk wilsonZ 1 50 50
#guard !wilsonOk wilsonZ (1/2) 0 0

/-! ## Held-out certification -/

/-- The sum of the code points of a row id. -/
def idSum (i : String) : Nat := (i.toList.map Char.toNat).sum

/-- **The split by id**: a row is held out exactly when the code points of its id sum to an odd number; every other
row is in the choose part. The replay file names no split, so no author picks which rows test a threshold. -/
def heldOut (i : String) : Bool := idSum i % 2 == 1

/-- A labeled replay row with its id. -/
abbrev IdRow := String × Row

/-- The choose part: the rows whose id is not held out, in order. -/
def choosePart (rs : List IdRow) : List Row := (rs.filter fun p => !heldOut p.1).map (·.2)

/-- The holdout part: the rows whose id is held out, in order. -/
def holdPart (rs : List IdRow) : List Row := (rs.filter fun p => heldOut p.1).map (·.2)

/-- The hits on `o` are among the rows advised as `o`. -/
theorem hitsAs_le_advisedAs (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) :
    hitsAs s τ rows o ≤ advisedAs s τ rows o := by
  unfold hitsAs advisedAs
  induction rows with
  | nil => simp
  | cons r rs ih =>
    simp only [List.filter_cons]
    by_cases h1 : r.label == o <;> by_cases h2 : policy s (some τ) (.answer r.answer) == .advise o <;>
      simp [h1, h2] <;> omega

/-- **The holdout test** of option `o` at `τ`: `τ` is acceptable for `o` on the rows (`okOpt`), and the Wilson score
lower bound of the hit rate among the rows advised as `o` is at least `q` (`wilsonOk` at `wilsonZ`). -/
def holdOk (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat) : Bool :=
  okOpt s q k rows o τ && wilsonOk wilsonZ q (hitsAs s τ rows o) (advisedAs s τ rows o)

/-- The certified threshold of one option: the threshold chosen on the choose part, kept only when that same value
passes the holdout test for `o` on the holdout part, else none. -/
def certOpt (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice) : Option Rat :=
  (calibrateOpt s q k (choosePart rs) o).filter (holdOk s q k (holdPart rs) o)

/-- **Certified calibration** (the table `oracle.calibrate` returns): for each advisable option in order, its
certified threshold when it has one. -/
def certify (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) : Thresholds :=
  s.advisable.filterMap fun o => (certOpt s q k rs o).map (o, ·)

/-- The certified table's entry for `o` is `o`'s certified threshold (none for an option the question cannot advise). -/
theorem certify_lookup (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice) :
    (certify s q k rs).lookup o = if o ∈ s.advisable then certOpt s q k rs o else none :=
  lookup_filterMap _ o _

/-- **A certified entry is the choose part's threshold, passing the holdout test on the holdout part.** -/
theorem certify_entry (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice) (τ : Rat)
    (h : (certify s q k rs).lookup o = some τ) :
    o ∈ s.advisable ∧ calibrateOpt s q k (choosePart rs) o = some τ ∧ holdOk s q k (holdPart rs) o τ = true := by
  rw [certify_lookup] at h
  by_cases ho : o ∈ s.advisable
  · simp only [ho, ite_true, certOpt] at h
    cases hc : calibrateOpt s q k (choosePart rs) o with
    | none => simp [hc] at h
    | some t =>
      rw [hc] at h
      by_cases hk : holdOk s q k (holdPart rs) o t = true
      · simp only [Option.filter, hk, ite_true, Option.some.injEq] at h
        subst h
        exact ⟨ho, rfl, hk⟩
      · simp [Option.filter, hk] at h
  · simp [ho] at h

/-- **Holdout certification.** If the decision under the certified table advises `o` on any outcome, then `o` is
advisable and, on the holdout rows, among the `n` rows that same decision advises as `o` the `h` hits (rows labeled
`o`) number at least `max 1 k`, the precision `h/n` is at least `q`, and every rate `p < q` is rejected by the
one-sided score test at `z = wilsonZ`, so the Wilson lower bound of `h/n` is at least `q` (`wilsonOk_sound`). On the
choose rows the hits and the point precision meet the same bounds. No other option's rows enter these counts. -/
theorem holdout_certified (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (x : Outcome) (o : Advice)
    (h : decideOpt s (certify s q k rs) x = .advise o) :
    o ∈ s.advisable ∧
      (max 1 k ≤ hitsBy s (certify s q k rs) (holdPart rs) o ∧
        q * (advisedBy s (certify s q k rs) (holdPart rs) o : Rat) ≤ (hitsBy s (certify s q k rs) (holdPart rs) o : Rat)) ∧
      (∀ p : Rat, p < q →
        (advisedBy s (certify s q k rs) (holdPart rs) o : Rat) * p < (hitsBy s (certify s q k rs) (holdPart rs) o : Rat) ∧
        wilsonZ * wilsonZ * (advisedBy s (certify s q k rs) (holdPart rs) o : Rat) * p * (1 - p) <
          ((hitsBy s (certify s q k rs) (holdPart rs) o : Rat) - (advisedBy s (certify s q k rs) (holdPart rs) o : Rat) * p) *
          ((hitsBy s (certify s q k rs) (holdPart rs) o : Rat) - (advisedBy s (certify s q k rs) (holdPart rs) o : Rat) * p)) ∧
      (max 1 k ≤ hitsBy s (certify s q k rs) (choosePart rs) o ∧
        q * (advisedBy s (certify s q k rs) (choosePart rs) o : Rat) ≤
          (hitsBy s (certify s q k rs) (choosePart rs) o : Rat)) := by
  obtain ⟨_, τ, _, hl, _⟩ := decideOpt_advise s _ x o h
  obtain ⟨ho, hc, hk⟩ := certify_entry s q k rs o τ hl
  have hs := calibrateOpt_sound s q k (choosePart rs) o τ hc
  simp only [holdOk, okOpt, Bool.and_eq_true, decide_eq_true_eq] at hk
  have hw := (wilsonOk_sound wilsonZ q _ _ (by unfold wilsonZ; grind) (hitsAs_le_advisedAs s τ (holdPart rs) o) hk.2).2
  obtain ⟨ha, hh⟩ := counts_by_entry s _ (holdPart rs) o τ hl
  obtain ⟨ca, ch⟩ := counts_by_entry s _ (choosePart rs) o τ hl
  rw [ha, hh, ca, ch]
  exact ⟨ho, hk.1, hw, hs⟩

/-- **Holdout rows never move a threshold.** Two row sets with the same choose part give the same threshold to every
option both certify; the holdout rows can only remove an entry. -/
theorem choose_independent_of_holdout (s : Spec) (q : Rat) (k : Nat) (rs rs' : List IdRow) (o : Advice) (τ τ' : Rat)
    (hc : choosePart rs = choosePart rs') (h : (certify s q k rs).lookup o = some τ)
    (h' : (certify s q k rs').lookup o = some τ') : τ = τ' := by
  have e := (certify_entry s q k rs o τ h).2.1
  have e' := (certify_entry s q k rs' o τ' h').2.1
  rw [hc, e'] at e
  exact (Option.some.inj e).symm

/-- Appending held-out rows leaves the choose part unchanged. -/
theorem choosePart_append_held (rs extra : List IdRow) (h : ∀ p ∈ extra, heldOut p.1 = true) :
    choosePart (rs ++ extra) = choosePart rs := by
  have : extra.filter (fun p => !heldOut p.1) = [] := List.filter_eq_nil_iff.mpr fun p hp => by simp [h p hp]
  simp [choosePart, List.filter_append, this]

/-- **A sparse holdout gives no threshold.** If fewer than `max 1 k` holdout rows are labeled `o`, the certified
table has no entry for `o`, whatever the choose part shows. -/
theorem certify_none_of_sparse_holdout (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice)
    (hk : ((holdPart rs).filter (·.label == o)).length < max 1 k) : (certify s q k rs).lookup o = none := by
  cases hl : (certify s q k rs).lookup o with
  | none => rfl
  | some τ =>
    have hok := (certify_entry s q k rs o τ hl).2.2
    simp only [holdOk, okOpt, Bool.and_eq_true, decide_eq_true_eq] at hok
    have := hitsAs_le s τ (holdPart rs) o
    omega

#guard heldOut "a" && !heldOut "b" && !heldOut "m001" && heldOut "m002"
private def idRows (l : List (String × Row)) : List IdRow := l
/-- `n` copies of row `r` whose ids (`p` and a number) all fall in the holdout part (`held`) or all in the choose part. -/
private def part (held : Bool) (p : String) (n : Nat) (r : Row) : List IdRow :=
  ((((List.range (4 * n + 8)).map fun i => p ++ toString i).filter fun i => heldOut i == held).take n).map (·, r)
#guard (part true "h" 30 (says "real" "real")).length == 30 && holdPart (part true "h" 30 (says "real" "real")) ==
  List.replicate 30 (says "real" "real") && choosePart (part true "h" 30 (says "real" "real")) == []
-- one right holdout row is too little evidence: the Wilson bound at `q = 9/10` needs 25
#guard certify triSpec (9/10) 1 (idRows [("b", says "real" "real"), ("a", says "real" "real")]) == []
-- no holdout row: nothing is certified, however good the choose part is
#guard certify triSpec (9/10) 1 (idRows [("b", says "real" "real"), ("d", says "real" "real")]) == []
-- the holdout rows disagree: `real` is chosen on the choose part but refused on the holdout part
#guard certify triSpec (9/10) 1 (part false "c" 5 (says "real" "real") ++ part true "h" 30 (says "real" "flake")) == []
-- an option chosen on the choose part but never advised on the holdout part has no evidence there
#guard certify triSpec (9/10) 1 (part false "c" 5 (says "flake" "flake") ++ part true "h" 30 (says "real" "real")) == []
-- a choose part on which every option is right
private def goodChoose : List IdRow :=
  part false "cf" 5 (says "flake" "flake") ++ part false "ci" 5 (says "infra" "infra") ++
    part false "cr" 5 (says "real" "real")
-- the round 5 probe on the holdout part: `flake` advised 16 times with `f` right, 5 `infra`, 25 `real`, all right
private def probeHold (f : Nat) : List IdRow :=
  part true "hf" f (says "flake" "flake") ++ part true "hx" (16 - f) (says "flake" "real") ++
    part true "hi" 5 (says "infra" "infra") ++ part true "hr" 25 (says "real" "real")
-- 5 of 16 right: `flake` is not certified; 5 `infra` rows are too few; 25 right `real` rows are enough
#guard certify triSpec (9/10) 5 (goodChoose ++ probeHold 5) == [(.pick "real", 1)]
-- 15 of 16 right (point precision 15/16 above 9/10): still not certified, the Wilson bound is below 9/10
#guard certify triSpec (9/10) 5 (goodChoose ++ probeHold 15) == [(.pick "real", 1)]
-- 25 right holdout rows per option certify every option
#guard certify triSpec (9/10) 5 (goodChoose ++ part true "hf" 25 (says "flake" "flake") ++
  part true "hi" 25 (says "infra" "infra") ++ part true "hr" 25 (says "real" "real")) ==
  [(.pick "flake", 1), (.pick "infra", 1), (.pick "real", 1)]

/-! ## Held-out evaluation -/

/-- **Held-out evaluation** (the `oracle.eval` op): under table `T`, the number of rows the decision advises on and
the number of those whose advice equals the true label. -/
def evalBy (s : Spec) (th : Thresholds) (rows : List Row) : Nat × Nat :=
  ((rows.filter fun r => !(decideOpt s th (.answer r.answer)).isEscalate).length,
   (rows.filter fun r => decideOpt s th (.answer r.answer) == .advise r.label).length)

/-- **Without a table entry nothing is advised**, so evaluation under the empty table covers no row. -/
theorem evalBy_empty (s : Spec) (rows : List Row) : evalBy s [] rows = (0, 0) := by
  simp only [evalBy, Prod.mk.injEq, List.length_eq_zero_iff, List.filter_eq_nil_iff]
  constructor
  · intro r _
    obtain ⟨x, hx⟩ := decideOpt_empty s (.answer r.answer)
    simp [hx, Action.isEscalate]
  · intro r _
    obtain ⟨x, hx⟩ := decideOpt_empty s (.answer r.answer)
    simp [hx]

#guard evalBy triSpec [(.pick "real", 1/2)] [says "real" "real", says "real" "flake", says "flake" "flake"] == (2, 1)
#guard evalBy triSpec [] [says "real" "real"] == (0, 0)
#guard advisedBy triSpec [(.pick "real", 1/2)] [says "real" "real", says "real" "flake"] (.pick "real") == 2
#guard hitsBy triSpec [(.pick "real", 1/2)] [says "real" "real", says "real" "flake"] (.pick "real") == 1

end Fw.Oracle
