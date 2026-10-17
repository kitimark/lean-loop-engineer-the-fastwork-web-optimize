import Fw.Measure.Classes
/-!
# Which count types may enter the dominance screen, and with what tolerance

The screen (`Fw.Screen`, class W) concludes "no more work" from one baseline run `b` and one variant
run `v`. Another run of the same page may differ: run-to-run variation is what the determinism
classes bound. The modelling premise (L3, not provable here) is that an unseen run `b'` of the
baseline is within the type's class of the observed `b`, and likewise `v'` of `v`. Under that
premise:

* **deterministic** types (`b' = b` frame for frame) enter frame by frame: `v ≤ b` in every frame
  carries over to `v' ≤ b'` in every frame (`det_frames_sound`).
* **stable(k, t)** types enter by their totals with the margin `2t` (or 0 when `k = 0`): if
  `Σv + 2t ≤ Σb` then `Σv' ≤ Σb'` (`margin_sound`), and no smaller margin is sound, even for
  non-negative counts (`margin_exact`). Frame by frame they can not enter: up to `k` frames may
  move (`stable_frames_unsound`).
* **quarantined** types can not enter with any margin (`quarantined_unsound`).

`noMoreWork` is the screen with these rules, and `noMoreWork_sound` / `noMoreWork_cost` state what
it guarantees.
-/
namespace Fw.Measure

/-! ## Frame-by-frame order with zero padding -/

/-- One series is at most another in every frame (the shorter padded with zeros).

$$\operatorname{leF}(v, b) = \mathrm{true} \iff \forall i:\ v[i] \le b[i]$$
-/
def leFrames : Series → Series → Bool
  | [], [] => true
  | x :: xs, [] => decide (x ≤ 0) && leFrames xs []
  | [], y :: ys => decide (0 ≤ y) && leFrames [] ys
  | x :: xs, y :: ys => decide (x ≤ y) && leFrames xs ys

#guard leFrames [1, 2] [1, 3, 0]
#guard !leFrames [1, 2, 1] [1, 3]

/-- The padded value of a non-empty series at index 0.

$$\forall x \in \mathbb{Z}, r \in \mathbb{Z}^{*}:\ (x :: r)[0] = x$$
-/
theorem valAt_cons_zero (x : Int) (r : Series) : valAt (x :: r) 0 = x := rfl

/-- The padded value at a successor index.

$$\forall x \in \mathbb{Z}, r \in \mathbb{Z}^{*}, i \in \mathbb{N}:\ (x :: r)[i + 1] = r[i]$$
-/
theorem valAt_cons_succ (x : Int) (r : Series) (i : Nat) : valAt (x :: r) (i + 1) = valAt r i := rfl

/-- The padded value of the empty series.

$$\forall i \in \mathbb{N}:\ [\,][i] = 0$$
-/
theorem valAt_nil (i : Nat) : valAt [] i = 0 := by simp [valAt]

/-- Pointwise statements about a cons split into index 0 and the rest.

$$\forall P : \mathbb{N} \to \mathbf{Prop}:\ (\forall i:\ P(i)) \iff P(0) \land \forall i:\ P(i + 1)$$
-/
theorem forall_nat_split (P : Nat → Prop) : (∀ i, P i) ↔ P 0 ∧ ∀ i, P (i + 1) :=
  ⟨fun h => ⟨h 0, fun i => h (i + 1)⟩, fun ⟨h0, hs⟩ i => by cases i with | zero => exact h0 | succ i => exact hs i⟩

/-- `leFrames` is the padded frame-by-frame order.

$$\forall v, b:\ \operatorname{leF}(v, b) = \mathrm{true} \iff \forall i:\ v[i] \le b[i]$$
-/
theorem leFrames_iff : ∀ v b : Series, leFrames v b = true ↔ ∀ i, valAt v i ≤ valAt b i
  | [], [] => by simp [leFrames, valAt_nil]
  | x :: xs, [] => by
    rw [forall_nat_split]; simp only [leFrames, Bool.and_eq_true, decide_eq_true_eq, leFrames_iff xs []]
    simp [valAt_cons_zero, valAt_cons_succ, valAt_nil]
  | [], y :: ys => by
    rw [forall_nat_split]; simp only [leFrames, Bool.and_eq_true, decide_eq_true_eq, leFrames_iff [] ys]
    simp [valAt_cons_zero, valAt_cons_succ, valAt_nil]
  | x :: xs, y :: ys => by
    rw [forall_nat_split]; simp only [leFrames, Bool.and_eq_true, decide_eq_true_eq, leFrames_iff xs ys]
    simp [valAt_cons_zero, valAt_cons_succ]

/-- No differing frame is padded equality.

$$\forall a, b:\ \operatorname{diff}(a, b) = 0 \iff \forall i:\ a[i] = b[i]$$
-/
theorem diffFrames_zero_iff : ∀ a b : Series, diffFrames a b = 0 ↔ ∀ i, valAt a i = valAt b i
  | [], [] => by simp [diffFrames, valAt_nil]
  | x :: xs, [] => by
    have ih := diffFrames_zero_iff xs []
    rw [forall_nat_split]
    simp only [valAt_cons_zero, valAt_cons_succ, valAt_nil] at ih ⊢
    rw [← ih]; simp only [diffFrames]
    by_cases h : x = 0 <;> simp [h]
  | [], y :: ys => by
    have ih := diffFrames_zero_iff [] ys
    rw [forall_nat_split]
    simp only [valAt_cons_zero, valAt_cons_succ, valAt_nil] at ih ⊢
    rw [← ih]; simp only [diffFrames]
    by_cases h : 0 = y <;> simp [h]
  | x :: xs, y :: ys => by
    have ih := diffFrames_zero_iff xs ys
    rw [forall_nat_split]
    simp only [valAt_cons_zero, valAt_cons_succ] at ih ⊢
    rw [← ih]; simp only [diffFrames]
    by_cases h : x = y <;> simp [h]

/-- Frame-by-frame at most implies total at most.

$$\forall v, b:\ \operatorname{leF}(v, b) = \mathrm{true} \;\Rightarrow\; \Sigma v \le \Sigma b$$
-/
theorem total_le_of_leFrames : ∀ v b : Series, leFrames v b = true → total v ≤ total b
  | [], [], _ => Int.le_refl 0
  | x :: xs, [], h => by
    simp only [leFrames, Bool.and_eq_true, decide_eq_true_eq] at h
    have := total_le_of_leFrames xs [] h.2
    simp only [total, sumBy] at this ⊢; simp only [id]; omega
  | [], y :: ys, h => by
    simp only [leFrames, Bool.and_eq_true, decide_eq_true_eq] at h
    have := total_le_of_leFrames [] ys h.2
    simp only [total, sumBy] at this ⊢; simp only [id]; omega
  | x :: xs, y :: ys, h => by
    simp only [leFrames, Bool.and_eq_true, decide_eq_true_eq] at h
    have := total_le_of_leFrames xs ys h.2
    simp only [total, sumBy] at this ⊢; simp only [id]; omega

/-! ## Deterministic types: frame by frame -/

/-- **Deterministic types keep frame-by-frame dominance.** If the variant is at most the baseline
in every frame, and the unseen runs `b'`, `v'` have no frame differing from `b`, `v`, then `v'` is
at most `b'` in every frame.

$$\forall b, b', v, v':\ \operatorname{leF}(v, b) \ \land\ \operatorname{diff}(b, b') = 0 \ \land\ \operatorname{diff}(v, v') = 0 \;\Rightarrow\; \operatorname{leF}(v', b')$$
-/
theorem det_frames_sound {b b' v v' : Series} (h : leFrames v b = true)
    (hb : diffFrames b b' = 0) (hv : diffFrames v v' = 0) : leFrames v' b' = true := by
  rw [leFrames_iff] at h ⊢
  rw [diffFrames_zero_iff] at hb hv
  intro i; rw [← hb i, ← hv i]; exact h i

/-- **Stable types can not enter frame by frame.** With two frames allowed to differ (`k ≥ 2`) and
no total gap, frame-by-frame dominance of the observed runs does not carry over (a unit of work moved one
frame earlier in the variant's unseen run).

$$\forall k \ge 2:\ \exists b, b', v, v' \in \mathbb{N}^{*}:\ \operatorname{leF}(v, b) \ \land\ \operatorname{Within}(\mathrm{stable}(k, 0), b, b') \ \land\ \operatorname{Within}(\mathrm{stable}(k, 0), v, v') \ \land\ \neg\operatorname{leF}(v', b')$$
-/
theorem stable_frames_unsound (k : Nat) (hk : 2 ≤ k) :
    ∃ b b' v v' : Series, (∀ x ∈ b ++ b' ++ v ++ v', 0 ≤ x) ∧ leFrames v b = true ∧
      Within (.stable k 0) b b' ∧ Within (.stable k 0) v v' ∧ leFrames v' b' = false := by
  refine ⟨[0, 1], [0, 1], [0, 1], [1, 0], ?_, by simp [leFrames], ?_, ?_, by simp [leFrames]⟩
  · intro x hx; simp at hx; omega
  · simp [Within, diffFrames, totalGap, total, sumBy]
  · simp [Within, diffFrames, totalGap, total, sumBy]; omega

/-! ## Stable types: totals with a margin -/

/-- The total margin a stable(k, t) type needs: 0 when no frame may differ, else twice the total
gap.

$$\operatorname{margin}(k, t) = \begin{cases} 0 & k = 0 \\ 2t & k \ge 1 \end{cases}$$
-/
def marginOf (k t : Nat) : Int := if k = 0 then 0 else 2 * (t : Int)

/-- **The margin is sound.** If the variant's observed total plus the margin is at most the
baseline's, then every unseen pair within stable(k, t) of the observed runs has the variant's total
at most the baseline's (for any integer counts).

$$\forall k, t \in \mathbb{N},\ b, b', v, v' \in \mathbb{Z}^{*}:\ \operatorname{Within}(\mathrm{stable}(k, t), b, b') \land \operatorname{Within}(\mathrm{stable}(k, t), v, v') \land \Sigma v + \operatorname{margin}(k, t) \le \Sigma b \;\Rightarrow\; \Sigma v' \le \Sigma b'$$
-/
theorem margin_sound {k t : Nat} {b b' v v' : Series} (hb : Within (.stable k t) b b')
    (hv : Within (.stable k t) v v') (h : total v + marginOf k t ≤ total b) : total v' ≤ total b' := by
  simp only [Within, totalGap] at hb hv
  simp only [marginOf] at h
  by_cases hk : k = 0
  · subst hk
    have e1 := total_eq_of_diff_zero b b' (by omega)
    have e2 := total_eq_of_diff_zero v v' (by omega)
    simp at h; omega
  · simp [hk] at h; omega

/-- A margin is sound for stable(k, t) on non-negative counts when it carries the observed total
order to every unseen pair of runs within the class.

$$\operatorname{Sound}(k, t, m) \iff \forall b, b', v, v' \in \mathbb{N}^{*}:\ \operatorname{Within}(\mathrm{stable}(k, t), b, b') \land \operatorname{Within}(\mathrm{stable}(k, t), v, v') \land \Sigma v + m \le \Sigma b \Rightarrow \Sigma v' \le \Sigma b'$$
-/
def SoundMargin (k t : Nat) (m : Int) : Prop :=
  ∀ b b' v v' : Series, (∀ x ∈ b ++ b' ++ v ++ v', 0 ≤ x) →
    Within (.stable k t) b b' → Within (.stable k t) v v' → total v + m ≤ total b → total v' ≤ total b'

/-- **The margin is exact.** A margin `m` is sound for stable(k, t) types, even when only
non-negative counts are considered, if and only if it is at least `margin(k, t)` (0 for k = 0,
2t otherwise).

$$\forall k, t \in \mathbb{N},\ m \in \mathbb{Z}:\ \operatorname{Sound}(k, t, m) \iff \operatorname{margin}(k, t) \le m$$
-/
theorem margin_exact (k t : Nat) (m : Int) : SoundMargin k t m ↔ marginOf k t ≤ m := by
  constructor
  · intro hs
    apply Classical.byContradiction; intro hlt
    simp only [marginOf] at hlt
    by_cases hk : k = 0
    · subst hk
      simp at hlt
      have := hs [0] [0] [-m] [-m] (by intro x hx; simp at hx; omega)
        (by simp [Within, diffFrames, totalGap])
        (by simp [Within, diffFrames, totalGap])
        (by simp [total, sumBy]; omega)
      simp [total, sumBy] at this; omega
    · simp [hk] at hlt
      have hk1 : 1 ≤ k := by omega
      let C : Int := (m.natAbs : Int) + t
      have := hs [C + t] [C] [C + t - m] [C + 2 * t - m]
        (by intro x hx; simp at hx; omega)
        (by simp only [Within, diffFrames, totalGap, total, sumBy, id]; constructor
            · split <;> omega
            · omega)
        (by simp only [Within, diffFrames, totalGap, total, sumBy, id]; constructor
            · split <;> omega
            · omega)
        (by simp [total, sumBy])
      simp [total, sumBy] at this; omega
  · intro hm b b' v v' _ hb hv h
    apply margin_sound hb hv
    by_cases hk : k = 0
    · subst hk
      simp only [Within] at hb hv
      simp [marginOf] at hm ⊢
      have := total_eq_of_diff_zero b b' (by omega)
      omega
    · omega

/-- **Quarantined types can not enter.** For every margin there are runs, with non-negative
counts, whose observed totals clear the margin and whose unseen totals are in the other order.

$$\forall m \in \mathbb{Z}:\ \exists b, b', v, v' \in \mathbb{N}^{*}:\ \operatorname{Within}(\mathrm{quar}, b, b') \land \operatorname{Within}(\mathrm{quar}, v, v') \land \Sigma v + m \le \Sigma b \land \Sigma v' > \Sigma b'$$
-/
theorem quarantined_unsound (m : Int) :
    ∃ b b' v v' : Series, (∀ x ∈ b ++ b' ++ v ++ v', 0 ≤ x) ∧ Within .quarantined b b' ∧
      Within .quarantined v v' ∧ total v + m ≤ total b ∧ total b' < total v' := by
  refine ⟨[m.natAbs], [0], [0], [1], ?_, trivial, trivial, ?_, ?_⟩
  · intro x hx; simp at hx; omega
  · simp [total, sumBy]; omega
  · simp [total, sumBy]

/-! ## The screen with classes -/

/-- One count type's input to the screen: its class (joined over both arms' runs) and one observed
series per arm.

$$\mathrm{Obs} = \mathrm{Class} \times \mathbb{Z}^{*} \times \mathbb{Z}^{*}$$
-/
structure TypeObs where
  cls : Class
  base : Series
  var : Series
deriving Repr, DecidableEq

/-- The per-type test: deterministic types frame by frame, stable types by totals with the margin,
quarantined types are left out.

$$\operatorname{ok}(c, b, v) = \begin{cases} \operatorname{leF}(v, b) & c = \mathrm{det} \\ \Sigma v + \operatorname{margin}(k, t) \le \Sigma b & c = \mathrm{stable}(k, t) \\ \mathrm{true} & c = \mathrm{quar} \end{cases}$$
-/
def typeOk : Class → Series → Series → Bool
  | .deterministic, b, v => leFrames v b
  | .stable k t, b, v => decide (total v + marginOf k t ≤ total b)
  | .quarantined, _, _ => true

/-- **The class-aware screen**: no more work when every non-quarantined type passes its test.

$$\operatorname{noMoreWork}(O) = \bigwedge_{o \in O} \operatorname{ok}(o.\mathrm{cls}, o.\mathrm{base}, o.\mathrm{var})$$
-/
def noMoreWork (os : List TypeObs) : Bool := os.all fun o => typeOk o.cls o.base o.var

#guard noMoreWork [⟨.deterministic, [3, 1], [2, 1]⟩, ⟨.stable 2 1, [10, 0], [0, 8]⟩, ⟨.quarantined, [0], [99]⟩]
#guard !noMoreWork [⟨.stable 2 1, [10, 0], [0, 9]⟩]
#guard !noMoreWork [⟨.deterministic, [1, 0], [0, 1]⟩]
#guard noMoreWork [⟨.stable 0 5, [3], [3]⟩]

/-- What the screen promises about unseen runs of one type: frame by frame for deterministic
types, on totals for stable types, nothing for quarantined ones.

$$\operatorname{Promise}(c, b', v') \iff \begin{cases} \forall i:\ v'[i] \le b'[i] & c = \mathrm{det} \\ \Sigma v' \le \Sigma b' & c = \mathrm{stable}(k, t) \\ \top & c = \mathrm{quar} \end{cases}$$
-/
def Promise : Class → Series → Series → Prop
  | .deterministic, b', v' => ∀ i, valAt v' i ≤ valAt b' i
  | .stable _ _, b', v' => total v' ≤ total b'
  | .quarantined, _, _ => True

/-- One type's test is sound under the class premise.

$$\forall c, b, b', v, v':\ \operatorname{ok}(c, b, v) \land \operatorname{Within}(c, b, b') \land \operatorname{Within}(c, v, v') \;\Rightarrow\; \operatorname{Promise}(c, b', v')$$
-/
theorem typeOk_sound {c : Class} {b b' v v' : Series} (h : typeOk c b v = true)
    (hb : Within c b b') (hv : Within c v v') : Promise c b' v' := by
  cases c with
  | deterministic =>
    simp only [Promise]; rw [← leFrames_iff]
    exact det_frames_sound h hb hv
  | stable k t =>
    simp only [typeOk, decide_eq_true_eq] at h
    exact margin_sound hb hv h
  | quarantined => trivial

/-- **Soundness of the class-aware screen.** If it says "no more work", then for every type and
all unseen runs within the type's class of the observed ones, the variant does no more work than
the baseline: in every frame for deterministic types, in total for stable types.

$$\forall O:\ \operatorname{noMoreWork}(O) \;\Rightarrow\; \forall o \in O,\ \forall b', v':\ \operatorname{Within}(o.\mathrm{cls}, o.\mathrm{base}, b') \land \operatorname{Within}(o.\mathrm{cls}, o.\mathrm{var}, v') \Rightarrow \operatorname{Promise}(o.\mathrm{cls}, b', v')$$
-/
theorem noMoreWork_sound {os : List TypeObs} (h : noMoreWork os = true) :
    ∀ o ∈ os, ∀ b' v' : Series, Within o.cls o.base b' → Within o.cls o.var v' → Promise o.cls b' v' := by
  intro o ho b' v' hb hv
  simp only [noMoreWork, List.all_eq_true] at h
  exact typeOk_sound (h o ho) hb hv

/-- A promise for a non-quarantined type bounds the total.

$$\forall c, b', v':\ c \ne \mathrm{quar} \land \operatorname{Promise}(c, b', v') \;\Rightarrow\; \Sigma v' \le \Sigma b'$$
-/
theorem promise_total {c : Class} {b' v' : Series} (hc : c ≠ .quarantined) (h : Promise c b' v') :
    total v' ≤ total b' := by
  cases c with
  | deterministic =>
    simp only [Promise] at h
    exact total_le_of_leFrames v' b' ((leFrames_iff v' b').mpr h)
  | stable _ _ => exact h
  | quarantined => exact absurd rfl hc

/-- One screened type with its unseen runs and its cost coefficient.

$$\mathrm{Entry} = \mathrm{Obs} \times \mathbb{Z}^{*} \times \mathbb{Z}^{*} \times \mathbb{Q}$$
-/
structure Entry where
  obs : TypeObs
  base' : Series
  var' : Series
  coef : Rat

/-- The linear run cost of the screened (non-quarantined) types of one arm.

$$\operatorname{cost}(E, \mathrm{sel}) = \sum_{e \in E,\ e.\mathrm{cls} \ne \mathrm{quar}} e.\mathrm{coef} \cdot \Sigma\,\mathrm{sel}(e)$$
-/
def runCost (sel : Entry → Series) : List Entry → Rat
  | [] => 0
  | e :: es => (if e.obs.cls = .quarantined then 0 else e.coef * ((total (sel e) : Int) : Rat)) + runCost sel es

/-- **No more work in run cost.** If the class-aware screen says "no more work", then under every
non-negative cost coefficients the screened types' linear run cost of any unseen variant run is at
most that of any unseen baseline run (each within its type's class of the observed runs).

$$\forall E:\ \operatorname{noMoreWork}([e.\mathrm{obs}]_{e \in E}) \land \forall e \in E:\ \big(0 \le e.\mathrm{coef} \land \operatorname{Within}(e.\mathrm{cls}, e.\mathrm{base}, e.b') \land \operatorname{Within}(e.\mathrm{cls}, e.\mathrm{var}, e.v')\big) \;\Rightarrow\; \operatorname{cost}(E, e \mapsto e.v') \le \operatorname{cost}(E, e \mapsto e.b')$$
-/
theorem noMoreWork_cost (es : List Entry) (h : noMoreWork (es.map (·.obs)) = true)
    (hw : ∀ e ∈ es, 0 ≤ e.coef) (hb : ∀ e ∈ es, Within e.obs.cls e.obs.base e.base')
    (hv : ∀ e ∈ es, Within e.obs.cls e.obs.var e.var') :
    runCost (·.var') es ≤ runCost (·.base') es := by
  induction es with
  | nil => exact Rat.le_refl
  | cons e es ih =>
    simp only [noMoreWork, List.map_cons, List.all_cons, Bool.and_eq_true] at h
    have ih' := ih (by simpa [noMoreWork] using h.2) (fun x hx => hw x (by simp [hx]))
      (fun x hx => hb x (by simp [hx])) (fun x hx => hv x (by simp [hx]))
    simp only [runCost]
    have hhead : (if e.obs.cls = .quarantined then 0 else e.coef * ((total e.var' : Int) : Rat)) ≤
        (if e.obs.cls = .quarantined then 0 else e.coef * ((total e.base' : Int) : Rat)) := by
      split
      · exact Rat.le_refl
      · rename_i hq
        have hp := typeOk_sound h.1 (hb e (by simp)) (hv e (by simp))
        exact Rat.mul_le_mul_of_nonneg_left (Rat.intCast_le_intCast.mpr (promise_total hq hp)) (hw e (by simp))
    exact Rat.le_trans (Rat.add_le_add_right.mpr hhead) (Rat.add_le_add_left.mpr ih')

end Fw.Measure
