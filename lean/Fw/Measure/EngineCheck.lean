import Lean.Data.Json
import Fw.Measure.Tolerance
/-!
# Engine-model check: CI counts as a falsification test of the engine tables

The engine tables (`Fw.Engine.*`) predict, per (scenario, variant, stage), how a variant's count of
one type compares with the original's: zero, equal, at most, strictly less, or nothing (`Pred`). A CI
run gives the counts (`Series`: one count per frame) and the frozen class of each count type
(`Class`). This module decides, per prediction row, one of three verdicts:

* `pass` — the observation **certifies** the prediction for every unseen run within the class
  (`pass_sound`);
* `bug` — the observation **refutes** it for every unseen run within the class (`bug_sound`), so the
  model is wrong and is fixed from engine source, never by widening a tolerance;
* `unusable w` — nothing may be concluded, for a reason `w`: the type is quarantined (never used,
  `quarantined_unusable`), a strict `<o` is asked on a type that is not frame-exact, the observation
  is inside the class noise, there is no observation or no lane.

Classes: a `deterministic` type, and `stable(0, t)`, are *frame exact*: an unseen run equals the
observed one frame for frame (`exact`), so the prediction is decided on the observation itself
(`exact_pass_iff`). A `stable(k, t)` with `k ≥ 1` is compared by totals; one unseen run's total moves
by at most `t` (`totals_gap`), so a comparison of two series moves by at most `2t`, the margin of
`margin_sound`. A comparison between two arms uses the join of their classes (`Class.join`).
-/
namespace Fw.Measure.EngineCheck
open Fw.Measure

/-! ## Predictions and the claim they make -/

/-- The prediction kinds of one row, about a variant series `v` and the original's series `b`:
`zero` ("=0"), `eqO` ("=o"), `leO` ("≤o"), `ltO` ("<o"), `any`.
-/
inductive Pred where
  | zero
  | eqO
  | leO
  | ltO
  | any
deriving Repr, DecidableEq

/-- A prediction by its name in the rows; `none` for any other name. -/
def Pred.ofName : String → Option Pred
  | "=0" => some .zero
  | "=o" => some .eqO
  | "≤o" | "<=o" => some .leO
  | "<o" => some .ltO
  | "any" => some .any
  | _ => none

#guard Pred.ofName "≤o" == some .leO && Pred.ofName "<o" == some .ltO && Pred.ofName "=0" == some .zero
#guard Pred.ofName "x" == none && Pred.ofName "any" == some .any && Pred.ofName "<=o" == some .leO

/-- A class is *frame exact* when an unseen run equals the observed one in every frame: `deterministic`,
and `stable(0, t)` (no frame may differ).
-/
def exact : Class → Bool
  | .deterministic => true
  | .stable 0 _ => true
  | _ => false

/-- The total gap one unseen run can have from the observed one: `t` for `stable(k, t)`, `k ≥ 1`;
0 for the frame-exact classes (and for `quarantined`, where nothing is claimed).
-/
def slack : Class → Nat
  | .stable (_ + 1) t => t
  | _ => 0

#guard exact .deterministic && exact (.stable 0 5) && !exact (.stable 4 0) && !exact .quarantined
#guard slack (.stable 4 3) == 3 && slack (.stable 0 3) == 0 && slack .deterministic == 0

/-- **The claim** a prediction makes about an unseen pair of runs `(b', v')` of class `c`. On a frame
exact class it is per frame; otherwise it is about totals (for non-negative counts a zero total is a
zero in every frame, `total_zero_frames`).
-/
def Claim (p : Pred) (c : Class) (b' v' : Series) : Prop :=
  if exact c = true then
    match p with
    | .zero => ∀ i, valAt v' i = 0
    | .eqO => ∀ i, valAt v' i = valAt b' i
    | .leO => ∀ i, valAt v' i ≤ valAt b' i
    | .ltO => (∀ i, valAt v' i ≤ valAt b' i) ∧ total v' < total b'
    | .any => True
  else
    match p with
    | .zero => total v' = 0
    | .eqO => total v' = total b'
    | .leO => total v' ≤ total b'
    | .ltO => total v' < total b'
    | .any => True

/-! ## The decisions -/

/-- The observation certifies the claim for every unseen run. Frame-exact classes: the observation
itself satisfies the claim. Totals: `=0` and `=o` need no slack at all (`slack = 0`) and the observed
totals equal; `≤o` needs the margin of `margin_sound`; strict `<o` is never certified here.
-/
def passes (p : Pred) (c : Class) (b v : Series) : Bool :=
  if exact c = true then
    match p with
    | .zero => decide (diffFrames v [] = 0)
    | .eqO => decide (diffFrames v b = 0)
    | .leO => leFrames v b
    | .ltO => leFrames v b && decide (total v < total b)
    | .any => true
  else
    match p with
    | .zero => decide (total v = 0 ∧ slack c = 0)
    | .eqO => decide (total v = total b ∧ slack c = 0)
    | .leO => decide (total v + 2 * (slack c : Int) ≤ total b)
    | .ltO => false
    | .any => true

/-- The observation refutes the claim for every unseen run. Frame-exact classes: the observation does
not satisfy the claim. Totals: the observed total is further from the claim than one unseen run can move
it (`slack` per series).
-/
def fails (p : Pred) (c : Class) (b v : Series) : Bool :=
  if exact c = true then
    match p with
    | .zero => !passes .zero c b v
    | .eqO => !passes .eqO c b v
    | .leO => !passes .leO c b v
    | .ltO => !passes .ltO c b v
    | .any => false
  else
    match p with
    | .zero => decide ((slack c : Int) < (total v).natAbs)
    | .eqO => decide (2 * (slack c : Int) < (total v - total b).natAbs)
    | .leO => decide (total b + 2 * (slack c : Int) < total v)
    | .ltO => false
    | .any => false

/-- Why a row is unusable. -/
inductive Why where
  | quarantined
  | strictNeedsExact
  | inconclusive
  | noObs
  | noLane
deriving Repr, DecidableEq

/-- A verdict. -/
inductive Res where
  | pass
  | bug
  | unusable (w : Why)
deriving Repr, DecidableEq

/-- **The verdict** of one prediction on one observed pair `(b, v)` of class `c`. A quarantined class
is unusable before anything else; `any` passes (it claims nothing); a strict `<o` on a class that is not
frame exact is unusable; otherwise `passes` gives `pass`, `fails` gives `bug`, and the rest is
inconclusive.
-/
def verdict (p : Pred) (c : Class) (b v : Series) : Res :=
  if c = .quarantined then .unusable .quarantined
  else if p = .any then .pass
  else if p = .ltO ∧ exact c = false then .unusable .strictNeedsExact
  else if passes p c b v = true then .pass
  else if fails p c b v = true then .bug
  else .unusable .inconclusive

-- det must match exactly
#guard verdict .zero .deterministic [] [0, 0, 0] == .pass
#guard verdict .zero .deterministic [] [0, 1, 0] == .bug
#guard verdict .eqO .deterministic [1, 2] [1, 2, 0] == .pass
#guard verdict .eqO .deterministic [1, 2] [2, 1] == .bug
#guard verdict .leO .deterministic [3, 1] [2, 1] == .pass
#guard verdict .leO .deterministic [1, 0] [0, 1] == .bug
#guard verdict .ltO .deterministic [3, 1] [2, 1] == .pass
#guard verdict .ltO .deterministic [3, 1] [3, 1] == .bug
-- stable: margin 2t, strict only on exact classes
#guard verdict .leO (.stable 4 1) [10, 0] [0, 8] == .pass
#guard verdict .leO (.stable 4 1) [10, 0] [0, 9] == .unusable .inconclusive
#guard verdict .leO (.stable 4 1) [10, 0] [0, 13] == .bug
#guard verdict .zero (.stable 4 0) [] [0, 0] == .pass
#guard verdict .zero (.stable 4 0) [] [0, 1] == .bug
#guard verdict .zero (.stable 4 3) [] [0, 0] == .unusable .inconclusive
#guard verdict .eqO (.stable 4 0) [5, 0] [0, 5] == .pass
#guard verdict .ltO (.stable 4 0) [5] [1] == .unusable .strictNeedsExact
#guard verdict .ltO (.stable 0 3) [5] [1] == .pass
#guard verdict .zero .quarantined [] [0] == .unusable .quarantined
#guard verdict .any .deterministic [] [7] == .pass
#guard verdict .any .quarantined [] [7] == .unusable .quarantined

/-! ## Proofs -/

/-- A pair within a frame-exact class agrees in every frame. -/
theorem exact_frames {c : Class} {a a' : Series} (hc : exact c = true) (h : Within c a a') :
    ∀ i, valAt a i = valAt a' i := by
  rw [← diffFrames_zero_iff]
  cases c with
  | deterministic => exact h
  | stable k t =>
    cases k with
    | zero => exact Nat.le_zero.mp h.1
    | succ k => simp [exact] at hc
  | quarantined => simp [exact] at hc

/-- A pair within a stable class with a positive `k` has totals at most `slack` apart. -/
theorem totals_gap {c : Class} {a a' : Series} (hc : exact c = false) (hq : c ≠ .quarantined)
    (h : Within c a a') : (total a - total a').natAbs ≤ slack c := by
  cases c with
  | deterministic => simp [exact] at hc
  | stable k t =>
    cases k with
    | zero => simp [exact] at hc
    | succ k => exact h.2
  | quarantined => exact absurd rfl hq

/-- On a frame-exact class the claim of an unseen pair is the claim of the observed pair. -/
theorem claim_exact_iff {p : Pred} {c : Class} {b b' v v' : Series} (hc : exact c = true)
    (hb : Within c b b') (hv : Within c v v') : Claim p c b' v' ↔ Claim p c b v := by
  have eb := exact_frames hc hb
  have ev := exact_frames hc hv
  have tb : total b = total b' := total_eq_of_diff_zero b b' ((diffFrames_zero_iff b b').mpr eb)
  have tv : total v = total v' := total_eq_of_diff_zero v v' ((diffFrames_zero_iff v v').mpr ev)
  cases p <;> simp only [Claim, hc, ↓reduceIte, ← eb, ← ev, tb, tv]


/-- On a frame-exact class `passes` is the claim on the observation (deterministic types must match
exactly).
-/
theorem exact_pass_iff {p : Pred} {c : Class} {b v : Series} (hc : exact c = true) :
    passes p c b v = true ↔ Claim p c b v := by
  cases p <;> simp only [passes, Claim, hc, ↓reduceIte]
  · rw [decide_eq_true_eq, diffFrames_zero_iff]; simp [valAt_nil]
  · rw [decide_eq_true_eq, diffFrames_zero_iff]
  · exact leFrames_iff v b
  · rw [Bool.and_eq_true, decide_eq_true_eq, leFrames_iff]

/-- Quarantined types are never used: every prediction on a quarantined class is unusable, with no
verdict (the reason is `quarantined_unsound`: no margin makes them sound).
-/
theorem quarantined_unusable (p : Pred) (b v : Series) :
    verdict p .quarantined b v = .unusable .quarantined := by
  simp [verdict]

/-- Strict `<o` is only checked on frame-exact classes. -/
theorem ltO_stable_unusable (k t : Nat) (b v : Series) :
    verdict .ltO (.stable (k + 1) t) b v = .unusable .strictNeedsExact := by
  simp [verdict, exact]

/-- What a `pass` verdict says about the decision functions. -/
theorem verdict_pass {p : Pred} {c : Class} {b v : Series} (h : verdict p c b v = .pass) :
    c ≠ .quarantined ∧ (p = .any ∨ (¬ (p = .ltO ∧ exact c = false) ∧ passes p c b v = true)) := by
  unfold verdict at h
  by_cases h1 : c = .quarantined
  · simp [h1] at h
  by_cases h2 : p = .any
  · simp [h1, h2]
  by_cases h3 : p = .ltO ∧ exact c = false
  · simp [h1, h3] at h
  by_cases h4 : passes p c b v = true
  · simp [h1, h2, h3, h4]
  · by_cases h5 : fails p c b v = true <;> simp [h1, h2, h3, h4, h5] at h

/-- What a `bug` verdict says about the decision functions. -/
theorem verdict_bug {p : Pred} {c : Class} {b v : Series} (h : verdict p c b v = .bug) :
    c ≠ .quarantined ∧ p ≠ .any ∧ ¬ (p = .ltO ∧ exact c = false) ∧ passes p c b v = false ∧
      fails p c b v = true := by
  unfold verdict at h
  by_cases h1 : c = .quarantined
  · simp [h1] at h
  by_cases h2 : p = .any
  · simp [h1, h2] at h
  by_cases h3 : p = .ltO ∧ exact c = false
  · simp [h1, h3] at h
  by_cases h4 : passes p c b v = true
  · simp [h1, h2, h3, h4] at h
  · by_cases h5 : fails p c b v = true
    · simp_all
    · simp [h1, h2, h3, h4, h5] at h

/-- **A `pass` is sound.** If the verdict on the observed pair is `pass`, the class is not
quarantined and the prediction's claim holds for every unseen pair within the class of the observed one
(frame by frame for deterministic types, by totals with the margin for stable ones).
-/
theorem pass_sound {p : Pred} {c : Class} {b v : Series} (h : verdict p c b v = .pass) :
    c ≠ .quarantined ∧ ∀ b' v' : Series, Within c b b' → Within c v v' → Claim p c b' v' := by
  obtain ⟨hq, hpp⟩ := verdict_pass h
  refine ⟨hq, fun b' v' hb hv => ?_⟩
  rcases hpp with hp | ⟨_, hps⟩
  · subst hp; cases hx : exact c <;> simp [Claim, hx]
  by_cases hx : exact c = true
  · exact (claim_exact_iff hx hb hv).mpr ((exact_pass_iff hx).mp hps)
  · have hx' : exact c = false := by simpa using hx
    have gb := totals_gap hx' hq hb
    have gv := totals_gap hx' hq hv
    cases p <;> simp only [passes, Claim, hx', Bool.false_eq_true, ↓reduceIte, decide_eq_true_eq] at hps ⊢
    · omega
    · omega
    · omega

/-- **A `bug` is sound.** If the verdict on the observed pair is `bug`, the prediction's claim fails
for every unseen pair within the class of the observed one: the model is wrong, not the run.
-/
theorem bug_sound {p : Pred} {c : Class} {b v : Series} (h : verdict p c b v = .bug) :
    ∀ b' v' : Series, Within c b b' → Within c v v' → ¬ Claim p c b' v' := by
  intro b' v' hb hv
  obtain ⟨hq, hp, _, hnp, hf⟩ := verdict_bug h
  by_cases hx : exact c = true
  · rw [claim_exact_iff hx hb hv, ← exact_pass_iff hx]; simp [hnp]
  · have hx' : exact c = false := by simpa using hx
    have gb := totals_gap hx' hq hb
    have gv := totals_gap hx' hq hv
    cases p <;> simp only [fails, Claim, hx', Bool.false_eq_true, ↓reduceIte, decide_eq_true_eq] at hf ⊢
    · omega
    · omega
    · omega

/-- The stable `≤o` pass is the margin test of the screen: it implies `Σv + margin(k, t) ≤ Σb`,
the hypothesis of `margin_sound` (and `typeOk` of the class).
-/
theorem leO_pass_margin {k t : Nat} {b v : Series} (h : verdict .leO (.stable k t) b v = .pass) :
    total v + marginOf k t ≤ total b := by
  obtain ⟨_, hpp⟩ := verdict_pass h
  rcases hpp with hp | ⟨_, hps⟩
  · exact absurd hp (by simp)
  cases k with
  | zero =>
    simp only [passes, exact, ↓reduceIte] at hps
    have := total_le_of_leFrames v b hps
    simp [marginOf]; omega
  | succ k =>
    have hm : marginOf (k + 1) t = 2 * (t : Int) := by simp [marginOf]
    simp only [passes, exact, ↓reduceIte, Bool.false_eq_true, slack] at hps
    rw [hm]; exact of_decide_eq_true hps

/-- A series of non-negative counts has a non-negative total. -/
theorem total_nonneg : ∀ {v : Series}, (∀ x ∈ v, 0 ≤ x) → 0 ≤ total v
  | [], _ => by simp [total, sumBy]
  | x :: r, h => by
    have hx : 0 ≤ x := h x (by simp)
    have hr := total_nonneg (v := r) (fun y hy => h y (by simp [hy]))
    simp only [total, sumBy, id] at hr ⊢; omega

/-- With non-negative counts, a zero total is a zero in every frame. -/
theorem total_zero_frames : ∀ {v' : Series}, (∀ x ∈ v', 0 ≤ x) → total v' = 0 → ∀ i, valAt v' i = 0
  | [], _, _, i => valAt_nil i
  | x :: r, hn, h, i => by
    have hx : 0 ≤ x := hn x (by simp)
    have hn' : ∀ y ∈ r, 0 ≤ y := fun y hy => hn y (by simp [hy])
    have hr := total_nonneg hn'
    have h' : x + total r = 0 := by simpa [total, sumBy] using h
    have hr0 : total r = 0 := by omega
    cases i with
    | zero => rw [valAt_cons_zero]; omega
    | succ i => rw [valAt_cons_succ]; exact total_zero_frames hn' hr0 i

/-! ## Rows: runs, pairing and lanes -/

/-- The class a prediction is judged in: the variant's own class for `=0` and `any`; for a comparison with
the original, the join of the two arms' classes (so both unseen runs are within it).
-/
def judgeClass (p : Pred) (cV cB : Class) : Class :=
  match p with
  | .zero => cV
  | .any => cV
  | _ => cV.join cB

#guard judgeClass .zero (.stable 4 0) .deterministic == .stable 4 0
#guard judgeClass .leO (.stable 4 0) (.stable 2 3) == .stable 4 3
#guard judgeClass .leO .deterministic .deterministic == .deterministic

/-- A pair within the variant's arm class is within the judged class (and likewise for the original's). -/
theorem within_judge {p : Pred} {cV cB : Class} {a a' : Series} :
    (Within cV a a' → Within (judgeClass p cV cB) a a') ∧
    (p ≠ .zero → p ≠ .any → Within cB a a' → Within (judgeClass p cV cB) a a') := by
  constructor
  · intro h
    cases p <;> simp only [judgeClass]
    all_goals first | exact h | exact within_mono (Class.le_join_left cV cB) h
  · intro h1 h2 h
    cases p <;> simp only [judgeClass]
    · exact absurd rfl h1
    all_goals first | exact within_mono (Class.le_join_right cV cB) h | exact absurd rfl h2

/-- The observed pairs of a row: the `i`-th run of the variant with the `i`-th run of the original (the
first when the original has fewer runs; the empty series when it has none), as `(b, v)`.
-/
def pairs (vs bs : List Series) : List (Series × Series) :=
  (vs.zipIdx).map fun (v, i) => (bs.getD i (bs.headD []), v)

#guard pairs [[1], [2]] [[5]] == [([5], [1]), ([5], [2])]
#guard pairs [[1], [2]] [[5], [6]] == [([5], [1]), ([6], [2])]
#guard pairs [[1]] [] == [([], [1])]

/-- Combine the verdicts of the runs: `pass` only if there is a run and all pass; `bug` if any run is a
bug; otherwise the first run that is not a pass. No run is `unusable noObs`.
-/
def combine : List Res → Res
  | [] => .unusable .noObs
  | r :: rs =>
    if (r :: rs).all (· == Res.pass) then .pass
    else if (r :: rs).any (· == Res.bug) then .bug
    else ((r :: rs).find? (· != Res.pass)).getD (.unusable .inconclusive)

#guard combine [] == .unusable .noObs
#guard combine [.pass, .pass] == .pass
#guard combine [.pass, .bug, .unusable .inconclusive] == .bug
#guard combine [.pass, .unusable .inconclusive] == .unusable .inconclusive

/-- A combined `pass` is a pass of every run (and there is a run). -/
theorem combine_pass {rs : List Res} (h : combine rs = .pass) : rs ≠ [] ∧ ∀ r ∈ rs, r = .pass := by
  cases rs with
  | nil => simp [combine] at h
  | cons r rs =>
    refine ⟨by simp, ?_⟩
    by_cases hp : (r :: rs).all (· == Res.pass) = true
    · simpa using hp
    · by_cases hb : (r :: rs).any (· == Res.bug) = true
      · simp [combine, hp, hb] at h
      · simp only [combine, hp, hb, Bool.false_eq_true, ↓reduceIte] at h
        cases hf : (r :: rs).find? (· != Res.pass) with
        | none => simp [hf] at h
        | some x =>
          have hx := List.find?_some hf
          simp [hf] at h
          subst h; simp at hx

/-- A combined `bug` comes from a run that is a bug. -/
theorem combine_bug {rs : List Res} (h : combine rs = .bug) : ∃ r ∈ rs, r = .bug := by
  cases rs with
  | nil => simp [combine] at h
  | cons r rs =>
    by_cases hp : (r :: rs).all (· == Res.pass) = true
    · simp [combine, hp] at h
    · by_cases hb : (r :: rs).any (· == Res.bug) = true
      · obtain ⟨x, hx, hx2⟩ := List.any_eq_true.mp hb
        exact ⟨x, hx, by simpa using hx2⟩
      · simp only [combine, hp, hb, Bool.false_eq_true, ↓reduceIte] at h
        cases hf : (r :: rs).find? (· != Res.pass) with
        | none => simp [hf] at h
        | some x =>
          simp only [hf, Option.getD_some] at h
          exact ⟨x, List.mem_of_find?_eq_some hf, h⟩

/-- **The verdict of a row** from the arms' classes `cV`, `cB`, the variant's runs `vs` and the original's
runs `bs`: `unusable noObs` when a comparison has no original run, else the combined verdict of the
run pairs in the judged class.
-/
def rowRes (p : Pred) (cV cB : Class) (vs bs : List Series) : Res :=
  if (p = .eqO ∨ p = .leO ∨ p = .ltO) ∧ bs = [] then .unusable .noObs
  else combine ((pairs vs bs).map fun (b, v) => verdict p (judgeClass p cV cB) b v)

/-- **A row's `pass` is sound.** If a row passes, the judged class is not quarantined and, for every observed run
pair, every unseen pair within the judged class satisfies the claim.
-/
theorem rowRes_pass_sound {p : Pred} {cV cB : Class} {vs bs : List Series}
    (h : rowRes p cV cB vs bs = .pass) :
    judgeClass p cV cB ≠ .quarantined ∧ ∀ pr ∈ pairs vs bs, ∀ b' v' : Series,
      Within (judgeClass p cV cB) pr.1 b' → Within (judgeClass p cV cB) pr.2 v' →
        Claim p (judgeClass p cV cB) b' v' := by
  unfold rowRes at h
  by_cases h0 : (p = .eqO ∨ p = .leO ∨ p = .ltO) ∧ bs = []
  · simp [h0] at h
  simp only [h0, ite_false] at h
  obtain ⟨hne, hall⟩ := combine_pass h
  have hall' : ∀ pr ∈ pairs vs bs, verdict p (judgeClass p cV cB) pr.1 pr.2 = .pass := by
    intro pr hpr
    exact hall _ (List.mem_map.mpr ⟨pr, hpr, rfl⟩)
  have hex : ∃ pr, pr ∈ pairs vs bs := by
    cases hl : pairs vs bs with
    | nil => simp [hl] at hne
    | cons x xs => exact ⟨x, by simp⟩
  obtain ⟨pr0, hpr0⟩ := hex
  exact ⟨(pass_sound (hall' pr0 hpr0)).1, fun pr hpr b' v' hb hv => (pass_sound (hall' pr hpr)).2 b' v' hb hv⟩

/-- **A row's `bug` is sound.** If a row is a bug, some observed run pair refutes the claim for every
unseen pair within the judged class.
-/
theorem rowRes_bug_sound {p : Pred} {cV cB : Class} {vs bs : List Series}
    (h : rowRes p cV cB vs bs = .bug) :
    ∃ pr ∈ pairs vs bs, ∀ b' v' : Series,
      Within (judgeClass p cV cB) pr.1 b' → Within (judgeClass p cV cB) pr.2 v' →
        ¬ Claim p (judgeClass p cV cB) b' v' := by
  unfold rowRes at h
  by_cases h0 : (p = .eqO ∨ p = .leO ∨ p = .ltO) ∧ bs = []
  · simp [h0] at h
  simp only [h0, ite_false] at h
  obtain ⟨r, hr, hrb⟩ := combine_bug h
  obtain ⟨pr, hpr, rfl⟩ := List.mem_map.mp hr
  exact ⟨pr, hpr, bug_sound hrb⟩

/-- The lanes: only the Chromium lane is served; any other engine's rows are unusable until its lane
exists (the Simulator lane does not serve the rewrite yet).
-/
def laneRes (engine : String) (r : Res) : Res :=
  if engine = "chromium" then r else .unusable .noLane

/-- A webkit row is unusable (no lane yet), whatever the observation says. -/
theorem laneRes_webkit (r : Res) : laneRes "webkit" r = .unusable .noLane := by
  simp [laneRes]

/-- A chromium row keeps its verdict. -/
theorem laneRes_chromium (r : Res) : laneRes "chromium" r = r := by
  simp [laneRes]

end Fw.Measure.EngineCheck

/-! # The wire op `measure.engineCheck`

JSON glue (namespace `Fw.Wire.Measure.EngineCheck`, so the math view treats it as wire code). Registered by
`Fw.Wire.Measure.handle`. No decision lives here: classes are looked up, the verdicts are `rowRes` and
`laneRes`.

| op | request | reply |
|---|---|---|
| `measure.engineCheck` | `rows` [{engine, scenario, variant, stage, prediction (`=0`, `=o`, `<o`, `≤o`, `any`), countType, base? (default `original`)}], `classes` (the frozen `profiles`: {scenario: {arms: {arm: {types: {type: {class, k, t}}}}}}), `observed` [{scenario, variant, type, runs (each an array of per-frame integers)}] | `verdicts` [row fields + `verdict` (`pass`, `model-bug`, `unusable`), `reason`, `class` {variant, base}, `runs`, `totals` {variant, base}], `tally` {pass, modelBug, unusable} |

A variant reads the arm of its own name in `classes` if there is one, else `original` for `original`, else
`rewrite`. A type missing in one arm's table but listed in the other's reads deterministic there (the arm
never records it, as in `measure.arms`); missing in both, it reads quarantined.
-/
namespace Fw.Wire.Measure.EngineCheck
open Lean Fw.Measure Fw.Measure.EngineCheck

private def fld (j : Json) (k : String) : Except String Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error _ => .error s!"missing field {k}"

private def optF (j : Json) (k : String) : Option Json :=
  match j.getObjVal? k with
  | .ok .null => none
  | .ok v => some v
  | .error _ => none

private def strF (j : Json) (k : String) : Except String String := do
  match ← fld j k with
  | .str s => pure s
  | _ => throw s!"field {k}: expected a string"

private def arrF (j : Json) (k : String) : Except String (Array Json) := do
  match ← fld j k with
  | .arr a => pure a
  | _ => throw s!"field {k}: expected an array"

private def natF (j : Json) (k : String) : Except String Nat := do
  match (← fld j k).getNat? with
  | .ok n => pure n
  | .error _ => throw s!"field {k}: expected a non-negative integer"

private def intsOf (j : Json) : Except String Series :=
  match j with
  | .arr a => a.toList.mapM fun x => match x.getInt? with
    | .ok n => pure n
    | .error _ => throw "field runs: expected integer counts"
  | _ => throw "field runs: each run must be an array of integers"

/-- Decode `{class, k, t}`. -/
private def classOfJson (j : Json) : Except String Class := do
  match ← strF j "class" with
  | "deterministic" => pure .deterministic
  | "stable" => pure (.stable (← natF j "k") (← natF j "t"))
  | "quarantined" => pure .quarantined
  | c => throw s!"unknown class {c}"

/-- The arm a variant reads: its own name if the profile has such an arm, else `original` or `rewrite`. -/
def armKey (arms : Json) (variant : String) : String :=
  match optF arms variant with
  | some _ => variant
  | none => if variant == "original" then "original" else "rewrite"

/-- The frozen class of a type in a variant's arm; `none` when the profile, arm or type is not listed. -/
def classIn (classes : Json) (scenario variant ty : String) : Except String (Option Class) := do
  let some prof := optF classes scenario | pure none
  let some arms := optF prof "arms" | pure none
  let some arm := optF arms (armKey arms variant) | pure none
  let some tys := optF arm "types" | pure none
  let some e := optF tys ty | pure none
  some <$> classOfJson e

/-- The classes of the two sides: a side the arm never records reads deterministic when the other
side's arm lists the type; listed in neither, both read quarantined. -/
def sides : Option Class → Option Class → Class × Class
  | some v, some b => (v, b)
  | some v, none => (v, .deterministic)
  | none, some b => (.deterministic, b)
  | none, none => (.quarantined, .quarantined)

#guard sides none none == (.quarantined, .quarantined) && sides none (some (.stable 1 2)) == (.deterministic, .stable 1 2)

private def className : Class → String
  | .deterministic => "deterministic"
  | .stable k t => s!"stable(k={k}, t={t})"
  | .quarantined => "quarantined"

private def whyText : Why → String
  | .quarantined => "quarantined type: never used"
  | .strictNeedsExact => "strict <o is only checked on frame-exact classes (deterministic, stable with k = 0)"
  | .inconclusive => "inside the class noise: neither certified nor refuted"
  | .noObs => "no observation for the variant or its original"
  | .noLane => "no lane yet"

private def resName : Res → String
  | .pass => "pass"
  | .bug => "model-bug"
  | .unusable _ => "unusable"

private def resReason (p : Pred) (r : Res) : String :=
  match r with
  | .pass => if p == .any then "any: no claim" else "certified for every run within the class"
  | .bug => "refuted for every run within the class: the model is wrong"
  | .unusable w => whyText w

private structure Obs where
  scenario : String
  variant : String
  ty : String
  runs : List Series

private def obsOf (j : Json) : Except String Obs := do
  let rs ← (← arrF j "runs").toList.mapM intsOf
  pure { scenario := ← strF j "scenario", variant := ← strF j "variant", ty := ← strF j "type", runs := rs }

private def findObs (os : List Obs) (scenario variant ty : String) : List Series :=
  ((os.find? fun o => o.scenario == scenario && o.variant == variant && o.ty == ty).map (·.runs)).getD []

private def totalsJson (rs : List Series) : Json := .arr (rs.map fun r => Json.num (total r)).toArray

/-- One row's verdict object. -/
private def rowJson (classes : Json) (os : List Obs) (j : Json) : Except String Json := do
  let engine ← strF j "engine"
  let scenario ← strF j "scenario"
  let variant ← strF j "variant"
  let stage ← strF j "stage"
  let ty ← strF j "countType"
  let pname ← strF j "prediction"
  let base := match optF j "base" with | some (.str s) => s | _ => "original"
  let some p := Pred.ofName pname | throw s!"unknown prediction {pname} (=0, =o, <o, ≤o, any)"
  let (cV, cB) := sides (← classIn classes scenario variant ty) (← classIn classes scenario base ty)
  let vs := findObs os scenario variant ty
  let bs := findObs os scenario base ty
  let r := laneRes engine (rowRes p cV cB vs bs)
  pure (Json.mkObj [("engine", .str engine), ("scenario", .str scenario), ("variant", .str variant),
    ("stage", .str stage), ("countType", .str ty), ("prediction", .str pname), ("base", .str base),
    ("verdict", .str (resName r)), ("reason", .str (resReason p r)),
    ("class", Json.mkObj [("variant", .str (className cV)), ("base", .str (className cB))]),
    ("runs", Json.mkObj [("variant", Json.num vs.length), ("base", Json.num bs.length)]),
    ("totals", Json.mkObj [("variant", totalsJson vs), ("base", totalsJson bs)])])

/-- `measure.engineCheck`: `{rows, classes, observed}` → `{verdicts, tally}`. An error when a row, an
observation or a class does not decode, or a prediction is not one of `=0`, `=o`, `<o`, `≤o`, `any`. -/
def op (req : Json) : Except String (List (String × Json)) := do
  let classes ← fld req "classes"
  let os ← (← arrF req "observed").toList.mapM obsOf
  let vs ← (← arrF req "rows").toList.mapM (rowJson classes os)
  let n (s : String) : Nat := (vs.filter fun v => (optF v "verdict") == some (.str s)).length
  pure [("verdicts", .arr vs.toArray),
        ("tally", Json.mkObj [("pass", Json.num (n "pass")), ("modelBug", Json.num (n "model-bug")),
          ("unusable", Json.num (n "unusable"))])]

end Fw.Wire.Measure.EngineCheck
