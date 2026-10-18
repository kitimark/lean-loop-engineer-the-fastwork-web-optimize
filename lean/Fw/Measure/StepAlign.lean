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

/-- Steps paired with their keys, given the offset `p` before the first step.

$$\operatorname{keyedFrom}(p,[\,])=[\,],\quad \operatorname{keyedFrom}(p,[s])=[((p,s.y,\bot),s)],\quad \operatorname{keyedFrom}(p,s::t::r)=((p,s.y,t.y),s)::\operatorname{keyedFrom}(s.y,t::r)$$
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

$$\begin{aligned}
\operatorname{azone}_{h,w}(A,B,z) &= (z,\ zh,\ |A_z|,\ |B_z|,\ |P(A,B)_z|,\ |P(B,A)_z|,\ c_A,\ c_B,\ [c_A[j]-c_B[j]]_{j<w},\ a_A,\ a_B,\ a_A-a_B,\ \mathrm{full}_z)\\
c_A &= \operatorname{zrec}_{h,w}(P(A,B),z).\mathrm{counts},\quad a_A = \operatorname{zrec}_{h,w}(P(A,B),z).\mathrm{area}\quad (c_B, a_B \text{ likewise from } P(B,A))\\
\mathrm{full}_z &\iff |A_z| > 0 \wedge |A_z| = |B_z| \wedge |A_z| = |P(A,B)_z| \wedge |B_z| = |P(B,A)_z|
\end{aligned}$$

Here $|A_z|$ counts the steps of $A$ in zone $z$, $|P(A,B)_z|$ is the step count of the zone record, and $c[j]$
reads a missing entry as $0$.
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

$$\forall s \in P(A, B):\ \operatorname{zix}_h(s.y) < N_h(A, B)$$

Here $\operatorname{zix}_h(y) = \max(0, \lfloor y/h \rfloor)$ with $y/0 = 0$.
-/
theorem paired_bound (h : Nat) (a b : List Step) : ∀ s ∈ pairedSteps a b, zoneIx h s.y < alignCount h a b := by
  intro s hs
  have := zoneIx_lt h a s ((pairedSteps_sublist a b).subset hs)
  unfold alignCount; omega

/-- **Zone partition (run A).** For every column `j < w`, the aligned zones' A sums add up to the sum over
the paired steps of A.

$$\forall j < w:\ \sum_{z \in \operatorname{align}_{h,w}(A,B)} \mathrm{countsA}_z[j] = \sum_{s \in P(A,B)} s.\mathrm{row}[j]$$
-/
theorem align_partition_a (h w : Nat) (a b : List Step) (j : Nat) (hj : j < w) :
    sumBy (fun z => valAt z.countsA j) (align h w a b) = sumBy (fun s => valAt s.row j) (pairedSteps a b) := by
  simp only [align, sumBy_map]
  exact zoneRec_partition h w (pairedSteps a b) (alignCount h a b) j hj (paired_bound h a b)

/-- **Paired steps of B land in the aligned zones.** The same for the steps paired from B.

$$\forall s \in P(B, A):\ \operatorname{zix}_h(s.y) < N_h(A, B)$$

Here $\operatorname{zix}_h(y) = \max(0, \lfloor y/h \rfloor)$ with $y/0 = 0$.
-/
theorem paired_bound' (h : Nat) (a b : List Step) : ∀ s ∈ pairedSteps b a, zoneIx h s.y < alignCount h a b := by
  intro s hs
  have := zoneIx_lt h b s ((pairedSteps_sublist b a).subset hs)
  unfold alignCount; omega

/-- **Zone partition (run B).** The same for run B.

$$\forall j < w:\ \sum_{z \in \operatorname{align}_{h,w}(A,B)} \mathrm{countsB}_z[j] = \sum_{s \in P(B,A)} s.\mathrm{row}[j]$$
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

$$\forall z \in \operatorname{align}_{h,w}(A, A):\ \mathrm{countsA}_z = \mathrm{countsB}_z \wedge \Delta_z = [0]^w \wedge \mathrm{areaDelta}_z = 0 \wedge (\mathrm{stepsA}_z > 0 \Rightarrow \mathrm{full}_z)$$
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


/-! ## Rows across sessions (the `merge` of the class tables)

`merge` takes the class table of every session and keeps the worse class per row. A row is named by its
key (family, count type, level, e.g. `census|layerCount|y=5268`); some keys depend on the page (the census
states are labelled by the offset the browser measured, and the document height differs by a pixel on some
VMs). A row is **paired** when every session has it; a row some sessions lack is **unpaired**, is reported
with the number of sessions that have it and is left out of the merged table. -/

/-- Whether every session has a row with this key.

$$\operatorname{inAll}(\mathcal{S}, \kappa) \iff \forall S \in \mathcal{S}:\ \kappa \in S$$
-/
def inAll (ss : List (List String)) (k : String) : Bool := ss.all (·.contains k)

/-- The paired rows: the keys of the first session, in its order, that every session has (none for no sessions).

$$\operatorname{paired}([\,]) = [\,],\qquad \operatorname{paired}(S_1 :: \mathcal{R}) = [\, \kappa \in S_1 \mid \operatorname{inAll}(S_1 :: \mathcal{R}, \kappa) \,]$$
-/
def pairedRows : List (List String) → List String
  | [] => []
  | s :: rest => s.filter (inAll (s :: rest))

/-- How many sessions have a row with this key; a session listed twice counts twice.

$$\operatorname{count}(\mathcal{S}, \kappa) = \big|[\, S \in \mathcal{S} \mid \kappa \in S \,]\big|$$
-/
def sessionsWith (ss : List (List String)) (k : String) : Nat := (ss.filter (·.contains k)).length

/-- The unpaired rows with the number of sessions that have them, each key once, in order of first appearance.

$$\operatorname{unpaired}(\mathcal{S}) = [\, (\kappa, \operatorname{count}(\mathcal{S}, \kappa)) \mid \kappa \in \operatorname{eraseDups}([\, \kappa \in \operatorname{concat}(\mathcal{S}) \mid \neg \operatorname{inAll}(\mathcal{S}, \kappa) \,]) \,]$$

Here $\operatorname{eraseDups}$ keeps the first occurrence of each key.
-/
def unpairedRows (ss : List (List String)) : List (String × Nat) :=
  (ss.flatten.filter (fun k => !inAll ss k)).eraseDups.map fun k => (k, sessionsWith ss k)

#guard pairedRows [["a", "b", "c"], ["b", "a"], ["a", "b", "d"]] == ["a", "b"]
#guard unpairedRows [["a", "b", "c"], ["b", "a"], ["a", "b", "d"]] == [("c", 1), ("d", 1)]

/-- **Paired means in every session.** A key is paired exactly when every session has it.

$$\kappa \in \operatorname{paired}(S_1 :: \mathcal{R}) \iff \forall S \in S_1 :: \mathcal{R}:\ \kappa \in S$$
-/
theorem mem_pairedRows (s : List String) (rest : List (List String)) (k : String) :
    k ∈ pairedRows (s :: rest) ↔ ∀ t ∈ s :: rest, k ∈ t := by
  simp only [pairedRows, List.mem_filter, inAll, List.all_eq_true, List.contains_iff_mem]
  constructor
  · exact fun h => h.2
  · intro h; exact ⟨h s List.mem_cons_self, h⟩

/-- **Unpaired means in some session but not in all.** The keys of the unpaired rows are those some session has and some
session lacks.

$$\kappa \in \operatorname{keys}(\operatorname{unpaired}(\mathcal{S})) \iff (\exists S \in \mathcal{S}:\ \kappa \in S) \wedge (\exists S \in \mathcal{S}:\ \kappa \notin S)$$
-/
theorem mem_unpairedRows (ss : List (List String)) (k : String) :
    k ∈ (unpairedRows ss).map (·.1) ↔ (∃ t ∈ ss, k ∈ t) ∧ (∃ t ∈ ss, k ∉ t) := by
  simp only [unpairedRows, List.map_map, Function.comp_def, List.map_id', List.mem_eraseDups, List.mem_filter,
    List.mem_flatten, inAll, Bool.not_eq_true', List.all_eq_false, List.contains_iff_mem]

/-- **Nothing is dropped silently.** A key that some session has is paired or unpaired, and never both.

$$\big(\exists S \in \mathcal{S}:\ \kappa \in S\big) \Rightarrow \big(\kappa \in \operatorname{paired}(\mathcal{S}) \,\veebar\, \kappa \in \operatorname{keys}(\operatorname{unpaired}(\mathcal{S}))\big)$$
-/
theorem pair_cover (s : List String) (rest : List (List String)) (k : String)
    (h : ∃ t ∈ s :: rest, k ∈ t) :
    (k ∈ pairedRows (s :: rest) ∧ k ∉ (unpairedRows (s :: rest)).map (·.1)) ∨
    (k ∉ pairedRows (s :: rest) ∧ k ∈ (unpairedRows (s :: rest)).map (·.1)) := by
  rw [mem_pairedRows, mem_unpairedRows]
  by_cases hall : ∀ t ∈ s :: rest, k ∈ t
  · left; refine ⟨hall, ?_⟩
    rintro ⟨_, t, ht, hn⟩; exact hn (hall t ht)
  · right
    refine ⟨hall, h, ?_⟩
    exact Classical.byContradiction fun hc =>
      hall (fun t ht => Classical.byContradiction fun hn => hc ⟨t, ht, hn⟩)

/-- **An unpaired row is in at least one session and fewer than all.**

$$(\kappa, n) \in \operatorname{unpaired}(\mathcal{S}) \Rightarrow 1 \le n \wedge n < |\mathcal{S}|$$
-/
theorem unpairedRows_count (ss : List (List String)) (k : String) (n : Nat) (h : (k, n) ∈ unpairedRows ss) :
    1 ≤ n ∧ n < ss.length := by
  have hk := (mem_unpairedRows ss k).1 (List.mem_map.2 ⟨(k, n), h, rfl⟩)
  have hn : n = sessionsWith ss k := by
    simp only [unpairedRows, List.mem_map] at h
    obtain ⟨k', _, he⟩ := h
    simp only [Prod.mk.injEq] at he
    rw [← he.2, he.1]
  subst hn
  obtain ⟨⟨t, ht, hkt⟩, u, hu, hku⟩ := hk
  constructor
  · simp only [sessionsWith]
    exact List.length_pos_of_mem (List.mem_filter.2 ⟨ht, by simpa using hkt⟩)
  · simp only [sessionsWith]
    exact List.length_filter_lt_length_iff_exists.2 ⟨u, hu, by simpa using hku⟩

/-- **Identical sessions pair everything.** `n + 1` copies of one session have all its rows paired and none unpaired.

$$\operatorname{paired}(S^{n+1}) = S \wedge \operatorname{unpaired}(S^{n+1}) = []$$
-/
theorem pair_self (s : List String) (n : Nat) :
    pairedRows (List.replicate (n + 1) s) = s ∧ unpairedRows (List.replicate (n + 1) s) = [] := by
  have hall : ∀ k, inAll (List.replicate (n + 1) s) k = s.contains k := by
    intro k
    simp only [inAll]
    cases hc : s.contains k <;> simp_all
  constructor
  · show List.filter (inAll (List.replicate (n + 1) s)) s = s
    rw [List.filter_eq_self]
    intro k hk; rw [hall]; exact List.contains_iff_mem.2 hk
  · simp only [unpairedRows]
    have : (List.replicate (n + 1) s).flatten.filter (fun k => !inAll (List.replicate (n + 1) s) k) = [] := by
      rw [List.filter_eq_nil_iff]
      intro k hk
      rw [hall]
      have hks : k ∈ s := by simpa [List.mem_flatten, List.mem_replicate] using hk
      rw [List.contains_iff_mem.2 hks]; simp
    simp [this]

end Fw.Measure.StepAlign
