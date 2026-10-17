import Fw
/-!
# Study set B: from math to Lean, our key results (levels 6-10)

Run from `research/kickoff/05-lean-sketch`:

    lake env lean ../12-math-to-lean/StudyB.lean

Every section imports the real declaration from `Fw/Spec/*.lean` (so nothing is restated), shows
its type with `#check`, evaluates a few cases with `#eval`, and proves the lesson's exercise
answer. Nothing here uses `sorry`; the last lines print the axioms of the new theorems.
-/

open Fw

/-! ## B1 (level 6): dominance in the cost model, `Fw.Cost.mainUs_mono` -/
section B1
open Fw.Cost

#check @mainUs_mono
-- mainUs_mono : ∀ (u : UnitCost) {a b : Work}, a.le b → mainUs u a ≤ mainUs u b
#eval mainUs ⟨2, 3, 5⟩ ⟨100, 10, 4, 1⟩   -- 100 + 2*10 + 3*4 + 5*1 = 137
#eval mainUs ⟨2, 3, 5⟩ ⟨100, 11, 4, 1⟩   -- one more restyled element: 139

/-- Exercise B1 (answer): the converse of dominance is false; equal or lower cost does not imply
componentwise dominance (here all unit costs are zero).

$$\neg\Big(\forall u \in \mathbb{N}^{3},\ \forall a, b \in \mathbb{N}^{4}:\ \operatorname{mainUs}(u, a) \le \operatorname{mainUs}(u, b) \Rightarrow a \preceq b\Big)$$
-/
theorem B1_converse_false :
    ¬ ∀ (u : UnitCost) (a b : Work), mainUs u a ≤ mainUs u b → a.le b := by
  intro h
  have := h ⟨0, 0, 0⟩ ⟨0, 1, 0, 0⟩ ⟨0, 0, 0, 0⟩ (by decide)
  exact absurd this.2.1 (by decide)

/-- The same cost formula over the integers, where unit costs may be negative.

$$\operatorname{mainUsZ}(u, w) = s + u_{\mathrm{style}}\, e + u_{\mathrm{layout}}\, \ell + u_{\mathrm{paint}}\, k \quad (u \in \mathbb{Z}^{3},\ w \in \mathbb{Z}^{4})$$
-/
def mainUsZ (u : Int × Int × Int) (w : Int × Int × Int × Int) : Int :=
  w.1 + u.1 * w.2.1 + u.2.1 * w.2.2.1 + u.2.2 * w.2.2.2

/-- Gotcha B1: over $\mathbb{Z}$ the theorem needs $u \ge 0$; a negative unit cost breaks it
(more restyled elements, lower cost).

$$u = (-1, 0, 0),\ a = (0, 0, 0, 0) \preceq b = (0, 1, 0, 0),\ \text{yet}\ \operatorname{mainUsZ}(u, b) < \operatorname{mainUsZ}(u, a)$$
-/
theorem B1_int_needs_nonneg :
    mainUsZ (-1, 0, 0) (0, 1, 0, 0) < mainUsZ (-1, 0, 0) (0, 0, 0, 0) := by decide

end B1

/-! ## B2 (level 7): A/B isolation of a flag override, `Fw.Flags.override_diff` -/
section B2
open Fw.Flags

#check @override_diff
-- override_diff : ∀ (c : Config) (p : Part) (v : Variant), c p ≠ v → diff c (override c p v) = [p]
#eval diff (fun _ => "orig") (override (fun _ => "orig") .hero "v2")   -- [Fw.Flags.Part.hero]
#eval diff (fun _ => "orig") (override (fun _ => "orig") .hero "orig") -- []

/-- Exercise B2 (answer): overriding a part with the value it already has changes nothing.

$$\forall c \in \mathrm{Config},\ \forall p \in \mathrm{Part}:\quad \operatorname{diff}\big(c,\ c[p \mapsto c(p)]\big) = [\,]$$
-/
theorem B2_override_same (c : Config) (p : Part) : diff c (override c p (c p)) = [] := by
  cases p <;> simp [diff, override, Part.all]

end B2

/-! ## B3 (level 7): soundness of "better" when higher is better, `Fw.Verdict.better_sound_higher` -/
section B3
open Fw.Verdict

#check @better_sound_higher
-- better_sound_higher : verdict Dir.higher ctl var = Verdict.better → ∀ y ∈ var, ∀ x ∈ ctl, x < y
#check @verdict_higher_eq_lower_neg
#eval verdict .higher [58, 59, 60] [61, 62, 61]                 -- better
#eval verdict .lower ([58, 59, 60].map (- ·)) ([61, 62, 61].map (- ·))   -- better (duality)
#eval ([58, 59, 60] : List Nat).map (fun x => 0 - x)             -- [0, 0, 0]: no duality on ℕ

/-- Exercise B3 (answer): soundness of "worse" for lower-is-better: every control run was strictly
lower than every variant run.

$$\forall C, V \in \mathbb{Z}^{*}:\quad \operatorname{verdict}(\mathrm{lower}, C, V) = \mathrm{worse} \;\Rightarrow\; \forall x \in C,\ \forall y \in V:\ x < y$$
-/
theorem B3_worse_sound {ctl var : List Int} (h : verdict .lower ctl var = .worse) :
    ∀ x ∈ ctl, ∀ y ∈ var, x < y := by
  unfold verdict at h
  split at h
  · cases h
  · simp only at h
    split at h
    · cases h
    · split at h
      · exact (below_spec _ _).mp ‹_›
      · cases h

end B3

/-! ## B4 (level 8): the false-win rate of the 4-vs-4 verdict is 1/70

The real declaration is `Fw.Verdict.verdict`. The probability statement is not in `Fw/Spec` yet
(the plan calls it `land_null_prob`); here it is proved by enumeration. The step from counting to
probability is math, not Lean: with no real difference and no ties, all $8!$ orderings of the 8
runs are equally likely, the verdict depends only on which 4 of the 8 ranks the variant got, and
each of the $\binom{8}{4} = 70$ rank sets carries $4!\,4!$ orderings, so each is equally likely. -/
section B4
open Fw.Verdict

#check @verdict
#eval verdict .lower [5, 6, 7, 8] [1, 2, 3, 4]   -- better: the variant took the 4 lowest ranks
#eval verdict .lower [1, 6, 7, 8] [5, 2, 3, 4]   -- noise: one overlap is enough

/-- All $k$-element sublists of a list, in order (a hand-written $\binom{xs}{k}$, no Mathlib).

$$\operatorname{choose}(0, xs) = [[\,]], \quad \operatorname{choose}(k{+}1, [\,]) = [\,], \quad \operatorname{choose}(k{+}1, x :: xs) = \big[x :: s \mid s \in \operatorname{choose}(k, xs)\big] \mathbin{+\!\!+} \operatorname{choose}(k{+}1, xs)$$
-/
def choose {α : Type} : Nat → List α → List (List α)
  | 0, _ => [[]]
  | _ + 1, [] => []
  | k + 1, x :: xs => (choose k xs).map (x :: ·) ++ choose (k + 1) xs

#guard (choose 2 [1, 2, 3]) == [[1, 2], [1, 3], [2, 3]]
#guard (choose 4 [1, 2, 3, 4, 5, 6, 7, 8]).length == 70

/-- The ranks $1, \dots, 8$ of the 8 runs (4 control, 4 variant), all distinct.

$$\mathrm{ranks} = [1, 2, \dots, 8] \in \mathbb{Z}^{*}$$
-/
def ranks : List Int := [1, 2, 3, 4, 5, 6, 7, 8]

/-- Every way to give 4 ranks to the variant and the other 4 to the control, as (control, variant).

$$\mathrm{splits} = \big[\,(\mathrm{ranks} \setminus V,\ V) \mid V \in \operatorname{choose}(4, \mathrm{ranks})\,\big]$$
-/
def splits : List (List Int × List Int) :=
  (choose 4 ranks).map fun v => (ranks.filter (fun x => !v.contains x), v)

/-- The number of splits that the lower-is-better verdict calls "better".

$$\operatorname{wins} = \#\{\,(C, V) \in \mathrm{splits} : \operatorname{verdict}(\mathrm{lower}, C, V) = \mathrm{better}\,\}$$
-/
def wins : Nat := (splits.filter fun cv => verdict .lower cv.1 cv.2 == .better).length

#guard wins == 1

/-- There are exactly $\binom{8}{4} = 70$ splits.

$$|\mathrm{splits}| = 70$$
-/
theorem splits_length : splits.length = 70 := by decide

/-- Exactly one split is a false win: the one where the variant got the 4 lowest ranks.

$$\operatorname{wins} = 1$$
-/
theorem wins_eq_one : wins = 1 := by decide

/-- The false-win rate as a rational number: wins over splits.

$$p = \operatorname{wins} / |\mathrm{splits}| \in \mathbb{Q}$$
-/
def falseBetterProb : Rat := (wins : Rat) / (splits.length : Rat)

/-- Exercise B4 (answer): with no real difference, the 4-vs-4 verdict says "better" with
probability exactly $1/70$ (the counting part is proved; equal likelihood of the 70 splits is the
modelling assumption above).

$$p = \frac{\#\{\text{better splits}\}}{\binom{8}{4}} = \frac{1}{70}$$
-/
theorem falseBetterProb_eq : falseBetterProb = 1 / 70 := by
  unfold falseBetterProb
  rw [wins_eq_one, splits_length]
  rfl

end B4

/-! ## B5 (level 9): structural induction, `Fw.Frames.countAbove_antitone` -/
section B5
open Fw.Frames

#check @countAbove_antitone
-- countAbove_antitone : t ≤ t' → ∀ (xs : List Nat), countAbove t' xs ≤ countAbove t xs
#eval countAbove 34000 [33000, 34000, 36000, 52000]   -- 2 (34000 itself is not counted)
#eval countAbove 50000 [33000, 34000, 36000, 52000]   -- 1

/-- Exercise B5 (answer): counting is additive over concatenation.

$$\forall t \in \mathbb{N},\ \forall xs, ys \in \mathbb{N}^{*}:\quad \operatorname{countAbove}(t, xs \mathbin{+\!\!+} ys) = \operatorname{countAbove}(t, xs) + \operatorname{countAbove}(t, ys)$$
-/
theorem B5_countAbove_append (t : Nat) (xs ys : List Nat) :
    countAbove t (xs ++ ys) = countAbove t xs + countAbove t ys := by
  simp [countAbove, List.filter_append]

end B5

/-! ## B6 (level 10): the lease invariant is kept by every step, `Fw.Lease.step_inv` -/
section B6
open Fw.Lease

#check @step_inv
-- step_inv : ∀ {s : State} (c : Cmd), Lease.Inv s → Lease.Inv (step s c).fst
-- (written `Lease.Inv` because `open Fw` also sees the unrelated root-level `Inv` class)
#eval (step {} (.acquire "a" 0 10)).1
#eval (step (step {} (.acquire "a" 0 10)).1 (.acquire "b" 1 10)).1

/-- Run a list of commands from a state, keeping only the states.

$$\operatorname{run}(s, [\,]) = s, \qquad \operatorname{run}(s, c :: cs) = \operatorname{run}\big(\mathrm{step}(s, c)_1,\ cs\big)$$
-/
def run (s : State) (cs : List Cmd) : State := cs.foldl (fun s c => (step s c).1) s

#guard (run {} [.acquire "a" 0 10, .acquire "b" 1 10, .release "a" 5 20]).holder == some ⟨"b", 25⟩

/-- Many steps keep the invariant (induction on the command list, `step_inv` for one step).

$$\forall cs \in \mathrm{Cmd}^{*},\ \forall s \in \mathrm{State}:\quad \operatorname{Inv}(s) \;\Rightarrow\; \operatorname{Inv}\big(\operatorname{run}(s, cs)\big)$$
-/
theorem inv_run (cs : List Cmd) : ∀ s, Lease.Inv s → Lease.Inv (run s cs) := by
  induction cs with
  | nil => intro s h; exact h
  | cons c cs ih => intro s h; exact ih _ (step_inv c h)

/-- Exercise B6 (answer): every state reached from the empty state satisfies the invariant (the
corollary that the sketch leaves open as gap G3).

$$\forall cs \in \mathrm{Cmd}^{*}:\quad \operatorname{Inv}\big(\operatorname{run}(s_0, cs)\big), \qquad s_0 = (\bot, [\,])$$
-/
theorem inv_reachable (cs : List Cmd) : Lease.Inv (run {} cs) := inv_run cs {} inv_init

end B6

#print axioms B1_converse_false
#print axioms B1_int_needs_nonneg
#print axioms B2_override_same
#print axioms B3_worse_sound
#print axioms falseBetterProb_eq
#print axioms B5_countAbove_append
#print axioms inv_reachable
