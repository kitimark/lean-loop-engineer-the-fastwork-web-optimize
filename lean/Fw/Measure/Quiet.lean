import Fw.Measure.WebKit
/-!
# Quiet steps of the WebKit lane (task webkit-quiet)

The Simulator shares a three-core CI VM with everything else, so a scroll step can take much longer
than the two animation frames it waits for. The harness records the duration of every step (the
distance between its two `wk:s<k>` marks, in whole microseconds). A step is **quiet** when it ran
quickly in every pass: `d[r][k] ≤ L` for every pass `r` (the limit `L` is a policy value, chosen from
the measured durations, never from the counts). The per-step classes are then computed over the
quiet steps only (`classifyQuiet`), and the verdict carries how many steps that left
(`Verdict.kept`), so a class is never quoted without its coverage.

Steps are aligned by index over the first `n` steps, `n` the shortest pass (a pass may have one
step more when the page is a little longer: the last, partial step is not compared).

Proved: the quiet steps are exactly the steps below `n` that are fast in every pass
(`mem_quietSteps`); restricting to any list of steps gives `maxOf` of that step's cell statuses
(`classifyCells_restrict`); hence **leaving steps out never makes the class stricter**
(`classifyQuiet_le`), a larger limit keeps more steps and never gives a better class
(`classifyQuiet_mono`), and a limit above every duration reproduces the plain class
(`classifyQuiet_all`). The class is a statement about the kept steps only.
-/
namespace Fw.Measure.Quiet
open Fw.Measure Fw.Measure.WebKit

/-- The number of steps compared: the shortest pass.

(`n = 0` for no passes)
-/
def stepCount (durs : List (List Nat)) : Nat :=
  match durs with
  | [] => 0
  | d :: ds => ds.foldl (fun m e => min m e.length) d.length

#guard stepCount [[1, 2, 3], [4, 5]] == 2 && stepCount [] == 0 && stepCount [[1], [1], [1]] == 1

/-- Step `k` is quiet at limit `L`: every pass took at most `L` there. -/
def quietAt (L : Nat) (durs : List (List Nat)) (k : Nat) : Bool :=
  durs.all fun d => decide (d.getD k 0 ≤ L)

/-- The quiet steps, in order. -/
def quietSteps (L : Nat) (durs : List (List Nat)) : List Nat :=
  (List.range (stepCount durs)).filter (quietAt L durs)

#guard quietSteps 10 [[5, 20, 7], [9, 3, 11]] == [0]
#guard quietSteps 10 [[5, 20, 7], [9, 3]] == [0]
#guard quietSteps 20 [[5, 20, 7], [9, 3, 11]] == [0, 1, 2]
#guard quietSteps 0 [[5, 20, 7]] == []

/-- The series restricted to the listed steps (0 past the end, like `valAt`). -/
def restrict (idx : List Nat) (s : Series) : Series := idx.map (valAt s)

/-- **The class over the quiet steps**: the cell-spread class of the runs restricted to `Q_L`. -/
def classifyQuiet (tol : Tol) (L : Nat) (durs : List (List Nat)) (runs : List Series) : Nat :=
  classifyCells tol (runs.map (restrict (quietSteps L durs)))

/-- A quiet-step verdict: the class over the kept steps, and how many steps were kept out of how
many (the `none` case for too few quiet steps belongs to `verdict`).
-/
structure Verdict where
  cls : Nat
  kept : Nat
  total : Nat
deriving Repr, DecidableEq

/-- The verdict of one series family at limit `L` with at least `minKept` kept steps. -/
def verdict (tol : Tol) (L minKept : Nat) (durs : List (List Nat)) (runs : List Series) : Option Verdict :=
  let q := quietSteps L durs
  if q.length < minKept then none
  else some { cls := classifyQuiet tol L durs runs, kept := q.length, total := stepCount durs }

#guard (verdict ⟨1, 0⟩ 10 1 [[5, 20, 7], [9, 3, 11]] [[1, 2, 3], [1, 9, 3]]).map (·.cls) == some 0
#guard (verdict ⟨1, 0⟩ 30 1 [[5, 20, 7], [9, 3, 11]] [[1, 2, 3], [1, 9, 3]]).map (·.cls) == some 2
#guard (verdict ⟨1, 0⟩ 10 2 [[5, 20, 7], [9, 3, 11]] [[1, 2, 3], [1, 9, 3]]) == none

/-! ## The quiet steps -/

/-- **Membership.** A step is kept iff it is below the shortest pass and fast in every pass. -/
theorem mem_quietSteps (L : Nat) (durs : List (List Nat)) (k : Nat) :
    k ∈ quietSteps L durs ↔ k < stepCount durs ∧ ∀ d ∈ durs, d.getD k 0 ≤ L := by
  simp [quietSteps, quietAt, List.mem_filter, List.mem_range, List.all_eq_true]

/-- **A larger limit keeps more steps.** -/
theorem quietSteps_mono {L L' : Nat} (h : L ≤ L') (durs : List (List Nat)) :
    ∀ k ∈ quietSteps L durs, k ∈ quietSteps L' durs := by
  intro k hk
  rw [mem_quietSteps] at hk ⊢
  exact ⟨hk.1, fun d hd => Nat.le_trans (hk.2 d hd) h⟩

/-- **A limit above every duration keeps every compared step.** -/
theorem quietSteps_all {L : Nat} {durs : List (List Nat)} (h : ∀ d ∈ durs, ∀ k, d.getD k 0 ≤ L) :
    quietSteps L durs = List.range (stepCount durs) := by
  simp only [quietSteps]
  apply List.filter_eq_self.mpr
  intro k _
  simp only [quietAt, List.all_eq_true, decide_eq_true_eq]
  exact fun d hd => h d hd k

/-! ## Restricting the runs -/

/-- The value of a restricted series at position `i` is the original at the `i`-th kept step. -/
theorem valAt_restrict (idx : List Nat) (s : Series) (i : Nat) (hi : i < idx.length) :
    valAt (restrict idx s) i = valAt s (idx.getD i 0) := by
  simp [restrict, valAt, List.getD_eq_getElem?_getD, List.getElem?_map, List.getElem?_eq_getElem hi]

/-- **Restricting a family of runs.** The class of the restricted runs is the worst status of
the cells at the listed steps (all runs restricted to the same steps have the same length).
-/
theorem classifyCells_restrict (tol : Tol) (idx : List Nat) (runs : List Series) :
    classifyCells tol (runs.map (restrict idx)) =
      maxOf (idx.map fun k => cellStatus tol (cellVals runs k)) := by
  have hzero : cellStatus tol [] = 0 := by simp [cellStatus, stats]
  cases runs with
  | nil =>
    have h0 : maxOf (idx.map fun k => cellStatus tol (cellVals ([] : List Series) k)) = 0 := by
      apply Nat.le_antisymm _ (Nat.zero_le _)
      apply maxOf_le
      intro x hx
      simp only [List.mem_map] at hx
      obtain ⟨k, _, rfl⟩ := hx
      simp [cellVals, hzero]
    rw [h0]
    simp [classifyCells, maxOf]
  | cons r rs =>
    have hlen : ∀ x ∈ (r :: rs).map (restrict idx), x.length = idx.length := by
      intro x hx
      simp only [List.mem_map] at hx
      obtain ⟨y, _, rfl⟩ := hx
      simp [restrict]
    have hrl : (restrict idx r).length = idx.length := by simp [restrict]
    have hany : ((r :: rs).map (restrict idx)).any
        (·.length != (((r :: rs).map (restrict idx)).headD []).length) = false := by
      simp only [List.any_eq_false]
      intro x hx
      simp [hlen x hx, hrl]
    have hcells : (List.range idx.length).map
        (fun i => cellStatus tol (cellVals ((r :: rs).map (restrict idx)) i)) =
        idx.map fun k => cellStatus tol (cellVals (r :: rs) k) := by
      apply List.ext_getElem
      · simp
      · intro i h1 h2
        simp only [List.getElem_map, List.getElem_range]
        have hi : i < idx.length := by simpa using h1
        congr 1
        simp only [cellVals, List.map_map]
        apply List.map_congr_left
        intro x _
        simp only [Function.comp]
        rw [valAt_restrict idx x i hi]
        simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi]
    have hh : ((r :: rs).map (restrict idx)).headD [] = restrict idx r := rfl
    unfold classifyCells
    dsimp only
    rw [hany]
    simp only [Bool.false_eq_true, ite_false, hh, hrl]
    rw [hcells]

/-- **More steps, no better class.** Restricting to fewer steps never makes the class stricter. -/
theorem classifyCells_restrict_mono (tol : Tol) {idx idx' : List Nat} (h : ∀ k ∈ idx, k ∈ idx')
    (runs : List Series) :
    classifyCells tol (runs.map (restrict idx)) ≤ classifyCells tol (runs.map (restrict idx')) := by
  rw [classifyCells_restrict, classifyCells_restrict]
  apply maxOf_le
  intro x hx
  simp only [List.mem_map] at hx
  obtain ⟨k, hk, rfl⟩ := hx
  exact le_maxOf (List.mem_map.mpr ⟨k, h k hk, rfl⟩)

/-- **A larger limit never gives a better class.** A larger limit keeps more steps, so the class
over them is at least as strict.
-/
theorem classifyQuiet_mono (tol : Tol) {L L' : Nat} (h : L ≤ L') (durs : List (List Nat))
    (runs : List Series) : classifyQuiet tol L durs runs ≤ classifyQuiet tol L' durs runs :=
  classifyCells_restrict_mono tol (quietSteps_mono h durs) runs

/-- Restricting a series of exactly `n` values to the first `n` steps changes nothing. -/
theorem restrict_range (s : Series) (n : Nat) (h : s.length = n) : restrict (List.range n) s = s := by
  apply List.ext_getElem
  · simp [restrict, h]
  · intro i h1 h2
    have hi : i < n := by simpa [restrict] using h1
    simp [restrict, valAt, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem h2]

/-- **Leaving steps out never makes the class stricter.** For runs of exactly the compared number of
steps, the class over the quiet steps is at most the plain class.
-/
theorem classifyQuiet_le (tol : Tol) (L : Nat) (durs : List (List Nat)) (runs : List Series)
    (hn : ∀ r ∈ runs, r.length = stepCount durs) :
    classifyQuiet tol L durs runs ≤ classifyCells tol runs := by
  have hsub : ∀ k ∈ quietSteps L durs, k ∈ List.range (stepCount durs) := by
    intro k hk
    exact List.mem_range.mpr ((mem_quietSteps L durs k).1 hk).1
  have hid : runs.map (restrict (List.range (stepCount durs))) = runs := by
    conv => rhs; rw [← List.map_id runs]
    exact List.map_congr_left fun r hr => restrict_range r _ (hn r hr)
  have := classifyCells_restrict_mono tol hsub runs
  rw [hid] at this
  exact this

/-- **A limit above every duration reproduces the plain class.** -/
theorem classifyQuiet_all (tol : Tol) {L : Nat} {durs : List (List Nat)} (runs : List Series)
    (hd : ∀ d ∈ durs, ∀ k, d.getD k 0 ≤ L) (hn : ∀ r ∈ runs, r.length = stepCount durs) :
    classifyQuiet tol L durs runs = classifyCells tol runs := by
  simp only [classifyQuiet, quietSteps_all hd]
  have hid : runs.map (restrict (List.range (stepCount durs))) = runs := by
    conv => rhs; rw [← List.map_id runs]
    exact List.map_congr_left fun r hr => restrict_range r _ (hn r hr)
  rw [hid]

end Fw.Measure.Quiet
