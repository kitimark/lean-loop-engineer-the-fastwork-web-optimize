import Fw.Measure.Offscreen

/-!
# Zone verdict of the WebKit Simulator scroll lane

The verdict of `Fw.Measure.Offscreen` (cmp, judge) over the per-step counters of the `webkit-sim` passes, one scroll
window at a time. A window is the steps whose scroll y lies in `[lo, hi]`. Passes are comparable only when they hold the
same steps in the window: the page end is y 5231 in a 106-step pass and y 5267 in a 107-step pass, so a window that
reaches the end mixes step sets and gets no verdict (`noData`).
-/
namespace Fw.Measure.OffscreenWebKit
open Fw.Measure.Offscreen

/-- The counters of a step row, in the order of `countTypes` of the pass file. -/
def wkKeys : List String :=
  ["RecalculateStyles", "Layout", "Paint", "Composite", "RenderingFrame", "FireAnimationFrame", "TimerFire",
   "ObserverCallback", "EventDispatch", "FunctionCall", "ScheduleStyleRecalculation", "InvalidateLayout"]

/-- One scroll pass: the scroll y of each step and the counter row of each step (a short row reads 0). -/
structure Pass where
  ys : List Nat
  rows : List (List Nat)
deriving Repr, DecidableEq

/-- A window of scroll positions, both ends included. -/
structure Zone where
  name : String
  lo : Nat
  hi : Nat
deriving Repr, DecidableEq

/-- The window stops here: passes end at y 5231 or 5267, so nothing from 5201 on is compared. -/
def endCut : Nat := 5200

/-- The zones the lane reports: two 500 px zones of the end, the finish (both) and the whole run, all cut at `endCut`. -/
def zones : List Zone :=
  [⟨"z4500", 4500, 4950⟩, ⟨"z5000", 5000, endCut⟩, ⟨"finish", 4500, endCut⟩, ⟨"whole", 0, endCut⟩]

/-- Which steps of the pass lie in `[lo, hi]`. -/
def mask (lo hi : Nat) (p : Pass) : List Bool := p.ys.map fun y => decide (lo ≤ y ∧ y ≤ hi)

/-- The scroll positions of the steps in the window. -/
def windowSteps (lo hi : Nat) (p : Pass) : List Nat := p.ys.filter fun y => decide (lo ≤ y ∧ y ≤ hi)

/-- The column of counter number `i` over the steps. -/
def col (p : Pass) (i : Nat) : List Nat := p.rows.map fun r => r.getD i 0

/-- One pass's window: its step count and, per counter, the sum over the window's steps. -/
def windowVec (lo hi : Nat) (p : Pass) : Vec :=
  { n := (mask lo hi p).count true,
    vals := (List.range wkKeys.length).filterMap fun i => (wkKeys[i]?).map fun k => (k, sumWhere (mask lo hi p) (col p i)) }

/-- Every pass has as many rows as steps. -/
def shaped (p : Pass) : Bool := p.ys.length == p.rows.length

/-- Every pass holds the same steps in the window (equal step sets, not only equal counts), and there is a pass. -/
def sameSteps (lo hi : Nat) : List Pass → Bool
  | [] => false
  | p :: ps => ps.all fun q => windowSteps lo hi q == windowSteps lo hi p

/-- Enough passes per arm, well-shaped rows, equal step sets, a non-empty window. -/
def usable (lo hi : Nat) (base flag : List Pass) : Bool :=
  decide (minRuns ≤ base.length) && decide (minRuns ≤ flag.length) && (base ++ flag).all shaped &&
    sameSteps lo hi (base ++ flag) && sameWindow ((base ++ flag).map (windowVec lo hi))

/-- The verdict of a flag arm against the base on one window: `Offscreen.judge` over the counters, or no data. -/
def verdict (lo hi : Nat) (base flag : List Pass) : Verdict :=
  if usable lo hi base flag then
    judge (wkKeys.filterMap (cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi))))
  else .noData

/-- Each zone judged on its own. -/
def zoneVerdicts (base flag : List Pass) : List (String × Verdict) :=
  zones.map fun z => (z.name, verdict z.lo z.hi base flag)

theorem count_map_eq_length_filter (q : Nat → Bool) : ∀ ys : List Nat, (ys.map q).count true = (ys.filter q).length
  | [] => rfl
  | y :: ys => by
    have ih := count_map_eq_length_filter q ys
    cases hq : q y <;> simp [hq, ih]

theorem windowVec_n (lo hi : Nat) (p : Pass) : (windowVec lo hi p).n = (windowSteps lo hi p).length :=
  count_map_eq_length_filter _ p.ys

/-- Passes with equal step sets in a non-empty window have the same window length. -/
theorem sameWindow_of_sameSteps (lo hi : Nat) (ps : List Pass) (h : sameSteps lo hi ps = true)
    (hne : ∀ p ∈ ps, windowSteps lo hi p ≠ []) : sameWindow (ps.map (windowVec lo hi)) = true := by
  cases ps with
  | nil => simp [sameSteps] at h
  | cons p ps =>
    simp only [sameSteps, List.all_eq_true, beq_iff_eq] at h
    have hp : windowSteps lo hi p ≠ [] := hne p (List.mem_cons_self ..)
    simp only [List.map_cons, sameWindow, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true, List.mem_map,
      beq_iff_eq]
    refine ⟨?_, ?_⟩
    · rw [windowVec_n]
      exact List.length_pos_iff.2 hp
    · rintro _ ⟨q, hq, rfl⟩
      rw [windowVec_n, windowVec_n, h q hq]

/-- **A mismatch of step sets gives no verdict**: when two passes hold different steps in the window, the verdict is
`noData`, so a window that reaches the end of a 106-step and a 107-step pass is never judged. -/
theorem noData_of_steps (lo hi : Nat) (base flag : List Pass) (h : sameSteps lo hi (base ++ flag) = false) :
    verdict lo hi base flag = .noData := by
  simp [verdict, usable, h]

theorem noData_of_fewBase (lo hi : Nat) (base flag : List Pass) (h : base.length < minRuns) :
    verdict lo hi base flag = .noData := by
  have : ¬ minRuns ≤ base.length := by omega
  simp [verdict, usable, this]

theorem noData_of_fewFlag (lo hi : Nat) (base flag : List Pass) (h : flag.length < minRuns) :
    verdict lo hi base flag = .noData := by
  have : ¬ minRuns ≤ flag.length := by omega
  simp [verdict, usable, this]

theorem noData_of_unshaped (lo hi : Nat) (base flag : List Pass) (h : (base ++ flag).all shaped = false) :
    verdict lo hi base flag = .noData := by
  simp [verdict, usable, h]

/-- A usable window gets the `Offscreen.judge` of its counters. -/
theorem verdict_of_usable (lo hi : Nat) (base flag : List Pass) (h : usable lo hi base flag = true) :
    verdict lo hi base flag =
      judge (wkKeys.filterMap (cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi)))) := by
  simp [verdict, h]

/-- A verdict other than `noData` came from a usable window. -/
theorem usable_of_verdict (lo hi : Nat) (base flag : List Pass) (h : verdict lo hi base flag ≠ .noData) :
    usable lo hi base flag = true := by
  cases hu : usable lo hi base flag
  · exact absurd (by simp [verdict, hu]) h
  · rfl

/-- A counter above the base's in a usable window makes the arm `noGain`. -/
theorem noGain_of_more (lo hi : Nat) (base flag : List Pass) (k : String) (hu : usable lo hi base flag = true)
    (hk : k ∈ wkKeys) (hm : cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi)) k = some .more) :
    verdict lo hi base flag = .noGain := by
  rw [verdict_of_usable lo hi base flag hu]
  exact judge_more _ (List.mem_filterMap.2 ⟨k, hk, hm⟩)

/-- A gain names a counter whose every flag pass is below every base pass, and no counter is above. -/
theorem gain_sound (lo hi : Nat) (base flag : List Pass) (h : verdict lo hi base flag = .gain) :
    usable lo hi base flag = true ∧
      (∃ k ∈ wkKeys, cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi)) k = some .less) ∧
      ∀ j ∈ wkKeys, cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi)) j ≠ some .more := by
  have hu : usable lo hi base flag = true := usable_of_verdict lo hi base flag (by rw [h]; simp)
  rw [verdict_of_usable lo hi base flag hu] at h
  obtain ⟨hl, hm⟩ := judge_gain_inv _ h
  refine ⟨hu, ?_, fun j hj hjm => hm (List.mem_filterMap.2 ⟨j, hj, hjm⟩)⟩
  obtain ⟨k, hk, hkm⟩ := List.mem_filterMap.1 hl
  exact ⟨k, hk, hkm⟩

/-- A step above the cut is in no window that ends at the cut. -/
theorem not_mem_windowSteps_of_gt (lo hi y : Nat) (p : Pass) (h : hi < y) : y ∉ windowSteps lo hi p := by
  intro hm
  have := (List.mem_filter.1 hm).2
  simp only [decide_eq_true_eq] at this
  omega

/-- The page-end steps of both pass shapes (y 5231 and y 5267) lie outside every zone. -/
theorem end_steps_outside (z : Zone) (hz : z ∈ zones) (p : Pass) :
    5231 ∉ windowSteps z.lo z.hi p ∧ 5267 ∉ windowSteps z.lo z.hi p := by
  have : z.hi ≤ endCut := by
    simp only [zones, List.mem_cons, List.not_mem_nil, or_false] at hz
    rcases hz with rfl | rfl | rfl | rfl <;> simp [endCut]
  exact ⟨not_mem_windowSteps_of_gt _ _ _ _ (by simp [endCut] at this ⊢; omega),
    not_mem_windowSteps_of_gt _ _ _ _ (by simp [endCut] at this ⊢; omega)⟩

end Fw.Measure.OffscreenWebKit
