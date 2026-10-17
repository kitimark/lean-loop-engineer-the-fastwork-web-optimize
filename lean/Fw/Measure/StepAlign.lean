import Fw.Measure.WebKit
/-!
# Aligning two WebKit scroll runs by scroll position (task `step-align`)

The original page and the rewrite have different heights, so their scroll runs (`y = 0, 50, 100 …` up to
the page's own maximum offset, `packages/measure-webkit/src/scrollrun.mjs`) have different numbers of steps
(107 against 74 on 2026-10-18: document heights 6042 and 4378 CSS px at the same step size). The runs agree
step by step where both scroll the same way, so they are compared by position, not by step number.

A step's **key** is the triple (previous offset, offset, next offset), `none` at the ends of the run: the
step's counting window starts at the scroll to its offset and ends at the next step's mark, so two steps
are the same piece of trajectory exactly when their keys are equal. The **paired** steps of a run are those
whose key occurs in the other run. Zones (`⌊y / h⌋`, as `Fw.Measure.WebKit.zones`) are summed over the
paired steps only; a zone is **full** when every step of that zone, in both runs, is paired (so nothing in
it was dropped, and the zone is comparable as a whole).

Laws proved: paired steps are a sublist of the run (`pairedSteps_sublist`), a run is fully paired with itself
(`pairedSteps_self`, `align_self`), the zone sums add up to the sum over the paired steps
(`align_partition_a`, `align_partition_b`) and paired plus unpaired steps add up to the whole run
(`paired_unpaired_total`), the delta is the difference of the two arms' sums (`align_delta_total`), swapping the
arms swaps the zones and negates the deltas (`align_swap`), a full zone carries exactly the plain zone sums
(`full_counts_a`).
-/
namespace Fw.Measure.StepAlign
open Fw.Measure Fw.Measure.WebKit

/-! ## Keys and paired steps -/

/-- The key of a step: previous offset, offset, next offset (`none` before the first and after the last step).

$$\mathrm{Key} = (\mathbb{Q} \cup \{\bot\}) \times \mathbb{Q} \times (\mathbb{Q} \cup \{\bot\})$$
-/
abbrev Key := Option Rat × Rat × Option Rat

/-- Steps with their keys, given the offset before the first step.

$$\operatorname{key}(S)_i = (y_{i-1},\, y_i,\, y_{i+1}),\quad y_0' = \bot,\ y_{|S|+1}' = \bot$$
-/
def keyedFrom : Option Rat → List Step → List (Key × Step)
  | _, [] => []
  | p, [s] => [((p, s.y, none), s)]
  | p, s :: t :: rest => ((p, s.y, some t.y), s) :: keyedFrom (some s.y) (t :: rest)

/-- The keyed steps of a run.

$$\operatorname{keyed}(S) = \operatorname{keyedFrom}(\bot, S)$$
-/
def keyed (ss : List Step) : List (Key × Step) := keyedFrom none ss

/-- Whether the run has a step with this key.

$$\operatorname{has}(S, \kappa) \iff \exists s \in S:\ \operatorname{key}(s) = \kappa$$
-/
def hasKey (ss : List Step) (k : Key) : Bool := (keyed ss).any (·.1 == k)

/-- The steps of `a` whose key occurs in `b`, in order.

$$P(A, B) = [\, s \in A \mid \operatorname{key}_A(s) \in \operatorname{keys}(B) \,]$$
-/
def pairedSteps (a b : List Step) : List Step := ((keyed a).filter (fun p => hasKey b p.1)).map (·.2)

/-- The steps of `a` whose key does not occur in `b`.

$$U(A, B) = [\, s \in A \mid \operatorname{key}_A(s) \notin \operatorname{keys}(B) \,]$$
-/
def unpairedSteps (a b : List Step) : List Step := ((keyed a).filter (fun p => !hasKey b p.1)).map (·.2)

#guard (pairedSteps [⟨0, [], 0⟩, ⟨50, [], 0⟩, ⟨100, [], 0⟩, ⟨103, [], 0⟩]
                    [⟨0, [], 0⟩, ⟨50, [], 0⟩, ⟨100, [], 0⟩, ⟨150, [], 0⟩, ⟨200, [], 0⟩]).map (·.y) == [0, 50]

/-- **Keying drops nothing.** Forgetting the keys of the keyed steps gives the steps back, whatever previous offset the
keying starts from.

$$\forall p\, ss.\;\; \operatorname{map}\,\pi_2\,(\operatorname{keyedFrom}_p(ss)) = ss$$
-/
theorem keyedFrom_map_snd : ∀ (p : Option Rat) (ss : List Step), (keyedFrom p ss).map (·.2) = ss
  | _, [] => rfl
  | _, [_] => rfl
  | p, s :: t :: rest => by
    simp only [keyedFrom, List.map_cons]
    rw [keyedFrom_map_snd (some s.y) (t :: rest)]

/-- **Keying drops nothing (from the start).** The keyed run, keys forgotten, is the run.

$$\operatorname{map}\,\pi_2\,(\operatorname{keyed}(ss)) = ss$$
-/
theorem keyed_map_snd (ss : List Step) : (keyed ss).map (·.2) = ss := keyedFrom_map_snd none ss

/-- **Paired steps are steps of the run.** The paired steps are a sublist of the run.

$$P(A, B) \sqsubseteq A$$
-/
theorem pairedSteps_sublist (a b : List Step) : (pairedSteps a b).Sublist a := by
  have h := (List.filter_sublist (p := fun p : Key × Step => hasKey b p.1) (l := keyed a)).map (·.2)
  rw [keyed_map_snd] at h
  exact h

/-- **Every step of a run has its own key in the run.**

$$\forall p \in \operatorname{keyed}(A).\;\; \operatorname{hasKey}_A(\pi_1\,p) = \text{true}$$
-/
theorem mem_hasKey_self (a : List Step) : ∀ p ∈ keyed a, hasKey a p.1 = true := by
  intro p hp
  simp only [hasKey, List.any_eq_true]
  exact ⟨p, hp, by simp⟩

/-- **A run is fully paired with itself.**

$$P(A, A) = A$$
-/
theorem pairedSteps_self (a : List Step) : pairedSteps a a = a := by
  unfold pairedSteps
  rw [List.filter_eq_self.mpr (fun p hp => mem_hasKey_self a p hp), keyed_map_snd]

/-- **Paired and unpaired steps add up.** For every column function, the paired steps' sum plus the
unpaired steps' sum is the whole run's.

$$\sum_{s \in P(A,B)} g(s) + \sum_{s \in U(A,B)} g(s) = \sum_{s \in A} g(s)$$
-/
theorem paired_unpaired_total (g : Step → Int) (a b : List Step) :
    sumBy g (pairedSteps a b) + sumBy g (unpairedSteps a b) = sumBy g a := by
  have key : ∀ (l : List (Key × Step)) (q : Key × Step → Bool),
      sumBy g ((l.filter q).map (·.2)) + sumBy g ((l.filter (fun x => !q x)).map (·.2)) = sumBy g (l.map (·.2)) := by
    intro l q
    induction l with
    | nil => rfl
    | cons x xs ih =>
      by_cases hq : q x = true
      · simp [hq, sumBy]; omega
      · have hq' : q x = false := by simpa using hq
        simp [hq', sumBy]; omega
  have := key (keyed a) (fun p => hasKey b p.1)
  rw [keyed_map_snd] at this
  exact this

/-! ## Aligned zones -/

/-- One aligned zone: the steps of the zone in each run, how many of them are paired, the sums of the paired
steps in each run, their difference, and whether the zone is full.

$$\mathrm{AZone} = \mathbb{N}^{6} \times (\mathbb{Z}^{*})^{3} \times \mathbb{Z}^{3} \times \{0, 1\}$$
-/
structure AZone where
  zone : Nat
  y0 : Nat
  stepsA : Nat
  stepsB : Nat
  pairedA : Nat
  pairedB : Nat
  countsA : List Int
  countsB : List Int
  delta : List Int
  areaA : Int
  areaB : Int
  areaDelta : Int
  full : Bool
deriving Repr, DecidableEq

/-- Aligned zone `z` of `a` against `b`: the zone records of the paired steps, the plain step counts, and
`full` (the zone has steps, and every step of both runs in it is paired).

$$\mathrm{full}_z \iff |A_z| > 0 \wedge |A_z| = |B_z| = |P(A,B)_z| = |P(B,A)_z|,\qquad \Delta_z = \operatorname{sum}(P(A,B)_z) - \operatorname{sum}(P(B,A)_z)$$
-/
def alignZone (h w : Nat) (a b : List Step) (z : Nat) : AZone :=
  let pa := zoneRec h w (pairedSteps a b) z
  let pb := zoneRec h w (pairedSteps b a) z
  let fa := (zoneSteps h a z).length
  let fb := (zoneSteps h b z).length
  { zone := z, y0 := z * h, stepsA := fa, stepsB := fb, pairedA := pa.steps, pairedB := pb.steps,
    countsA := pa.counts, countsB := pb.counts,
    delta := (List.range w).map fun j => valAt pa.counts j - valAt pb.counts j,
    areaA := pa.paintArea, areaB := pb.paintArea, areaDelta := pa.paintArea - pb.paintArea,
    full := decide (0 < fa ∧ fa = fb ∧ fa = pa.steps ∧ fb = pb.steps) }

/-- The number of aligned zones: the larger zone count of the two runs.

$$N = \max(N_h(A), N_h(B))$$
-/
def alignCount (h : Nat) (a b : List Step) : Nat := max (zoneCount h a) (zoneCount h b)

/-- **Aligned zones** of two runs, zones `0 … N-1`.

$$\operatorname{align}_{h,w}(A, B) = [\operatorname{azone}_{h,w}(A, B, z)]_{z < N}$$
-/
def align (h w : Nat) (a b : List Step) : List AZone :=
  (List.range (alignCount h a b)).map (alignZone h w a b)

/-- The zone with the roles of the two runs exchanged: the A and B fields swap and the delta changes sign.

$$\operatorname{swap}(z)_A = z_B,\quad \operatorname{swap}(z)_B = z_A,\quad \operatorname{swap}(z)_\Delta = -z_\Delta$$
-/
def AZone.swap (z : AZone) : AZone :=
  { z with stepsA := z.stepsB, stepsB := z.stepsA, pairedA := z.pairedB, pairedB := z.pairedA,
           countsA := z.countsB, countsB := z.countsA, delta := z.delta.map (- ·),
           areaA := z.areaB, areaB := z.areaA, areaDelta := - z.areaDelta }

/-- Column `j` of a zone record sum equals the sum of its steps (generic zone partition).

$$\forall n,\ P,\ j<w:\ (\forall s \in P:\ \operatorname{zix}_h(s.y) < n) \Rightarrow \sum_{z<n} \operatorname{zrec}_{h,w}(P, z).\mathrm{counts}[j] = \sum_{s \in P} s.\mathrm{row}[j]$$
-/
theorem zoneRec_partition (h w : Nat) (ps : List Step) (n : Nat) (j : Nat) (hj : j < w)
    (hb : ∀ s ∈ ps, zoneIx h s.y < n) :
    sumBy (fun z => valAt (zoneRec h w ps z).counts j) (List.range n) = sumBy (fun s => valAt s.row j) ps := by
  have hc : ∀ z ∈ List.range n, valAt (zoneRec h w ps z).counts j =
      sumBy (fun s => valAt s.row j) (ps.filter (zoneIx h ·.y == z)) := by
    intro z _
    simp only [valAt, zoneRec]
    rw [List.getD_eq_getElem?_getD, List.getElem?_map, List.getElem?_range hj]
    rfl
  rw [sumBy_congr hc]
  exact sum_partition_range (fun s => zoneIx h s.y) _ n ps hb

/-- **Paired steps of A land in the aligned zones.** The zone index of a step paired from A is below the zone count.

$$\forall s \in P(A, B).\;\; \lfloor s.y / h \rfloor < N_h(A, B)$$
-/
theorem paired_bound (h : Nat) (a b : List Step) : ∀ s ∈ pairedSteps a b, zoneIx h s.y < alignCount h a b := by
  intro s hs
  have := zoneIx_lt h a s ((pairedSteps_sublist a b).subset hs)
  unfold alignCount; omega

/-- **Zone partition (run A).** For every column `j < w`, the aligned zones' A sums add up to the sum over
the paired steps of A.

$$\sum_{z < N} \mathrm{countsA}_z[j] = \sum_{s \in P(A,B)} s.\mathrm{row}[j]$$
-/
theorem align_partition_a (h w : Nat) (a b : List Step) (j : Nat) (hj : j < w) :
    sumBy (fun z => valAt z.countsA j) (align h w a b) = sumBy (fun s => valAt s.row j) (pairedSteps a b) := by
  simp only [align, sumBy_map]
  exact zoneRec_partition h w (pairedSteps a b) (alignCount h a b) j hj (paired_bound h a b)

/-- **Paired steps of B land in the aligned zones.** The same for the steps paired from B.

$$\forall s \in P(B, A).\;\; \lfloor s.y / h \rfloor < N_h(A, B)$$
-/
theorem paired_bound' (h : Nat) (a b : List Step) : ∀ s ∈ pairedSteps b a, zoneIx h s.y < alignCount h a b := by
  intro s hs
  have := zoneIx_lt h b s ((pairedSteps_sublist b a).subset hs)
  unfold alignCount; omega

/-- **Zone partition (run B).** The same for run B.

$$\sum_{z < N} \mathrm{countsB}_z[j] = \sum_{s \in P(B,A)} s.\mathrm{row}[j]$$
-/
theorem align_partition_b (h w : Nat) (a b : List Step) (j : Nat) (hj : j < w) :
    sumBy (fun z => valAt z.countsB j) (align h w a b) = sumBy (fun s => valAt s.row j) (pairedSteps b a) := by
  simp only [align, sumBy_map]
  exact zoneRec_partition h w (pairedSteps b a) (alignCount h a b) j hj (paired_bound' h a b)

/-- **The sum of a difference is the difference of the sums.**

$$\sum_{x \in l} (f(x) - g(x)) = \sum_{x \in l} f(x) - \sum_{x \in l} g(x)$$
-/
theorem sumBy_sub {α : Type} (f g : α → Int) : ∀ l : List α, sumBy (fun x => f x - g x) l = sumBy f l - sumBy g l
  | [] => rfl
  | x :: xs => by simp only [sumBy]; rw [sumBy_sub f g xs]; omega

/-- **Reading a tabulated list at an index inside it.** Entry `j` of `[f(0), …, f(w-1)]` is `f(j)`.

$$j < w \;\Rightarrow\; [f(i)]_{i<w}\,[j] = f(j)$$
-/
theorem valAt_map_range (f : Nat → Int) (w j : Nat) (hj : j < w) : valAt ((List.range w).map f) j = f j := by
  simp only [valAt]
  rw [List.getD_eq_getElem?_getD, List.getElem?_map, List.getElem?_range hj]
  rfl

/-- **The delta is the difference.** Over any set of aligned zones, column `j` of the deltas sums to the A sums
minus the B sums.

$$j < w:\ \sum_{z \in Z} \Delta_z[j] = \sum_{z \in Z} \mathrm{countsA}_z[j] - \sum_{z \in Z} \mathrm{countsB}_z[j]$$
-/
theorem align_delta_total (h w : Nat) (a b : List Step) (j : Nat) (hj : j < w) (keep : AZone → Bool) :
    sumBy (fun z => valAt z.delta j) ((align h w a b).filter keep) =
      sumBy (fun z => valAt z.countsA j) ((align h w a b).filter keep) -
      sumBy (fun z => valAt z.countsB j) ((align h w a b).filter keep) := by
  rw [← sumBy_sub]
  apply sumBy_congr
  intro z hz
  have hz' : z ∈ align h w a b := (List.mem_filter.mp hz).1
  simp only [align, List.mem_map] at hz'
  obtain ⟨n, _, rfl⟩ := hz'
  simp only [alignZone]
  exact valAt_map_range _ w j hj

/-- **Swapping the arms.** Aligning B against A gives the swapped zones of aligning A against B.

$$\operatorname{align}(B, A) = [\operatorname{swap}(z)]_{z \in \operatorname{align}(A, B)}$$
-/
theorem align_swap (h w : Nat) (a b : List Step) : align h w b a = (align h w a b).map AZone.swap := by
  have hc : alignCount h b a = alignCount h a b := by unfold alignCount; omega
  simp only [align, List.map_map, hc]
  apply List.map_congr_left
  intro z _
  simp only [Function.comp, alignZone, AZone.swap, AZone.mk.injEq]
  refine ⟨trivial, trivial, trivial, trivial, trivial, trivial, trivial, trivial, ?_, trivial, trivial, (by omega), ?_⟩
  · rw [List.map_map]; apply List.map_congr_left; intro j _; simp only [Function.comp]; omega
  · apply decide_eq_decide.mpr; omega

/-- **A zone never has more paired steps than steps.**

$$|P(A,B)_z| \le |A_z|$$
-/
theorem paired_le_steps (h : Nat) (a b : List Step) (z : Nat) :
    (zoneSteps h (pairedSteps a b) z).length ≤ (zoneSteps h a z).length :=
  ((pairedSteps_sublist a b).filter _).length_le

/-- When a sublist keeps every step of a zone, its zone record is the whole run's.

$$P \sqsubseteq A,\ |P_z| = |A_z| \Rightarrow \operatorname{zrec}_{h,w}(P, z) = \operatorname{zrec}_{h,w}(A, z)$$
-/
theorem zoneRec_of_full (h w : Nat) (ps a : List Step) (z : Nat) (hs : ps.Sublist a)
    (hl : (zoneSteps h ps z).length = (zoneSteps h a z).length) : zoneRec h w ps z = zoneRec h w a z := by
  have heq : zoneSteps h ps z = zoneSteps h a z := (hs.filter _).eq_of_length hl
  simp only [zoneRec]
  rw [heq]

/-- **A full zone loses nothing.** In a full zone the aligned A sums are the plain zone sums of A.

$$\mathrm{full}_z \Rightarrow \mathrm{countsA}_z = \operatorname{zrec}_{h,w}(A, z).\mathrm{counts} \wedge \mathrm{areaA}_z = \operatorname{zrec}_{h,w}(A, z).\mathrm{area}$$
-/
theorem full_counts_a (h w : Nat) (a b : List Step) (z : Nat) (hf : (alignZone h w a b z).full = true) :
    (alignZone h w a b z).countsA = (zoneRec h w a z).counts ∧
    (alignZone h w a b z).areaA = (zoneRec h w a z).paintArea := by
  simp only [alignZone, decide_eq_true_eq] at hf ⊢
  have := zoneRec_of_full h w (pairedSteps a b) a z (pairedSteps_sublist a b) (by
    have h3 := hf.2.2.1
    simp only [zoneRec] at h3 ⊢
    omega)
  rw [this]
  exact ⟨rfl, rfl⟩

/-- **A full zone loses nothing (run B).**

$$\mathrm{full}_z \Rightarrow \mathrm{countsB}_z = \operatorname{zrec}_{h,w}(B, z).\mathrm{counts} \wedge \mathrm{areaB}_z = \operatorname{zrec}_{h,w}(B, z).\mathrm{area}$$
-/
theorem full_counts_b (h w : Nat) (a b : List Step) (z : Nat) (hf : (alignZone h w a b z).full = true) :
    (alignZone h w a b z).countsB = (zoneRec h w b z).counts ∧
    (alignZone h w a b z).areaB = (zoneRec h w b z).paintArea := by
  simp only [alignZone, decide_eq_true_eq] at hf ⊢
  have := zoneRec_of_full h w (pairedSteps b a) b z (pairedSteps_sublist b a) (by
    have h3 := hf.2.2.2
    simp only [zoneRec] at h3 ⊢
    omega)
  rw [this]
  exact ⟨rfl, rfl⟩

/-- **A run aligned with itself is all full and has no delta.** Every zone with steps is full, the A and B sums
are equal and the deltas are 0.

$$\forall z \in \operatorname{align}(A, A):\ \mathrm{countsA}_z = \mathrm{countsB}_z \wedge \Delta_z = 0 \wedge (|A_z| > 0 \Rightarrow \mathrm{full}_z)$$
-/
theorem align_self (h w : Nat) (a : List Step) :
    ∀ x ∈ align h w a a, x.countsA = x.countsB ∧ x.delta = List.replicate w 0 ∧ x.areaDelta = 0 ∧
      (0 < x.stepsA → x.full = true) := by
  intro x hx
  simp only [align, List.mem_map] at hx
  obtain ⟨z, _, rfl⟩ := hx
  simp only [alignZone, pairedSteps_self]
  refine ⟨trivial, ?_, by omega, ?_⟩
  · simp only [Int.sub_self]; rw [List.map_const']; simp
  · intro hp
    simp [hp, zoneRec]

/-- Column sums over a list of aligned zones, for the columns `0 … w-1` of a per-zone vector.

$$\operatorname{col}_w(f, Z) = \Big[\sum_{z \in Z} f(z)[j]\Big]_{j < w}$$
-/
def colSum (w : Nat) (f : AZone → List Int) (zs : List AZone) : List Int :=
  (List.range w).map fun j => sumBy (fun z => valAt (f z) j) zs

end Fw.Measure.StepAlign
