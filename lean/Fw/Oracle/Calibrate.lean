import Fw.Oracle.Core
import Fw.Oracle.Labels
/-! A threshold per option, computed from that option's labeled replay rows. -/
namespace Fw.Oracle

/-- A labeled replay row: the model's answer and the true label. -/
structure Row where
  answer : Answer
  label : Advice
deriving Repr, DecidableEq

/-- The advice values a question can give. -/
def Spec.advisable : Spec → List Advice
  | .choice os z => (os.filter (· != z)).map .pick
  | .noul => [.yes, .no]
  | .score ls => (List.range ls.length).map .level

/-! ## The decision under a per-option table -/

/-- A threshold table: a threshold per option. -/
abbrev Thresholds := List (Advice × Rat)

/-- The decision (the `oracle.decide` op). -/
def decideOpt (s : Spec) (th : Thresholds) : Outcome → Action
  | .failure f => .escalate (.failure f)
  | .answer a => policy s (th.lookup (adviceOf a)) (.answer a)

theorem policy_advise_eq (s : Spec) (t : Option Rat) (a : Answer) (v : Advice)
    (h : policy s t (.answer a) = .advise v) : v = adviceOf a := by
  obtain ⟨a', _, ho, _, _, _, _, _, _, _, hv⟩ := advise_sound s t _ v h
  cases ho; exact hv

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

theorem decideOpt_empty (s : Spec) (o : Outcome) : ∃ r, decideOpt s [] o = .escalate r := by
  cases o with
  | failure f => exact ⟨_, rfl⟩
  | answer a => exact uncalibrated_escalates s (.answer a)

theorem decideOpt_missing (s : Spec) (th : Thresholds) (a : Answer) (h : th.lookup (adviceOf a) = none) :
    ∃ r, decideOpt s th (.answer a) = .escalate r := by
  simp only [decideOpt, h]; exact uncalibrated_escalates s (.answer a)

/-! ## Counting one option's rows -/

def advisedAs (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => policy s (some τ) (.answer r.answer) == .advise o).length

def hitsAs (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => policy s (some τ) (.answer r.answer) == .advise o && r.label == o).length

/-- The rows the decision under table `T` advises as `o`. -/
def advisedBy (s : Spec) (th : Thresholds) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => decideOpt s th (.answer r.answer) == .advise o).length

/-- The rows the decision under table `T` advises as `o` whose true label is `o`. -/
def hitsBy (s : Spec) (th : Thresholds) (rows : List Row) (o : Advice) : Nat :=
  (rows.filter fun r => decideOpt s th (.answer r.answer) == .advise o && r.label == o).length

theorem decideOpt_iff_policy (s : Spec) (th : Thresholds) (o : Advice) (τ : Rat) (a : Answer)
    (h : th.lookup o = some τ) :
    decideOpt s th (.answer a) = .advise o ↔ policy s (some τ) (.answer a) = .advise o := by
  by_cases hv : adviceOf a = o
  · simp only [decideOpt, hv, h]
  · constructor
    · intro hp; exact absurd (policy_advise_eq s _ a o hp).symm hv
    · intro hp; exact absurd (policy_advise_eq s _ a o hp).symm hv

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

theorem least_none (l : List Rat) : least l = none ↔ l = [] := by
  cases l with
  | nil => simp [least]
  | cons x xs =>
    simp only [least, reduceCtorEq, iff_false]
    split <;> simp

/-! ## Calibration, one option at a time -/

def okOpt (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat) : Bool :=
  decide (max 1 k ≤ hitsAs s τ rows o) && decide (q * (advisedAs s τ rows o : Rat) ≤ (hitsAs s τ rows o : Rat))

/-- The threshold of one option: the least gate value observed in the rows that is acceptable for `o`, or `none`. -/
def calibrateOpt (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) : Option Rat :=
  least ((rows.map (gate ·.answer)).filter (okOpt s q k rows o))

/-- Calibration on one row set. -/
def calibrate (s : Spec) (q : Rat) (k : Nat) (rows : List Row) : Thresholds :=
  s.advisable.filterMap fun o => (calibrateOpt s q k rows o).map (o, ·)

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

theorem calibrate_lookup (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) :
    (calibrate s q k rows).lookup o = if o ∈ s.advisable then calibrateOpt s q k rows o else none :=
  lookup_filterMap _ o _

theorem calibrateOpt_sound (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat)
    (h : calibrateOpt s q k rows o = some τ) :
    max 1 k ≤ hitsAs s τ rows o ∧ q * (advisedAs s τ rows o : Rat) ≤ (hitsAs s τ rows o : Rat) := by
  have hm := least_mem _ τ h
  have hτ : okOpt s q k rows o τ = true := (List.mem_filter.mp hm).2
  simpa only [okOpt, Bool.and_eq_true, decide_eq_true_eq] using hτ

theorem calibrateOpt_least (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat)
    (h : calibrateOpt s q k rows o = some τ) (r : Row) (hr : r ∈ rows)
    (hok : okOpt s q k rows o (gate r.answer) = true) : τ ≤ gate r.answer :=
  least_le _ τ h _ (List.mem_filter.mpr ⟨List.mem_map.mpr ⟨r, hr, rfl⟩, hok⟩)

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

theorem hitsAs_le (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) :
    hitsAs s τ rows o ≤ (rows.filter (·.label == o)).length := by
  unfold hitsAs
  induction rows with
  | nil => simp
  | cons r rs ih =>
    simp only [List.filter_cons]
    by_cases h1 : r.label == o <;> by_cases h2 : policy s (some τ) (.answer r.answer) == .advise o <;>
      simp [h1, h2] <;> omega

theorem hitsAs_eq_zero (s : Spec) (τ : Rat) (rows : List Row) (o : Advice)
    (h : ∀ r ∈ rows, adviceOf r.answer ≠ o) : hitsAs s τ rows o = 0 := by
  unfold hitsAs
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro r hr hp
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact h r hr (policy_advise_eq s _ _ o hp.1).symm

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

private def triSpec : Spec := .choice ["flake", "infra", "real", "unknown"] "unknown"
private def says (pick l : String) : Row :=
  { answer := .choice pick (["flake", "infra", "real", "unknown"].map fun x => if x == pick then 1 else 0)
    label := .pick l }
#guard triSpec.advisable == [.pick "flake", .pick "infra", .pick "real"]
#guard calibrate triSpec (9/10) 1 (List.replicate 27 (says "real" "real") ++ [says "real" "flake"]) ==
  [(.pick "real", 1)]
#guard calibrate triSpec (9/10) 5
  (List.replicate 5 (says "real" "flake") ++ List.replicate 5 (says "real" "infra") ++
    List.replicate 90 (says "real" "real")) == [(.pick "real", 1)]
#guard calibrate triSpec (9/10) 5
  (List.replicate 5 (says "flake" "flake") ++ List.replicate 11 (says "flake" "real") ++
    List.replicate 5 (says "infra" "infra") ++ List.replicate 90 (says "real" "real")) ==
  [(.pick "infra", 1), (.pick "real", 1)]
#guard decideOpt triSpec [(.pick "infra", 1), (.pick "real", 1)] (.answer (says "flake" "flake").answer) ==
  .escalate .uncalibrated
#guard calibrate triSpec (9/10) 5
  (List.replicate 5 (says "flake" "flake") ++ List.replicate 5 (says "infra" "infra") ++
    List.replicate 90 (says "real" "real")) == [(.pick "flake", 1), (.pick "infra", 1), (.pick "real", 1)]
#guard calibrate triSpec 0 0 [{ answer := .choice "real" [1/4, 1/4, 1/4, 1/4], label := .pick "real" }] == []
#guard calibrate triSpec 0 0 [] == []

/-! ## The Wilson lower bound -/

def wilsonZ : Rat := 1645 / 1000

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

/-- The split by id: `Labels.heldOut` (FNV-1a 32 of the id is 0 mod 4). -/
def heldOut (i : String) : Bool := Labels.heldOut i

theorem heldOut_canonical : heldOut = Labels.heldOut := rfl

/-- A labeled replay row with its id. -/
abbrev IdRow := String × Row

/-- The choose part: the rows whose id is not held out, in order. -/
def choosePart (rs : List IdRow) : List Row := (rs.filter fun p => !heldOut p.1).map (·.2)

/-- The holdout part: the rows whose id is held out, in order. -/
def holdPart (rs : List IdRow) : List Row := (rs.filter fun p => heldOut p.1).map (·.2)

theorem holdPart_canonical (rs : List IdRow) : holdPart rs = (Labels.heldOutRows Prod.fst rs).map (·.2) := by
  simp only [holdPart, Labels.heldOutRows, heldOut_canonical]
  rfl

theorem choosePart_canonical (rs : List IdRow) :
    choosePart rs = (Labels.calibrationRows Prod.fst rs).map (·.2) := by
  simp only [choosePart, Labels.calibrationRows, heldOut_canonical]
  rfl

theorem hitsAs_le_advisedAs (s : Spec) (τ : Rat) (rows : List Row) (o : Advice) :
    hitsAs s τ rows o ≤ advisedAs s τ rows o := by
  unfold hitsAs advisedAs
  induction rows with
  | nil => simp
  | cons r rs ih =>
    simp only [List.filter_cons]
    by_cases h1 : r.label == o <;> by_cases h2 : policy s (some τ) (.answer r.answer) == .advise o <;>
      simp [h1, h2] <;> omega

def holdOk (s : Spec) (q : Rat) (k : Nat) (rows : List Row) (o : Advice) (τ : Rat) : Bool :=
  okOpt s q k rows o τ && wilsonOk wilsonZ q (hitsAs s τ rows o) (advisedAs s τ rows o)

def certOpt (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice) : Option Rat :=
  (calibrateOpt s q k (choosePart rs) o).filter (holdOk s q k (holdPart rs) o)

/-- Certified calibration (the table `oracle.calibrate` returns). -/
def certify (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) : Thresholds :=
  s.advisable.filterMap fun o => (certOpt s q k rs o).map (o, ·)

theorem certify_split (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) :
    certify s q k rs = s.advisable.filterMap fun o =>
      ((calibrateOpt s q k ((Labels.calibrationRows Prod.fst rs).map (·.2)) o).filter
        (holdOk s q k ((Labels.heldOutRows Prod.fst rs).map (·.2)) o)).map (o, ·) := by
  simp only [certify, certOpt, choosePart_canonical, holdPart_canonical]

theorem certify_lookup (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice) :
    (certify s q k rs).lookup o = if o ∈ s.advisable then certOpt s q k rs o else none :=
  lookup_filterMap _ o _

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

theorem choose_independent_of_holdout (s : Spec) (q : Rat) (k : Nat) (rs rs' : List IdRow) (o : Advice) (τ τ' : Rat)
    (hc : choosePart rs = choosePart rs') (h : (certify s q k rs).lookup o = some τ)
    (h' : (certify s q k rs').lookup o = some τ') : τ = τ' := by
  have e := (certify_entry s q k rs o τ h).2.1
  have e' := (certify_entry s q k rs' o τ' h').2.1
  rw [hc, e'] at e
  exact (Option.some.inj e).symm

theorem choosePart_append_held (rs extra : List IdRow) (h : ∀ p ∈ extra, heldOut p.1 = true) :
    choosePart (rs ++ extra) = choosePart rs := by
  have : extra.filter (fun p => !heldOut p.1) = [] := List.filter_eq_nil_iff.mpr fun p hp => by simp [h p hp]
  simp [choosePart, List.filter_append, this]

theorem certify_none_of_sparse_holdout (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice)
    (hk : ((holdPart rs).filter (·.label == o)).length < max 1 k) : (certify s q k rs).lookup o = none := by
  cases hl : (certify s q k rs).lookup o with
  | none => rfl
  | some τ =>
    have hok := (certify_entry s q k rs o τ hl).2.2
    simp only [holdOk, okOpt, Bool.and_eq_true, decide_eq_true_eq] at hok
    have := hitsAs_le s τ (holdPart rs) o
    omega

#guard heldOut "a" && !heldOut "b" && !heldOut "m001" && heldOut "m004"
private def idRows (l : List (String × Row)) : List IdRow := l
private def part (held : Bool) (p : String) (n : Nat) (r : Row) : List IdRow :=
  ((((List.range (4 * n + 8)).map fun i => p ++ toString i).filter fun i => heldOut i == held).take n).map (·, r)
#guard (part true "h" 30 (says "real" "real")).length == 30 && holdPart (part true "h" 30 (says "real" "real")) ==
  List.replicate 30 (says "real" "real") && choosePart (part true "h" 30 (says "real" "real")) == []
#guard certify triSpec (9/10) 1 (idRows [("b", says "real" "real"), ("a", says "real" "real")]) == []
#guard certify triSpec (9/10) 1 (idRows [("b", says "real" "real"), ("d", says "real" "real")]) == []
#guard certify triSpec (9/10) 1 (part false "c" 5 (says "real" "real") ++ part true "h" 30 (says "real" "flake")) == []
#guard certify triSpec (9/10) 1 (part false "c" 5 (says "flake" "flake") ++ part true "h" 30 (says "real" "real")) == []
private def goodChoose : List IdRow :=
  part false "cf" 5 (says "flake" "flake") ++ part false "ci" 5 (says "infra" "infra") ++
    part false "cr" 5 (says "real" "real")
private def probeHold (f : Nat) : List IdRow :=
  part true "hf" f (says "flake" "flake") ++ part true "hx" (16 - f) (says "flake" "real") ++
    part true "hi" 5 (says "infra" "infra") ++ part true "hr" 25 (says "real" "real")
#guard certify triSpec (9/10) 5 (goodChoose ++ probeHold 5) == [(.pick "real", 1)]
#guard certify triSpec (9/10) 5 (goodChoose ++ probeHold 15) == [(.pick "real", 1)]
#guard certify triSpec (9/10) 5 (goodChoose ++ part true "hf" 25 (says "flake" "flake") ++
  part true "hi" 25 (says "infra" "infra") ++ part true "hr" 25 (says "real" "real")) ==
  [(.pick "flake", 1), (.pick "infra", 1), (.pick "real", 1)]

/-! ## Held-out evaluation -/

/-- Held-out evaluation (the `oracle.eval` op). -/
def evalBy (s : Spec) (th : Thresholds) (rows : List Row) : Nat × Nat :=
  ((rows.filter fun r => !(decideOpt s th (.answer r.answer)).isEscalate).length,
   (rows.filter fun r => decideOpt s th (.answer r.answer) == .advise r.label).length)

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
