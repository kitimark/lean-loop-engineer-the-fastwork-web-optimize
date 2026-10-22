import Lean.Data.Json
/-!
# Fw.Gate.Smooth: motion continuity along one push and a bad-frame verdict (task smoothness-probe)

Advisory evidence only; no gate reads it. Values are integers (property value x 1000, time in tenths of ms).
-/

namespace Fw.Gate.Smooth

/-- One sampled frame of a property: the time, the ideal value the curve wants there, and the value shown. -/
structure Frame where
  t : Nat
  want : Int
  shown : Int
deriving Repr, BEq

/-- One frame-to-frame step: the time of the later frame, the ideal step `e` and the shown step `s`. -/
structure Step where
  t : Nat
  e : Int
  s : Int
deriving Repr, BEq

/-- The steps between consecutive frames. -/
def steps : List Frame → List Step
  | a :: b :: rest => ⟨b.t, b.want - a.want, b.shown - a.shown⟩ :: steps (b :: rest)
  | _ => []

/-- The ideal value at driver `d` on the straight line from `(d0, v0)` to `(d1, v1)`, rounded down. -/
def lerp (d0 v0 d1 v1 d : Int) : Int :=
  if d0 = d1 then v1
  else
    let den : Int := (d1 - d0).natAbs
    let sg : Int := if d0 < d1 then 1 else -1
    v0 + sg * (v1 - v0) * (d - d0) / den

/-- Stall threshold: the ideal moves at least this many per mille of the travel in the step. -/
def stallPm : Nat := 5
/-- Stall threshold: the shown step is under `1 / stallDiv` of the ideal step. -/
def stallDiv : Nat := 4
/-- Jump threshold: the shown step exceeds the ideal step by more than this many per mille of the travel. -/
def jumpPm : Nat := 50
/-- Reversal threshold: the shown step goes against the ideal by at least this many per mille of the travel. -/
def reversePm : Nat := 10

/-- The total travel of the ideal curve over the steps. -/
def travel (ps : List Step) : Nat := (ps.map Step.e).sum.natAbs

/-- The ideal moved by at least `stallPm` per mille of the travel `T` and the shown value moved under a quarter of that. -/
def Step.stalled (T : Nat) (p : Step) : Bool :=
  decide (stallPm * T ≤ 1000 * p.e.natAbs) && decide (stallDiv * p.s.natAbs < p.e.natAbs)

/-- The shown step exceeds the ideal step by more than `jumpPm` per mille of the travel `T`. -/
def Step.jumped (T : Nat) (p : Step) : Bool :=
  decide ((jumpPm : Int) * T < 1000 * ((p.s.natAbs : Int) - p.e.natAbs))

/-- The shown step goes against the ideal step by at least `reversePm` per mille of the travel `T`. -/
def Step.reversed (T : Nat) (p : Step) : Bool :=
  decide (p.s * p.e < 0) && decide (reversePm * T ≤ 1000 * p.s.natAbs)

/-- Steps where the shown value lags the ideal. -/
def stalls (ps : List Step) : Nat := ps.countP (Step.stalled (travel ps))
/-- Steps where the shown value leaps past the ideal. -/
def jumps (ps : List Step) : Nat := ps.countP (Step.jumped (travel ps))
/-- Steps where the shown value goes the other way. -/
def reversals (ps : List Step) : Nat := ps.countP (Step.reversed (travel ps))

/-- The largest shown step. -/
def peakShown (ps : List Step) : Nat := (ps.map fun p => p.s.natAbs).foldl max 0
/-- The largest ideal step. -/
def peakIdeal (ps : List Step) : Nat := (ps.map fun p => p.e.natAbs).foldl max 0
/-- Largest shown step over largest ideal step, per mille (1000 on the curve); 0 when the ideal never moves. -/
def peakRatio (ps : List Step) : Nat := if peakIdeal ps = 0 then 0 else 1000 * peakShown ps / peakIdeal ps

/-- The leading steps in which the ideal stands still. -/
def idleFront : List Step → List Step
  | p :: rest => if p.e == 0 then p :: idleFront rest else []
  | [] => []

/-- The trailing steps in which the ideal stands still. -/
def idleRun (ps : List Step) : List Step := (idleFront ps.reverse).reverse

/-- Steps after the ideal arrived in which the shown value still moves. -/
def tailSteps (ps : List Step) : Nat := (idleRun ps).countP fun p => p.s != 0

/-- Time from the ideal's arrival to the last shown move after it, tenths of ms. -/
def tailT (ps : List Step) : Nat :=
  let idle := idleRun ps
  let arrive := ((ps.take (ps.length - idle.length)).getLast?.map Step.t).getD 0
  let last := ((idle.filter fun p => p.s != 0).getLast?.map Step.t).getD arrive
  last - arrive

/-- The metrics of one push of one scalar property. -/
structure Metrics where
  n : Nat
  travel : Nat
  stalls : Nat
  jumps : Nat
  reversals : Nat
  peakPm : Nat
  peakRatio : Nat
  tailSteps : Nat
  tailT : Nat
deriving Repr, BEq

/-- The shown peak step per mille of the travel; 0 when the ideal does not travel. -/
def peakPm (ps : List Step) : Nat := if travel ps = 0 then 0 else 1000 * peakShown ps / travel ps

/-- All metrics of a list of steps. -/
def metricsOf (ps : List Step) : Metrics :=
  ⟨ps.length, travel ps, stalls ps, jumps ps, reversals ps, peakPm ps, peakRatio ps, tailSteps ps, tailT ps⟩

/-- All metrics of a list of frames. -/
def metrics (fs : List Frame) : Metrics := metricsOf (steps fs)

/-- The property has no motion to judge: its ideal does not travel. -/
def Metrics.flat (m : Metrics) : Bool := m.travel == 0

/-- Some metric found a defect. -/
def Metrics.flagged (m : Metrics) : Bool := 0 < m.stalls || 0 < m.jumps || 0 < m.reversals || 0 < m.tailSteps

/-- The worse of two components of one property: counts and peaks take the larger, the travel too. -/
def Metrics.worst (a b : Metrics) : Metrics :=
  ⟨max a.n b.n, max a.travel b.travel, max a.stalls b.stalls, max a.jumps b.jumps, max a.reversals b.reversals,
    max a.peakPm b.peakPm, max a.peakRatio b.peakRatio, max a.tailSteps b.tailSteps, max a.tailT b.tailT⟩

/-- The `p`-th smallest by nearest rank of `xs` (none when empty); `p` from 1 to 100. -/
def quantile (xs : List Nat) (p : Nat) : Option Nat :=
  let s := xs.mergeSort
  s[min ((p * s.length + 99) / 100 - 1) (s.length - 1)]?

/-- The median of each metric over repeated pushes. -/
def Metrics.median (ms : List Metrics) : Option Metrics := do
  let q (f : Metrics → Nat) := quantile (ms.map f) 50
  pure ⟨← q Metrics.n, ← q Metrics.travel, ← q Metrics.stalls, ← q Metrics.jumps, ← q Metrics.reversals,
    ← q Metrics.peakPm, ← q Metrics.peakRatio, ← q Metrics.tailSteps, ← q Metrics.tailT⟩

/-! ### What each metric detects -/

/-- Every shown step equals the ideal step: the shown value is on the curve. -/
def Exact (ps : List Step) : Prop := ∀ p ∈ ps, p.s = p.e

theorem steps_length (fs : List Frame) : (steps fs).length = fs.length - 1 := by
  induction fs with
  | nil => rfl
  | cons a tl ih =>
    cases tl with
    | nil => rfl
    | cons b rest => simp [steps, ih]

/-- Frames on the curve make exact steps. -/
theorem steps_exact (fs : List Frame) (h : ∀ f ∈ fs, f.shown = f.want) : Exact (steps fs) := by
  induction fs with
  | nil => simp [steps, Exact]
  | cons a tl ih =>
    cases tl with
    | nil => simp [steps, Exact]
    | cons b rest =>
      have ha := h a (by simp)
      have hb := h b (by simp)
      intro p hp
      simp only [steps, List.mem_cons] at hp
      rcases hp with rfl | hp
      · simp [ha, hb]
      · exact ih (fun f hf => h f (by rcases List.mem_cons.mp hf with rfl | hf; simp; simp [hf])) p
          (by simpa [steps] using hp)

/-- **A held value stalls.** The ideal moves enough and the shown value does not move. -/
theorem stalled_held (T : Nat) (p : Step) (hs : p.s = 0) (he : p.e ≠ 0) (hT : stallPm * T ≤ 1000 * p.e.natAbs) :
    p.stalled T = true := by
  have : 0 < p.e.natAbs := Int.natAbs_pos.mpr he
  simp [Step.stalled, hs, hT, this]

/-- The branch where the ideal barely moves: no stall, whatever is shown. -/
theorem not_stalled_small (T : Nat) (p : Step) (h : 1000 * p.e.natAbs < stallPm * T) : p.stalled T = false := by
  simp [Step.stalled, Nat.not_le.mpr h]

/-- The branch where the shown value follows at least a quarter of the ideal: no stall. -/
theorem not_stalled_follows (T : Nat) (p : Step) (h : p.e.natAbs ≤ stallDiv * p.s.natAbs) : p.stalled T = false := by
  simp [Step.stalled, Nat.not_lt.mpr h]

/-- **A leap past the ideal jumps.** -/
theorem jumped_of_leap (T : Nat) (p : Step) (h : (jumpPm : Int) * T < 1000 * ((p.s.natAbs : Int) - p.e.natAbs)) :
    p.jumped T = true := by
  simp [Step.jumped, h]

/-- The branch where the shown step is within the ideal step plus the allowance: no jump. -/
theorem not_jumped_within (T : Nat) (p : Step) (h : 1000 * ((p.s.natAbs : Int) - p.e.natAbs) ≤ (jumpPm : Int) * T) :
    p.jumped T = false := by
  simp [Step.jumped, h]

/-- **A step against the ideal reverses.** -/
theorem reversed_of_opposite (T : Nat) (p : Step) (h : p.s * p.e < 0) (hT : reversePm * T ≤ 1000 * p.s.natAbs) :
    p.reversed T = true := by
  simp [Step.reversed, h, hT]

/-- The branch where the shown step goes with the ideal: no reversal. -/
theorem not_reversed_same (T : Nat) (p : Step) (h : 0 ≤ p.s * p.e) : p.reversed T = false := by
  simp [Step.reversed, Int.not_lt.mpr h]

private theorem mul_self_nonneg' (e : Int) : 0 ≤ e * e := by
  rcases Int.le_total 0 e with h | h
  · exact Int.mul_nonneg h h
  · have := Int.mul_nonneg (Int.neg_nonneg_of_nonpos h) (Int.neg_nonneg_of_nonpos h)
    simpa [Int.neg_mul_neg] using this

private theorem idleFront_mem (l : List Step) (p : Step) (h : p ∈ idleFront l) : p ∈ l ∧ p.e = 0 := by
  induction l with
  | nil => simp [idleFront] at h
  | cons q rest ih =>
    simp only [idleFront] at h
    by_cases hq : q.e == 0
    · simp only [hq, ite_true, List.mem_cons] at h
      rcases h with rfl | h
      · exact ⟨by simp, by simpa using hq⟩
      · have := ih h
        exact ⟨List.mem_cons_of_mem _ this.1, this.2⟩
    · simp [hq] at h

private theorem countP_zero_of (f : Step → Bool) (ps : List Step) (h : ∀ p ∈ ps, f p = false) : ps.countP f = 0 :=
  List.countP_eq_zero.mpr (fun p hp => by simp [h p hp])

/-- **An exact curve has no defect**: no stall, no jump, no reversal, no tail. -/
theorem exact_zero (ps : List Step) (h : Exact ps) :
    stalls ps = 0 ∧ jumps ps = 0 ∧ reversals ps = 0 ∧ tailSteps ps = 0 := by
  refine ⟨countP_zero_of _ _ fun p hp => ?_, countP_zero_of _ _ fun p hp => ?_, countP_zero_of _ _ fun p hp => ?_,
    countP_zero_of _ _ fun p hp => ?_⟩
  · have := h p hp
    by_cases he : p.e = 0
    · simp [Step.stalled, this, he]
    · apply not_stalled_follows
      simp [this, stallDiv]; omega
  · have := h p hp
    simp only [Step.jumped, this, jumpPm, Int.sub_self, Int.mul_zero, decide_eq_false_iff_not]
    omega
  · have := h p hp
    exact not_reversed_same _ _ (by rw [this]; exact mul_self_nonneg' p.e)
  · simp only [idleRun, List.mem_reverse] at hp
    obtain ⟨hmem, hz⟩ := idleFront_mem _ _ hp
    have := h p (List.mem_reverse.mp hmem)
    simp [this, hz]

/-- On the curve the largest shown step equals the largest ideal step. -/
theorem peakRatio_exact (ps : List Step) (h : Exact ps) (hp : peakIdeal ps ≠ 0) : peakRatio ps = 1000 := by
  have : peakShown ps = peakIdeal ps := by
    unfold peakShown peakIdeal
    congr 1
    apply List.map_congr_left
    intro p hp
    rw [h p hp]
  simp [peakRatio, hp, this, Nat.mul_div_cancel _ (Nat.pos_of_ne_zero hp)]

/-- **A skipped frame is not a continuity defect**: merging two steps of an exact curve leaves it exact. -/
theorem merge_exact (a b : Step) (h : Exact [a, b]) : Exact [⟨b.t, a.e + b.e, a.s + b.s⟩] := by
  intro p hp
  simp at hp
  subst hp
  have ha := h a (by simp)
  have hb := h b (by simp)
  simp [ha, hb]

/-- A step in which the ideal moves by `n` and the shown value by `m`. -/
def catchUp (n m : Nat) : Step := ⟨0, (n : Int), (m : Int)⟩

/-- The steps of a restarting transition: `h` steps in which the ideal moves by `n` and the shown value stays, then one
step in which the shown value catches up with everything the ideal moved. -/
def restart (h n : Nat) : List Step := List.replicate h (catchUp n 0) ++ [catchUp n ((h + 1) * n)]

/-- The steps of a held value: `k` steps in which the ideal moves by `n` and the shown value stays. -/
def held (k n : Nat) : List Step := List.replicate k (catchUp n 0)

private theorem sum_replicate_e (k n : Nat) : ((List.replicate k (catchUp n 0)).map Step.e).sum = ((k * n : Nat) : Int) := by
  induction k with
  | zero => simp
  | succ k ih =>
    simp only [catchUp] at ih
    simp only [catchUp, List.replicate_succ, List.map_cons, List.sum_cons, ih]
    rw [Nat.succ_mul]
    omega

private theorem natAbs_cast (m : Nat) : ((m : Int)).natAbs = m := Int.natAbs_natCast m

theorem travel_held (k n : Nat) : travel (held k n) = k * n := by
  unfold travel held
  rw [sum_replicate_e, natAbs_cast]

theorem travel_restart (h n : Nat) : travel (restart h n) = (h + 1) * n := by
  have := sum_replicate_e h n
  unfold travel restart
  rw [List.map_append, List.sum_append, this]
  simp only [catchUp, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil]
  rw [Nat.succ_mul]
  have : (((h * n : Nat) : Int) + (((n : Nat) : Int) + 0)) = ((h * n + n : Nat) : Int) := by omega
  rw [this, natAbs_cast]

private theorem hold_stalled (T n : Nat) (hn : 0 < n) (h : stallPm * T ≤ 1000 * n) :
    Step.stalled T (catchUp n 0) = true := by
  simp only [Step.stalled, catchUp, natAbs_cast, Nat.mul_zero]
  simp [h, hn]

private theorem hold_not_jumped (T n : Nat) : Step.jumped T (catchUp n 0) = false := by
  simp only [Step.jumped, catchUp, natAbs_cast, jumpPm]
  simp only [decide_eq_false_iff_not]
  omega

private theorem hold_not_reversed (T n : Nat) : Step.reversed T (catchUp n 0) = false := by
  simp [Step.reversed, catchUp]

private theorem catch_not_stalled (T n m : Nat) (hm : n ≤ m) :
    Step.stalled T (catchUp n m) = false := by
  simp only [Step.stalled, catchUp, natAbs_cast, stallDiv]
  have : n ≤ 4 * m := by omega
  simp [Nat.not_lt.mpr this]

private theorem catch_jumped (n m : Nat) (hn : 0 < n) (hm : 2 * n ≤ m) :
    Step.jumped m (catchUp n m) = true := by
  simp only [Step.jumped, catchUp, natAbs_cast, jumpPm]
  simp only [decide_eq_true_eq]
  omega

private theorem catch_not_reversed (T n m : Nat) :
    Step.reversed T (catchUp n m) = false := by
  simp only [Step.reversed, catchUp, Bool.and_eq_false_imp]
  intro hlt
  exfalso
  have hlt := of_decide_eq_true hlt
  have : (0 : Int) ≤ (m : Int) * (n : Int) := Int.mul_nonneg (Int.natCast_nonneg _) (Int.natCast_nonneg _)
  omega

/-- **A held value is all stalls.** While the ideal moves the shown value stays: every step stalls and none jumps. -/
theorem held_stalls (k n : Nat) (hn : 0 < n) (hk : k * stallPm ≤ 1000) :
    stalls (held k n) = k ∧ jumps (held k n) = 0 ∧ reversals (held k n) = 0 := by
  have hT := travel_held k n
  have h5 : stallPm * (k * n) ≤ 1000 * n := by
    have := Nat.mul_le_mul_right n hk
    calc stallPm * (k * n) = k * stallPm * n := by ac_rfl
      _ ≤ 1000 * n := this
  refine ⟨?_, ?_, ?_⟩
  · unfold stalls; rw [hT]; unfold held
    rw [List.countP_eq_length.mpr (fun p hp => by
      rw [List.mem_replicate] at hp; rw [hp.2]; exact hold_stalled _ n hn h5), List.length_replicate]
  · unfold jumps; rw [hT]; unfold held
    exact List.countP_eq_zero.mpr (fun p hp => by
      rw [List.mem_replicate] at hp; rw [hp.2, hold_not_jumped]; simp)
  · unfold reversals; rw [hT]; unfold held
    exact List.countP_eq_zero.mpr (fun p hp => by
      rw [List.mem_replicate] at hp; rw [hp.2, hold_not_reversed]; simp)

/-- **A restarting transition is flagged as stalls, then a jump.** The `h` held steps are all stalls, the catch-up step is
the only jump, and nothing reverses. -/
theorem restart_flagged (h n : Nat) (hn : 0 < n) (h1 : 1 ≤ h) (h2 : (h + 1) * stallPm ≤ 1000) :
    stalls (restart h n) = h ∧ jumps (restart h n) = 1 ∧ reversals (restart h n) = 0 := by
  have hT := travel_restart h n
  have h5 : stallPm * ((h + 1) * n) ≤ 1000 * n := by
    have := Nat.mul_le_mul_right n h2
    calc stallPm * ((h + 1) * n) = (h + 1) * stallPm * n := by ac_rfl
      _ ≤ 1000 * n := this
  refine ⟨?_, ?_, ?_⟩
  · unfold stalls; rw [hT]; unfold restart
    rw [List.countP_append, List.countP_eq_length.mpr (fun p hp => by
      rw [List.mem_replicate] at hp; rw [hp.2]; exact hold_stalled _ n hn h5), List.length_replicate]
    simp [catch_not_stalled ((h + 1) * n) n ((h + 1) * n) (by have := Nat.le_mul_of_pos_left n (show 0 < h + 1 by omega); omega)]
  · unfold jumps; rw [hT]; unfold restart
    rw [List.countP_append, List.countP_eq_zero.mpr (fun p hp => by
      rw [List.mem_replicate] at hp; rw [hp.2, hold_not_jumped]; simp)]
    simp [catch_jumped n ((h + 1) * n) hn (Nat.mul_le_mul_right n (by omega))]
  · unfold reversals; rw [hT]; unfold restart
    rw [List.countP_append, List.countP_eq_zero.mpr (fun p hp => by
      rw [List.mem_replicate] at hp; rw [hp.2, hold_not_reversed]; simp)]
    simp [catch_not_reversed ((h + 1) * n) n ((h + 1) * n)]

private theorem idleFront_append (a b : List Step) (h : ∀ p ∈ a, p.e = 0) : idleFront (a ++ b) = a ++ idleFront b := by
  induction a with
  | nil => rfl
  | cons q rest ih =>
    have hq := h q (by simp)
    simp only [List.cons_append, idleFront, hq, beq_self_eq_true, ite_true]
    rw [ih (fun p hp => h p (List.mem_cons_of_mem _ hp))]

private theorem idleFront_stop (b : List Step) (h : ∀ q ∈ b.head?, q.e ≠ 0) : idleFront b = [] := by
  cases b with
  | nil => rfl
  | cons q rest =>
    have := h q (by simp)
    simp [idleFront, this]

/-- **A late tail is counted.** After the ideal's last move, `post` steps stand still in the ideal and still move
the shown value: every one is a tail step. -/
theorem tail_late (pre post : List Step) (hpost : ∀ p ∈ post, p.e = 0 ∧ p.s ≠ 0)
    (hpre : ∀ q ∈ pre.getLast?, q.e ≠ 0) : tailSteps (pre ++ post) = post.length := by
  have hb : ∀ q ∈ pre.reverse.head?, q.e ≠ 0 := by
    intro q hq
    rw [List.head?_reverse] at hq
    exact hpre q hq
  have hrun : idleRun (pre ++ post) = post := by
    unfold idleRun
    rw [List.reverse_append, idleFront_append _ _ (fun p hp => (hpost p (List.mem_reverse.mp hp)).1),
      idleFront_stop _ hb]
    simp
  unfold tailSteps
  rw [hrun, List.countP_eq_length.mpr]
  intro p hp
  simp [(hpost p hp).2]

/-! ### Cadence: frames that took too long, per arm, judged against the A/A spread -/

/-- A frame interval above this many tenths of a millisecond is a bad frame (the phone note's 34 ms line). -/
def badTenths : Nat := 340
/-- Fewest repeats an arm needs before it is judged. -/
def minReps : Nat := 5

/-- One repeat of one window: the frame intervals seen and how many of them are bad. -/
structure Rep where
  frames : Nat
  bad : Nat
deriving Repr, BEq

/-- The repeat made from its frame intervals (tenths of ms). -/
def Rep.ofIntervals (ivs : List Nat) : Rep := ⟨ivs.length, ivs.countP fun i => decide (badTenths < i)⟩

/-- Bad frames per 10000 frames (0 when there are no frames). -/
def rate (frames bad : Nat) : Nat := if frames = 0 then 0 else 10000 * bad / frames

/-- All repeats of one arm. -/
abbrev Arm := List Rep

/-- The pooled rate of an arm. -/
def armRate (a : Arm) : Nat := rate (a.map Rep.frames).sum (a.map Rep.bad).sum

/-- The rate of each repeat. -/
def repRates (a : Arm) : List Nat := a.map fun r => rate r.frames r.bad

/-- Largest minus smallest repeat rate (0 when empty). -/
def repRange (a : Arm) : Nat :=
  match repRates a with
  | [] => 0
  | x :: xs => xs.foldl max x - xs.foldl min x

/-- The distance between two numbers. -/
def dist (a b : Nat) : Nat := (a - b) + (b - a)

/-- The noise the A/A pair shows: the larger of the gap between its two arms and the spread of repeats inside either. -/
def spread (aa1 aa2 : Arm) : Nat := max (dist (armRate aa1) (armRate aa2)) (max (repRange aa1) (repRange aa2))

/-- Which of two arms is smoother. -/
inductive Verdict where
  | first | second | same | insufficient
deriving Repr, BEq, DecidableEq

/-- The wire name of a verdict. -/
def Verdict.name : Verdict → String
  | .first => "first" | .second => "second" | .same => "same" | .insufficient => "insufficient"

/-- The other arm. -/
def Verdict.swap : Verdict → Verdict
  | .first => .second | .second => .first | .same => .same | .insufficient => .insufficient

/-- The arm with the lower rate wins only when the other's rate is above it by more than the spread `sp`. -/
def judge (sp ra rb : Nat) : Verdict :=
  if ra + sp < rb then .first else if rb + sp < ra then .second else .same

/-- An arm has enough repeats to be judged. -/
def enough (a : Arm) : Bool := decide (minReps ≤ a.length)

/-- All four arms have enough repeats. -/
def ok (a b aa1 aa2 : Arm) : Bool := enough a && enough b && enough aa1 && enough aa2

/-- The verdict on arms `a` and `b` against the A/A pair `aa1`, `aa2`; none of the four may have fewer than `minReps` repeats. -/
def verdict (a b aa1 aa2 : Arm) : Verdict :=
  if ok a b aa1 aa2 then judge (spread aa1 aa2) (armRate a) (armRate b) else .insufficient

/-- **Too few repeats is never a verdict.** -/
theorem verdict_insufficient (a b aa1 aa2 : Arm) (h : ok a b aa1 aa2 = false) : verdict a b aa1 aa2 = .insufficient := by
  simp [verdict, h]

theorem ok_swap (a b aa1 aa2 : Arm) : ok b a aa1 aa2 = ok a b aa1 aa2 := by
  unfold ok
  cases enough a <;> cases enough b <;> simp

/-- The branch where the first arm's rate plus the spread is under the second's: the first is smoother. -/
theorem judge_first (sp ra rb : Nat) (h : ra + sp < rb) : judge sp ra rb = .first := by
  simp [judge, h]

/-- The branch where the second arm's rate plus the spread is under the first's: the second is smoother. -/
theorem judge_second (sp ra rb : Nat) (h : rb + sp < ra) : judge sp ra rb = .second := by
  unfold judge
  have : ¬ ra + sp < rb := by omega
  simp [this, h]

/-- The branch where the rates are within the spread of each other: same. -/
theorem judge_same (sp ra rb : Nat) (h1 : rb ≤ ra + sp) (h2 : ra ≤ rb + sp) : judge sp ra rb = .same := by
  unfold judge
  have a : ¬ ra + sp < rb := by omega
  have b : ¬ rb + sp < ra := by omega
  simp [a, b]

/-- Judging the arms the other way round swaps the verdict. -/
theorem judge_swap (sp ra rb : Nat) : judge sp rb ra = (judge sp ra rb).swap := by
  unfold judge
  by_cases h1 : ra + sp < rb
  · have : ¬ rb + sp < ra := by omega
    simp [h1, this, Verdict.swap]
  · by_cases h2 : rb + sp < ra
    · simp [h1, h2, Verdict.swap]
    · simp [h1, h2, Verdict.swap]

/-- A wider spread never turns a difference into one: if the first arm wins at spread `sp'`, it wins at any `sp ≤ sp'`. -/
theorem judge_first_mono (sp sp' ra rb : Nat) (h : sp ≤ sp') (hj : judge sp' ra rb = .first) : judge sp ra rb = .first := by
  unfold judge at hj
  by_cases h1 : ra + sp' < rb
  · exact judge_first _ _ _ (by omega)
  · by_cases h2 : rb + sp' < ra <;> simp [h1, h2] at hj

/-- The same for the second arm. -/
theorem judge_second_mono (sp sp' ra rb : Nat) (h : sp ≤ sp') (hj : judge sp' ra rb = .second) : judge sp ra rb = .second := by
  rw [judge_swap] at hj
  rw [judge_swap]
  have : judge sp' rb ra = .first := by
    cases hh : judge sp' rb ra <;> simp_all [Verdict.swap]
  rw [judge_first_mono sp sp' rb ra h this]
  rfl

/-- **The A/A pair is never told apart.** Two arms of the same code, judged against their own spread, are the same. -/
theorem aa_same (aa1 aa2 : Arm) (h1 : enough aa1 = true) (h2 : enough aa2 = true) :
    verdict aa1 aa2 aa1 aa2 = .same := by
  have : ok aa1 aa2 aa1 aa2 = true := by simp [ok, h1, h2]
  unfold verdict
  simp only [this, ite_true]
  apply judge_same <;> (unfold spread dist; omega)

/-- Swapping the two arms swaps the verdict. -/
theorem verdict_swap (a b aa1 aa2 : Arm) : verdict b a aa1 aa2 = (verdict a b aa1 aa2).swap := by
  unfold verdict
  rw [ok_swap]
  by_cases h : ok a b aa1 aa2 = true
  · simp only [h, ite_true]; exact judge_swap _ _ _
  · simp [h, Verdict.swap]

/-! ### Hitches: frames over 60 ms, counted per repeat

The rate rule above pools bad frames over repeats and compares the difference with a per-repeat range, so one more bad frame in one
A/A repeat can be as large as a one-frame-per-repeat effect (a repeat has about 172 frames at 390 px: one frame is 0.58 points).
The hitch metric counts frames over 60 ms in each repeat and compares whole repeats: an arm is hitchier only when every one of its
repeats has more hitches than every repeat of the other. -/

/-- A frame interval above this many tenths of a millisecond is a hitch (60 ms). -/
def hitchTenths : Nat := 600

/-- Hitches in one repeat, from its frame intervals (tenths of ms). -/
def hitches (ivs : List Nat) : Nat := ivs.countP fun i => decide (hitchTenths < i)

/-- Every repeat of `a` has more hitches than every repeat of `b`. -/
def above (a b : List Nat) : Bool := a.all fun x => b.all fun y => decide (y < x)

theorem above_iff (a b : List Nat) : above a b = true ↔ ∀ x ∈ a, ∀ y ∈ b, y < x := by
  simp [above, List.all_eq_true]

/-- An arm's hitch counts have enough repeats to be judged. -/
def enoughN (c : List Nat) : Bool := decide (minReps ≤ c.length)

/-- Which arm is smoother by hitch counts: the first when every repeat of the second has more hitches than every repeat of the first. -/
def hitchJudge (a b : List Nat) : Verdict :=
  if above b a then .first else if above a b then .second else .same

/-- All four arms have enough repeats of hitch counts. -/
def okN (a b aa1 aa2 : List Nat) : Bool := enoughN a && enoughN b && enoughN aa1 && enoughN aa2

/-- The hitch verdict on the repeat counts of `a` and `b` against the A/A pair. Fewer than `minReps` repeats in any of the four is
`insufficient`. When the A/A pair is itself told apart the metric is not steady on this runner and no difference is claimed (`same`). -/
def hitchVerdict (a b aa1 aa2 : List Nat) : Verdict :=
  if okN a b aa1 aa2 then
    (match hitchJudge aa1 aa2 with
      | .same => hitchJudge a b
      | _ => .same)
  else .insufficient

private theorem ne_nil_of_enoughN (c : List Nat) (h : enoughN c = true) : c ≠ [] := by
  intro hc
  subst hc
  simp [enoughN, minReps] at h

private theorem not_above_both (a b : List Nat) (ha : a ≠ []) (hb : b ≠ []) (h : above a b = true) : above b a = false := by
  cases h2 : above b a
  · rfl
  · rw [above_iff] at h h2
    obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil a ha
    obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil b hb
    have := h x hx y hy
    have := h2 y hy x hx
    omega

/-- The branch where every repeat of the second arm has more hitches: the first arm is smoother. -/
theorem hitchJudge_first (a b : List Nat) (h : above b a = true) : hitchJudge a b = .first := by
  simp [hitchJudge, h]

/-- The branch where every repeat of the first arm has more hitches: the second arm is smoother. -/
theorem hitchJudge_second (a b : List Nat) (ha : a ≠ []) (hb : b ≠ []) (h : above a b = true) : hitchJudge a b = .second := by
  have := not_above_both a b ha hb h
  simp [hitchJudge, this, h]

/-- The branch where neither arm's repeats are all above the other's: same. -/
theorem hitchJudge_same (a b : List Nat) (h1 : above b a = false) (h2 : above a b = false) : hitchJudge a b = .same := by
  simp [hitchJudge, h1, h2]

/-- Judging the arms the other way round swaps the verdict (for arms with repeats). -/
theorem hitchJudge_swap (a b : List Nat) (ha : a ≠ []) (hb : b ≠ []) : hitchJudge b a = (hitchJudge a b).swap := by
  by_cases h1 : above b a = true
  · have h2 := not_above_both b a hb ha h1
    simp [hitchJudge, h1, h2, Verdict.swap]
  · by_cases h2 : above a b = true
    · simp [hitchJudge, h1, h2, Verdict.swap]
    · simp [hitchJudge, h1, h2, Verdict.swap]

/-- **A hitch in every repeat of one arm and none in the other is detected.** If every repeat of `a` has at least one frame over 60 ms
and no repeat of `b` has any, and both have repeats, the second arm is smoother. -/
theorem hitch_detected (a b : List Nat) (ha : a ≠ []) (hb : b ≠ []) (hall : ∀ x ∈ a, 0 < x) (hnone : ∀ y ∈ b, y = 0) :
    hitchJudge a b = .second := by
  apply hitchJudge_second a b ha hb
  rw [above_iff]
  intro x hx y hy
  rw [hnone y hy]
  exact hall x hx

/-- The same through the full verdict, against a steady A/A pair. -/
theorem hitchVerdict_detected (a b aa1 aa2 : List Nat) (hok : okN a b aa1 aa2 = true)
    (haa : hitchJudge aa1 aa2 = .same) (hall : ∀ x ∈ a, 0 < x) (hnone : ∀ y ∈ b, y = 0) :
    hitchVerdict a b aa1 aa2 = .second := by
  have ha : enoughN a = true := by simp [okN] at hok; exact hok.1.1.1
  have hb : enoughN b = true := by simp [okN] at hok; exact hok.1.1.2
  unfold hitchVerdict
  simp only [hok, ↓reduceIte, haa]
  exact hitch_detected a b (ne_nil_of_enoughN a ha) (ne_nil_of_enoughN b hb) hall hnone

/-- The mirror: a hitch in every repeat of the second arm and none in the first makes the first smoother. -/
theorem hitchVerdict_detected_first (a b aa1 aa2 : List Nat) (hok : okN a b aa1 aa2 = true)
    (haa : hitchJudge aa1 aa2 = .same) (hall : ∀ y ∈ b, 0 < y) (hnone : ∀ x ∈ a, x = 0) :
    hitchVerdict a b aa1 aa2 = .first := by
  unfold hitchVerdict
  simp only [hok, ↓reduceIte, haa]
  apply hitchJudge_first
  rw [above_iff]
  intro y hy x hx
  rw [hnone x hx]
  exact hall y hy

/-- **Too few repeats is never a verdict.** -/
theorem hitchVerdict_insufficient (a b aa1 aa2 : List Nat) (h : okN a b aa1 aa2 = false) :
    hitchVerdict a b aa1 aa2 = .insufficient := by
  simp [hitchVerdict, h]

/-- **An A/A pair that is itself told apart claims no difference.** -/
theorem hitchVerdict_noisy (a b aa1 aa2 : List Nat) (hok : okN a b aa1 aa2 = true)
    (haa : hitchJudge aa1 aa2 ≠ .same) : hitchVerdict a b aa1 aa2 = .same := by
  unfold hitchVerdict
  split
  · split
    · exact absurd ‹hitchJudge aa1 aa2 = .same› haa
    · rfl
  · simp_all

/-- **The A/A pair is never told apart.** -/
theorem hitchVerdict_aa_same (aa1 aa2 : List Nat) (h1 : enoughN aa1 = true) (h2 : enoughN aa2 = true) :
    hitchVerdict aa1 aa2 aa1 aa2 = .same := by
  have hok : okN aa1 aa2 aa1 aa2 = true := by simp [okN, h1, h2]
  unfold hitchVerdict
  simp only [hok, ↓reduceIte]
  cases h : hitchJudge aa1 aa2 <;> simp

private theorem okN_swap (a b aa1 aa2 : List Nat) : okN b a aa1 aa2 = okN a b aa1 aa2 := by
  unfold okN
  cases enoughN a <;> cases enoughN b <;> simp

/-- Swapping the two arms swaps the hitch verdict. -/
theorem hitchVerdict_swap (a b aa1 aa2 : List Nat) : hitchVerdict b a aa1 aa2 = (hitchVerdict a b aa1 aa2).swap := by
  by_cases h : okN a b aa1 aa2 = true
  · have hb : okN b a aa1 aa2 = true := by rw [okN_swap]; exact h
    have ha' : enoughN a = true := by simp [okN] at h; exact h.1.1.1
    have hb' : enoughN b = true := by simp [okN] at h; exact h.1.1.2
    unfold hitchVerdict
    simp only [hb, h, ↓reduceIte]
    cases hh : hitchJudge aa1 aa2
    all_goals simp [Verdict.swap]
    exact hitchJudge_swap a b (ne_nil_of_enoughN a ha') (ne_nil_of_enoughN b hb')
  · have hb : okN b a aa1 aa2 = false := by rw [okN_swap]; simpa using h
    have h' : okN a b aa1 aa2 = false := by simpa using h
    simp [hitchVerdict, h', hb, Verdict.swap]

/-! ### Across samples: how sure is a verdict that came out of several independent samples

One CI job is one sample. Each sample gives its own verdict; `across k` says the first (second) arm is smoother only when at least
`k` samples say so and no sample says the other. `same` and `insufficient` samples agree with neither side and disagree with neither. -/

/-- Fewest samples before agreement means anything. -/
def minSamples : Nat := 3

/-- The agreement asked of `n` samples: two thirds, rounded up (5 of 7, 7 of 10). -/
def agreeNeeded (n : Nat) : Nat := (2 * n + 2) / 3

/-- The samples that came to a verdict: first, second or same. -/
def decisive (vs : List Verdict) : Nat := vs.count .first + vs.count .second + vs.count .same

/-- The verdict over samples: `first` when at least `k` say first and none says second, `second` the other way, `same` otherwise;
`insufficient` below `minSamples` decisive samples or for `k = 0`. -/
def across (k : Nat) (vs : List Verdict) : Verdict :=
  if decisive vs < minSamples ∨ k = 0 then .insufficient
  else if k ≤ vs.count .first ∧ vs.count .second = 0 then .first
  else if k ≤ vs.count .second ∧ vs.count .first = 0 then .second
  else .same

private theorem decisive_le (vs : List Verdict) : decisive vs ≤ vs.length := by
  induction vs with
  | nil => simp [decisive]
  | cons x xs ih =>
    simp only [decisive, List.count_cons, List.length_cons] at ih ⊢
    cases x <;> simp (config := { decide := true }) only [ite_true, ite_false] <;> omega

/-- **Too few samples is never a verdict.** -/
theorem across_few (k : Nat) (vs : List Verdict) (h : vs.length < minSamples) : across k vs = .insufficient := by
  have hd : decisive vs ≤ vs.length := decisive_le vs
  unfold across
  repeat' split
  all_goals first | rfl | omega

/-- **Undecided samples are never a verdict.** Below `minSamples` first, second or same samples, `across` is `insufficient`. -/
theorem across_insufficient (k : Nat) (vs : List Verdict) (h : decisive vs < minSamples) : across k vs = .insufficient := by
  unfold across
  repeat' split
  all_goals first | rfl | omega

/-- The branch where at least `k` samples say first and none says second. -/
theorem across_first (k : Nat) (vs : List Verdict) (hk : 0 < k) (hn : minSamples ≤ decisive vs)
    (hf : k ≤ vs.count .first) (hs : vs.count .second = 0) : across k vs = .first := by
  unfold across
  repeat' split
  all_goals first | rfl | omega

/-- The branch where at least `k` samples say second and none says first. -/
theorem across_second (k : Nat) (vs : List Verdict) (hk : 0 < k) (hn : minSamples ≤ decisive vs)
    (hs : k ≤ vs.count .second) (hf : vs.count .first = 0) : across k vs = .second := by
  unfold across
  repeat' split
  all_goals first | rfl | omega

/-- **One disagreeing sample blocks the claim.** Any sample for each side gives `same`. -/
theorem across_split (k : Nat) (vs : List Verdict) (hk : 0 < k) (hn : minSamples ≤ decisive vs)
    (hf : 0 < vs.count .first) (hs : 0 < vs.count .second) : across k vs = .same := by
  unfold across
  repeat' split
  all_goals first | rfl | omega

/-- The branch where too few samples agree and none disagrees: same. -/
theorem across_same (k : Nat) (vs : List Verdict) (hk : 0 < k) (hn : minSamples ≤ decisive vs)
    (hf : vs.count .first < k) (hs : vs.count .second < k) : across k vs = .same := by
  unfold across
  repeat' split
  all_goals first | rfl | omega

private theorem count_swap (vs : List Verdict) (v : Verdict) : (vs.map Verdict.swap).count v.swap = vs.count v := by
  induction vs with
  | nil => simp
  | cons x xs ih =>
    simp only [List.map_cons, List.count_cons, ih]
    cases x <;> cases v <;> simp [Verdict.swap] <;> decide

/-- Swapping the sides of every sample swaps the verdict. -/
theorem across_swap (k : Nat) (vs : List Verdict) : across k (vs.map Verdict.swap) = (across k vs).swap := by
  have hf : (vs.map Verdict.swap).count .first = vs.count .second := count_swap vs .second
  have hs : (vs.map Verdict.swap).count .second = vs.count .first := count_swap vs .first
  have he : (vs.map Verdict.swap).count .same = vs.count .same := count_swap vs .same
  unfold across decisive
  rw [hf, hs, he]
  repeat' split
  all_goals first | rfl | omega

/-! ### Golden vectors the TS twin is checked against -/

open Lean in
/-- A metrics record as JSON. -/
def Metrics.toJson (m : Metrics) : Json :=
  Json.mkObj [("n", Lean.toJson m.n), ("travel", Lean.toJson m.travel), ("stalls", Lean.toJson m.stalls),
    ("jumps", Lean.toJson m.jumps), ("reversals", Lean.toJson m.reversals), ("peakPm", Lean.toJson m.peakPm),
    ("peakRatio", Lean.toJson m.peakRatio), ("tailSteps", Lean.toJson m.tailSteps), ("tailT", Lean.toJson m.tailT)]

/-- The frames of a case from `(time, want, shown)` rows. -/
def frames (rows : List (Nat × Int × Int)) : List Frame := rows.map fun r => ⟨r.1, r.2.1, r.2.2⟩

/-- A straight ideal ramp of `n + 1` frames 160 apart from 0 to `top`, with the shown values given. -/
def ramp (top : Int) (n : Nat) (shown : List Int) : List Frame :=
  (List.range (n + 1)).map fun i => Frame.mk (160 * i) (top * (i : Int) / (n : Int)) (shown.getD i 0)

/-- Named metric cases: frames of one push of one property. -/
def metricCases : List (String × List Frame) := [
  ("exact", ramp 1000 10 [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]),
  ("held-then-jump", ramp 1000 10 [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1000]),
  ("restart", ramp 1000 10 [0, 0, 0, 0, 0, 0, 600, 700, 800, 900, 1000]),
  ("reversal", ramp 1000 10 [0, 100, 200, 300, 150, 50, 600, 700, 800, 900, 1000]),
  ("late-tail", frames [(0, 0, 0), (160, 400, 400), (320, 800, 800), (480, 1000, 1000), (640, 1000, 1030), (800, 1000, 1050), (960, 1000, 1050)]),
  ("falling", frames [(0, 1000, 1000), (160, 750, 750), (320, 500, 500), (480, 250, 250), (640, 0, 0)]),
  ("skipped-frame", frames [(0, 0, 0), (160, 100, 100), (480, 500, 500), (640, 600, 600), (800, 1000, 1000)]),
  ("flat", frames [(0, 5, 5), (160, 5, 5), (320, 5, 5)]),
  ("flat-moving", frames [(0, 5, 5), (160, 5, 40), (320, 5, 5)]),
  ("one-frame", frames [(0, 0, 0)]),
  ("empty", []),
  ("noise-below-stall", frames [(0, 0, 0), (160, 1, 0), (320, 2, 0), (480, 3, 0), (640, 1000, 1000)])]

/-- Linear-ideal cases `(d0, v0, d1, v1, d)`. -/
def lerpCases : List (List Int) := [
  [0, 0, 10000, 152000, 0], [0, 0, 10000, 152000, 656], [0, 0, 10000, 152000, 10000], [10000, 152000, 0, 0, 3333],
  [0, 5, 0, 9, 0], [0, -100, 10000, 100, 5000], [10000, 0, 0, 1000, 2500], [0, 7, 3, 8, 1], [0, 8, 3, 7, 1], [0, 0, 10000, 1000, -1]]

/-- Interval lists in tenths of ms. -/
def repCases : List (List Nat) := [[], [167, 167, 166], [167, 340, 341, 1000], [160, 160, 160, 160], [339, 340, 341]]

/-- Rate cases `(frames, bad)`. -/
def rateCases : List (Nat × Nat) := [(0, 0), (100, 0), (100, 3), (7, 1), (10000, 10000), (3, 3)]

/-- An arm of `n` repeats of 100 frames with the given bad counts cycling. -/
def armOf (n : Nat) (bads : List Nat) : Arm := (List.range n).map fun i => ⟨100, bads.getD (i % bads.length) 0⟩

/-- Verdict cases `(a, b, aa1, aa2)`. -/
def verdictCases : List (Arm × Arm × Arm × Arm) := [
  (armOf 5 [1, 2, 1], armOf 5 [9, 11, 10], armOf 5 [3, 4, 3], armOf 5 [3, 3, 4]),
  (armOf 5 [9, 11, 10], armOf 5 [1, 2, 1], armOf 5 [3, 4, 3], armOf 5 [3, 3, 4]),
  (armOf 5 [3, 4, 3], armOf 5 [4, 3, 4], armOf 5 [3, 4, 3], armOf 5 [3, 3, 4]),
  (armOf 4 [1], armOf 5 [9], armOf 5 [3], armOf 5 [3]),
  (armOf 5 [1], armOf 5 [9], armOf 5 [3], armOf 4 [3]),
  (armOf 6 [3, 4, 3], armOf 6 [3, 4, 3], armOf 6 [3, 4, 3], armOf 6 [3, 4, 3]),
  (armOf 5 [0], armOf 5 [6], armOf 5 [0, 2], armOf 5 [3, 1]),
  (armOf 5 [0], armOf 5 [1], armOf 5 [0, 0, 0, 0, 0], armOf 5 [0, 0, 0, 0, 0])]

/-- Interval lists in tenths of ms for the hitch count (600 is not a hitch, 601 is). -/
def hitchIvCases : List (List Nat) := [[], [167, 600, 601, 1000], [600, 600], [601], [167, 167], [833, 167, 167, 167]]

/-- Hitch verdict cases `(a, b, aa1, aa2)` of per-repeat hitch counts. -/
def hitchVerdictCases : List (List Nat × List Nat × List Nat × List Nat) := [
  ([1, 1, 1, 1, 1], [0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]),
  ([0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]),
  ([1, 1, 0, 1, 1], [0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]),
  ([3, 3, 4, 3, 3], [1, 2, 1, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]),
  ([2, 3, 2, 2, 3], [1, 1, 2, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]),
  ([1, 1, 1, 1], [0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]),
  ([1, 1, 1, 1, 1], [0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [0, 0, 0, 0, 0]),
  ([1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]),
  ([1, 1, 1, 1, 1, 1, 1], [0, 0, 0, 0, 0, 0, 0], [1, 1, 1, 1, 1, 1, 1], [1, 1, 1, 1, 1, 1, 1])]

/-- Across cases `(k, per-sample verdicts)`. -/
def acrossCases : List (Nat × List Verdict) := [
  (5, [.first, .first, .first, .first, .first, .same, .same]),
  (5, [.first, .first, .first, .first, .first, .second]),
  (5, [.first, .first, .first, .first, .same, .same, .same]),
  (5, [.second, .second, .second, .second, .second, .second, .second]),
  (3, [.first, .first]),
  (0, [.first, .first, .first, .first, .first]),
  (2, [.first, .first, .insufficient]),
  (5, []),
  (3, [.second, .second, .second, .insufficient, .same]),
  (4, [.insufficient, .insufficient, .insufficient, .insufficient, .insufficient]),
  (4, [.first, .same, .insufficient, .insufficient, .insufficient]),
  (3, [.first, .first, .first, .insufficient, .insufficient]),
  (4, [.first, .first, .same, .insufficient, .insufficient])]

/-- Sample counts for the agreement asked. -/
def agreeCases : List Nat := [0, 1, 3, 4, 7, 10]

open Lean in
private def frameJson (f : Frame) : Json := Json.arr #[Lean.toJson f.t, Lean.toJson f.want, Lean.toJson f.shown]
open Lean in
private def armJson (a : Arm) : Json := Json.arr (a.map fun r => Json.arr #[Lean.toJson r.frames, Lean.toJson r.bad]).toArray

open Lean in
/-- The golden lines, one JSON object per case. -/
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("stallPm", Lean.toJson stallPm), ("stallDiv", Lean.toJson stallDiv),
    ("jumpPm", Lean.toJson jumpPm), ("reversePm", Lean.toJson reversePm), ("badTenths", Lean.toJson badTenths),
    ("minReps", Lean.toJson minReps), ("hitchTenths", Lean.toJson hitchTenths), ("minSamples", Lean.toJson minSamples)]).compress
  let ms := metricCases.map fun (name, fs) =>
    (Json.mkObj [("op", "metrics"), ("case", Json.str name), ("frames", Json.arr (fs.map frameJson).toArray),
      ("out", (metrics fs).toJson), ("flat", Lean.toJson (metrics fs).flat), ("flagged", Lean.toJson (metrics fs).flagged)]).compress
  let ls := lerpCases.map fun c =>
    (Json.mkObj [("op", "lerp"), ("args", Lean.toJson c),
      ("out", Lean.toJson (lerp (c.getD 0 0) (c.getD 1 0) (c.getD 2 0) (c.getD 3 0) (c.getD 4 0)))]).compress
  let ws := (metricCases.zip metricCases.tail).map fun ((na, a), (nb, b)) =>
    (Json.mkObj [("op", "worst"), ("a", Json.str na), ("b", Json.str nb), ("out", (Metrics.worst (metrics a) (metrics b)).toJson)]).compress
  let qs := [([5, 1, 9, 3, 7], 50), ([4, 4, 4], 50), ([10, 20], 50), ([], 50), ([8, 2, 6, 4], 100), ([8, 2, 6, 4], 1)].map fun (xs, p) =>
    (Json.mkObj [("op", "quantile"), ("xs", Lean.toJson xs), ("p", Lean.toJson p),
      ("out", match quantile xs p with | some v => Lean.toJson v | none => Json.null)]).compress
  let med := (Json.mkObj [("op", "median"), ("cases", Json.arr (metricCases.map fun c => Json.str c.1).toArray),
    ("out", match Metrics.median (metricCases.map fun c => metrics c.2) with | some m => m.toJson | none => Json.null)]).compress
  let med0 := (Json.mkObj [("op", "median"), ("cases", Json.arr #[]), ("out", Json.null)]).compress
  let reps := repCases.map fun ivs =>
    (Json.mkObj [("op", "rep"), ("ivs", Lean.toJson ivs),
      ("out", Json.arr #[Lean.toJson (Rep.ofIntervals ivs).frames, Lean.toJson (Rep.ofIntervals ivs).bad])]).compress
  let rs := rateCases.map fun (f, b) => (Json.mkObj [("op", "rate"), ("frames", Lean.toJson f), ("bad", Lean.toJson b), ("out", Lean.toJson (rate f b))]).compress
  let vs := verdictCases.map fun (a, b, aa1, aa2) =>
    (Json.mkObj [("op", "verdict"), ("a", armJson a), ("b", armJson b), ("aa1", armJson aa1), ("aa2", armJson aa2),
      ("spread", Lean.toJson (spread aa1 aa2)), ("rateA", Lean.toJson (armRate a)), ("rateB", Lean.toJson (armRate b)),
      ("out", Json.str (verdict a b aa1 aa2).name)]).compress
  let hs := hitchIvCases.map fun ivs => (Json.mkObj [("op", "hitches"), ("ivs", Lean.toJson ivs), ("out", Lean.toJson (hitches ivs))]).compress
  let hv := hitchVerdictCases.map fun (a, b, aa1, aa2) =>
    (Json.mkObj [("op", "hitchVerdict"), ("a", Lean.toJson a), ("b", Lean.toJson b), ("aa1", Lean.toJson aa1), ("aa2", Lean.toJson aa2),
      ("out", Json.str (hitchVerdict a b aa1 aa2).name)]).compress
  let ac := acrossCases.map fun (k, xs) =>
    (Json.mkObj [("op", "across"), ("k", Lean.toJson k), ("vs", Json.arr (xs.map fun v => Json.str v.name).toArray),
      ("out", Json.str (across k xs).name)]).compress
  let ag := agreeCases.map fun n => (Json.mkObj [("op", "agreeNeeded"), ("n", Lean.toJson n), ("out", Lean.toJson (agreeNeeded n))]).compress
  [consts] ++ ms ++ ls ++ ws ++ qs ++ [med, med0] ++ reps ++ rs ++ vs ++ hs ++ hv ++ ac ++ ag

/-- The exact bytes of `packages/contracts/golden/gate/smooth.jsonl`: the lines, each newline-terminated. -/
def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- The value after `flag` in an argument list. -/
def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

/-- Command-line driver (`lean/scripts/SmoothGolden.lean`): print the golden text, or with `--check <file>` exit 0 when the file
holds exactly these bytes and 1 otherwise. Print mode returns 0. -/
def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"smooth golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"smooth golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard (metrics (ramp 1000 10 [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000])).flagged == false
#guard (metrics (ramp 1000 10 [0, 0, 0, 0, 0, 0, 600, 700, 800, 900, 1000])).stalls == 5
#guard (metrics (ramp 1000 10 [0, 0, 0, 0, 0, 0, 600, 700, 800, 900, 1000])).jumps == 1
#guard (metrics (frames [(0, 0, 0), (160, 400, 400), (320, 800, 800), (480, 1000, 1000), (640, 1000, 1030), (800, 1000, 1050), (960, 1000, 1050)])).tailSteps == 2
#guard goldenLines.length == 61 + 6 + 9 + 13 + 6
#guard (verdict (armOf 5 [1, 2, 1]) (armOf 5 [9, 11, 10]) (armOf 5 [3, 4, 3]) (armOf 5 [3, 3, 4])) == .first
#guard (verdict (armOf 4 [1]) (armOf 5 [9]) (armOf 5 [3]) (armOf 5 [3])) == .insufficient
#guard hitches [167, 600, 601, 1000] == 2
#guard hitchVerdict [1, 1, 1, 1, 1] [0, 0, 0, 0, 0] [1, 1, 1, 1, 1] [1, 1, 1, 1, 1] == .second
#guard hitchVerdict [1, 1, 0, 1, 1] [0, 0, 0, 0, 0] [1, 1, 1, 1, 1] [1, 1, 1, 1, 1] == .same
#guard across 5 [.first, .first, .first, .first, .first, .same, .same] == .first
#guard across 5 [.first, .first, .first, .first, .first, .second] == .same
#guard across 3 [.insufficient, .insufficient, .insufficient, .insufficient] == .insufficient
#guard across 2 [.first, .first, .insufficient, .insufficient] == .insufficient
#guard across 2 [.first, .first, .same, .insufficient] == .first

end Fw.Gate.Smooth
