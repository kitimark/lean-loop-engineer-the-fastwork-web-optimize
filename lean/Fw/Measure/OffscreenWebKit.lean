import Fw.Measure.Offscreen

namespace Fw.Measure.OffscreenWebKit
open Fw.Measure.Offscreen

def wkKeys : List String :=
  ["RecalculateStyles", "Layout", "Paint", "Composite", "RenderingFrame", "FireAnimationFrame", "TimerFire",
   "ObserverCallback", "EventDispatch", "FunctionCall", "ScheduleStyleRecalculation", "InvalidateLayout"]

structure Pass where
  vm : Nat
  ys : List Nat
  rows : List (List Nat)
deriving Repr, DecidableEq

structure Zone where
  name : String
  lo : Nat
  hi : Nat
deriving Repr, DecidableEq

def endCut : Nat := 5200

def zones : List Zone :=
  [⟨"z4500", 4500, 4950⟩, ⟨"z5000", 5000, endCut⟩, ⟨"finish", 4500, endCut⟩, ⟨"whole", 0, endCut⟩]

def mask (lo hi : Nat) (p : Pass) : List Bool := p.ys.map fun y => decide (lo ≤ y ∧ y ≤ hi)

def windowSteps (lo hi : Nat) (p : Pass) : List Nat := p.ys.filter fun y => decide (lo ≤ y ∧ y ≤ hi)

def col (p : Pass) (i : Nat) : List Nat := p.rows.map fun r => r.getD i 0

def windowVec (lo hi : Nat) (p : Pass) : Vec :=
  { n := (mask lo hi p).count true,
    vals := (List.range wkKeys.length).filterMap fun i => (wkKeys[i]?).map fun k => (k, sumWhere (mask lo hi p) (col p i)) }

def shaped (p : Pass) : Bool := p.ys.length == p.rows.length

def sameSteps (lo hi : Nat) : List Pass → Bool
  | [] => false
  | p :: ps => ps.all fun q => windowSteps lo hi q == windowSteps lo hi p

def minVms : Nat := 3

def vmCount (ps : List Pass) : Nat := (ps.map (·.vm)).eraseDups.length

def enoughVms (ps : List Pass) : Bool := decide (minVms ≤ vmCount ps)

def undecided (base flag : List Pass) : Bool := !(enoughVms base && enoughVms flag)

def passUsable (lo hi : Nat) (base flag : List Pass) : Bool :=
  decide (minRuns ≤ base.length) && decide (minRuns ≤ flag.length) && (base ++ flag).all shaped &&
    sameSteps lo hi (base ++ flag) && sameWindow ((base ++ flag).map (windowVec lo hi))

def usable (lo hi : Nat) (base flag : List Pass) : Bool :=
  enoughVms base && enoughVms flag && passUsable lo hi base flag

def judged (lo hi : Nat) (base flag : List Pass) : Verdict :=
  judge (wkKeys.filterMap (cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi))))

def passVerdict (lo hi : Nat) (base flag : List Pass) : Verdict :=
  if passUsable lo hi base flag then judged lo hi base flag else .noData

def verdict (lo hi : Nat) (base flag : List Pass) : Verdict :=
  if usable lo hi base flag then judged lo hi base flag else .noData

def zoneVerdicts (base flag : List Pass) : List (String × Verdict) :=
  zones.map fun z => (z.name, verdict z.lo z.hi base flag)

theorem count_map_eq_length_filter (q : Nat → Bool) : ∀ ys : List Nat, (ys.map q).count true = (ys.filter q).length
  | [] => rfl
  | y :: ys => by
    have ih := count_map_eq_length_filter q ys
    cases hq : q y <;> simp [hq, ih]

theorem windowVec_n (lo hi : Nat) (p : Pass) : (windowVec lo hi p).n = (windowSteps lo hi p).length :=
  count_map_eq_length_filter _ p.ys

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

theorem noData_of_steps (lo hi : Nat) (base flag : List Pass) (h : sameSteps lo hi (base ++ flag) = false) :
    verdict lo hi base flag = .noData := by
  simp [verdict, usable, passUsable, h]

theorem noData_of_fewBase (lo hi : Nat) (base flag : List Pass) (h : base.length < minRuns) :
    verdict lo hi base flag = .noData := by
  have : ¬ minRuns ≤ base.length := by omega
  simp [verdict, usable, passUsable, this]

theorem noData_of_fewFlag (lo hi : Nat) (base flag : List Pass) (h : flag.length < minRuns) :
    verdict lo hi base flag = .noData := by
  have : ¬ minRuns ≤ flag.length := by omega
  simp [verdict, usable, passUsable, this]

theorem noData_of_unshaped (lo hi : Nat) (base flag : List Pass) (h : (base ++ flag).all shaped = false) :
    verdict lo hi base flag = .noData := by
  simp [verdict, usable, passUsable, h]

theorem verdict_of_usable (lo hi : Nat) (base flag : List Pass) (h : usable lo hi base flag = true) :
    verdict lo hi base flag =
      judge (wkKeys.filterMap (cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi)))) := by
  simp [verdict, judged, h]

theorem usable_of_verdict (lo hi : Nat) (base flag : List Pass) (h : verdict lo hi base flag ≠ .noData) :
    usable lo hi base flag = true := by
  cases hu : usable lo hi base flag
  · exact absurd (by simp [verdict, hu]) h
  · rfl

theorem noGain_of_more (lo hi : Nat) (base flag : List Pass) (k : String) (hu : usable lo hi base flag = true)
    (hk : k ∈ wkKeys) (hm : cmpKey slack (base.map (windowVec lo hi)) (flag.map (windowVec lo hi)) k = some .more) :
    verdict lo hi base flag = .noGain := by
  rw [verdict_of_usable lo hi base flag hu]
  exact judge_more _ (List.mem_filterMap.2 ⟨k, hk, hm⟩)

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

theorem noData_of_fewVmsBase (lo hi : Nat) (base flag : List Pass) (h : vmCount base < minVms) :
    verdict lo hi base flag = .noData := by
  have : ¬ minVms ≤ vmCount base := by omega
  simp [verdict, usable, enoughVms, this]

theorem noData_of_fewVmsFlag (lo hi : Nat) (base flag : List Pass) (h : vmCount flag < minVms) :
    verdict lo hi base flag = .noData := by
  have : ¬ minVms ≤ vmCount flag := by omega
  simp [verdict, usable, enoughVms, this]

theorem zones_noData_of_fewVmsBase (base flag : List Pass) (h : vmCount base < minVms) :
    ∀ zv ∈ zoneVerdicts base flag, zv.2 = .noData := by
  intro zv hzv
  obtain ⟨z, _, rfl⟩ := List.mem_map.1 hzv
  exact noData_of_fewVmsBase _ _ _ _ h

theorem zones_noData_of_fewVmsFlag (base flag : List Pass) (h : vmCount flag < minVms) :
    ∀ zv ∈ zoneVerdicts base flag, zv.2 = .noData := by
  intro zv hzv
  obtain ⟨z, _, rfl⟩ := List.mem_map.1 hzv
  exact noData_of_fewVmsFlag _ _ _ _ h

theorem fewVms_of_undecided (base flag : List Pass) (h : undecided base flag = true) :
    vmCount base < minVms ∨ vmCount flag < minVms := by
  simp only [undecided, enoughVms, Bool.not_eq_true', Bool.and_eq_false_iff, decide_eq_false_iff_not] at h
  omega

theorem undecided_of_fewVmsBase (base flag : List Pass) (h : vmCount base < minVms) : undecided base flag = true := by
  have : ¬ minVms ≤ vmCount base := by omega
  simp [undecided, enoughVms, this]

theorem undecided_of_fewVmsFlag (base flag : List Pass) (h : vmCount flag < minVms) : undecided base flag = true := by
  have : ¬ minVms ≤ vmCount flag := by omega
  simp [undecided, enoughVms, this]

theorem zones_noData_of_undecided (base flag : List Pass) (h : undecided base flag = true) :
    ∀ zv ∈ zoneVerdicts base flag, zv.2 = .noData := by
  rcases fewVms_of_undecided base flag h with hb | hf
  · exact zones_noData_of_fewVmsBase base flag hb
  · exact zones_noData_of_fewVmsFlag base flag hf

theorem verdict_eq_passVerdict (lo hi : Nat) (base flag : List Pass) (hb : minVms ≤ vmCount base)
    (hf : minVms ≤ vmCount flag) : verdict lo hi base flag = passVerdict lo hi base flag := by
  simp [verdict, passVerdict, usable, enoughVms, hb, hf]

theorem zoneVerdicts_eq_pass (base flag : List Pass) (hb : minVms ≤ vmCount base) (hf : minVms ≤ vmCount flag) :
    zoneVerdicts base flag = zones.map fun z => (z.name, passVerdict z.lo z.hi base flag) := by
  simp only [zoneVerdicts, verdict_eq_passVerdict _ _ base flag hb hf]

theorem decided_of_not_undecided (base flag : List Pass) (h : undecided base flag = false) :
    zoneVerdicts base flag = zones.map fun z => (z.name, passVerdict z.lo z.hi base flag) := by
  simp only [undecided, enoughVms, Bool.not_eq_false', Bool.and_eq_true, decide_eq_true_eq] at h
  exact zoneVerdicts_eq_pass base flag h.1 h.2

theorem not_mem_windowSteps_of_gt (lo hi y : Nat) (p : Pass) (h : hi < y) : y ∉ windowSteps lo hi p := by
  intro hm
  have := (List.mem_filter.1 hm).2
  simp only [decide_eq_true_eq] at this
  omega

theorem end_steps_outside (z : Zone) (hz : z ∈ zones) (p : Pass) :
    5231 ∉ windowSteps z.lo z.hi p ∧ 5267 ∉ windowSteps z.lo z.hi p := by
  have : z.hi ≤ endCut := by
    simp only [zones, List.mem_cons, List.not_mem_nil, or_false] at hz
    rcases hz with rfl | rfl | rfl | rfl <;> simp [endCut]
  exact ⟨not_mem_windowSteps_of_gt _ _ _ _ (by simp [endCut] at this ⊢; omega),
    not_mem_windowSteps_of_gt _ _ _ _ (by simp [endCut] at this ⊢; omega)⟩

end Fw.Measure.OffscreenWebKit
