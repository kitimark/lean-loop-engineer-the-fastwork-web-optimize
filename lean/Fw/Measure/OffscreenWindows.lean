import Fw.Measure.Offscreen

/-!
Push windows of one Chromium touch-swipe run, judged with `Fw.Measure.Offscreen`.
-/
namespace Fw.Measure.OffscreenWindows
open Fw.Measure.Offscreen

def wkeys : List String :=
  ["metric.RecalcStyleCount", "metric.LayoutCount", "trace.Paint", "trace.RasterTask", "trace.PaintImage", "trace.FireAnimationFrame"]

def approachFrames : Nat := 34

def touchTail : Nat := 30

def endFrame (ys : List Nat) : Option Nat := ys.max?.bind fun m => ys.findIdx? (· == m)

theorem endFrame_nil : endFrame [] = none := rfl

theorem endFrame_isSome (ys : List Nat) (h : ys ≠ []) : ∃ e, endFrame ys = some e := by
  cases ys with
  | nil => exact absurd rfl h
  | cons y ys =>
    have hm : ∃ m, (y :: ys).max? = some m := ⟨_, rfl⟩
    obtain ⟨m, hm⟩ := hm
    have hmem := List.max?_mem hm
    have hany : (y :: ys).any (fun x => x == m) = true := List.any_eq_true.2 ⟨m, hmem, by simp⟩
    have hs := List.findIdx?_isSome (p := fun x => x == m) (xs := y :: ys)
    rw [hany] at hs
    obtain ⟨i, hi⟩ := Option.isSome_iff_exists.1 hs
    exact ⟨i, by unfold endFrame; rw [hm]; exact hi⟩

theorem endFrame_spec (ys : List Nat) (e : Nat) (h : endFrame ys = some e) :
    ∃ hl : e < ys.length, (∀ y ∈ ys, y ≤ ys[e]) ∧ ∀ j (hj : j < e), ys[j]'(by omega) < ys[e] := by
  unfold endFrame at h
  cases hm : ys.max? with
  | none => simp [hm] at h
  | some m =>
    rw [hm] at h
    simp only [Option.bind_some] at h
    obtain ⟨hl, hp, hq⟩ := List.findIdx?_eq_some_iff_getElem.1 h
    simp only [beq_iff_eq] at hp hq
    have hmax := (List.max?_eq_some_iff.1 hm).2
    refine ⟨hl, fun y hy => by rw [hp]; exact hmax y hy, fun j hj => ?_⟩
    have h1 := hmax (ys[j]'(by omega)) (List.getElem_mem _)
    have h2 := hq j hj
    rw [hp]
    omega

theorem endFrame_eq (ys : List Nat) (e : Nat) (hl : e < ys.length) (hmax : ∀ y ∈ ys, y ≤ ys[e])
    (hfirst : ∀ j (hj : j < e), ys[j]'(by omega) < ys[e]) : endFrame ys = some e := by
  have hm : ys.max? = some ys[e] := List.max?_eq_some_iff.2 ⟨List.getElem_mem _, hmax⟩
  unfold endFrame
  rw [hm]
  simp only [Option.bind_some]
  apply List.findIdx?_eq_some_iff_getElem.2
  refine ⟨hl, by simp, fun j hj => ?_⟩
  have := hfirst j hj
  simp only [beq_iff_eq]
  omega

structure Win where
  name : String
  lo : Nat
  hi : Nat
deriving Repr, DecidableEq

def Win.len (w : Win) : Nat := w.hi - w.lo

def lastFrame (total tail : Nat) : Nat := total - tail

def clip (last x : Nat) : Nat := min x last

def pushWindows (e last : Nat) : List Win :=
  [⟨"approach", clip last (e - approachFrames), clip last e⟩,
   ⟨"end 0-19", clip last e, clip last (e + 20)⟩,
   ⟨"end 20-59", clip last (e + 20), clip last (e + 60)⟩,
   ⟨"end 60-119", clip last (e + 60), clip last (e + 120)⟩,
   ⟨"end 120+", clip last (e + 120), last⟩]

def finishWin (e last : Nat) : Win := ⟨"finish", clip last (e - approachFrames), last⟩

def allWindows (e last : Nat) : List Win := pushWindows e last ++ [finishWin e last]

def windowNames : List String := (allWindows 0 0).map (·.name)

theorem pushWindows_length (e last : Nat) : (pushWindows e last).length = 5 := rfl

theorem windowNames_eq : windowNames = ["approach", "end 0-19", "end 20-59", "end 60-119", "end 120+", "finish"] := rfl

theorem pushWindows_abut (e last : Nat) :
    (pushWindows e last).map (·.hi) = ((pushWindows e last).map (·.lo)).drop 1 ++ [last] := rfl

theorem pushWindows_span (e last : Nat) :
    (pushWindows e last).head?.map (·.lo) = some (finishWin e last).lo ∧
      (pushWindows e last).getLast?.map (·.hi) = some (finishWin e last).hi := ⟨rfl, rfl⟩

theorem pushWindows_ordered (e last : Nat) : ∀ w ∈ pushWindows e last, w.lo ≤ w.hi := by
  intro w hw
  simp only [pushWindows, clip, List.mem_cons, List.not_mem_nil, or_false] at hw
  rcases hw with rfl | rfl | rfl | rfl | rfl <;> simp only <;> omega

theorem finishWin_ordered (e last : Nat) : (finishWin e last).lo ≤ (finishWin e last).hi := by
  simp only [finishWin, clip]; omega

theorem pushWindows_lens (e last : Nat) (h1 : approachFrames ≤ e) (h2 : e + 120 ≤ last) :
    (pushWindows e last).map Win.len = [34, 20, 40, 60, last - (e + 120)] := by
  unfold approachFrames at h1
  simp only [pushWindows, List.map_cons, List.map_nil, Win.len, clip, approachFrames, List.cons.injEq, and_true]
  omega

theorem finishWin_len (e last : Nat) (h1 : approachFrames ≤ e) (h2 : e + 120 ≤ last) :
    (finishWin e last).len = last - e + 34 := by
  simp only [finishWin, Win.len, clip, approachFrames] at *
  omega

def sumRange (xs : List Nat) (lo hi : Nat) : Nat := ((xs.drop lo).take (hi - lo)).sum

theorem sumRange_add (xs : List Nat) (a b c : Nat) (h1 : a ≤ b) (h2 : b ≤ c) :
    sumRange xs a c = sumRange xs a b + sumRange xs b c := by
  unfold sumRange
  have : c - a = (b - a) + (c - b) := by omega
  rw [this, List.take_add, List.sum_append, List.drop_drop]
  have : a + (b - a) = b := by omega
  rw [this]

theorem sumRange_len (xs : List Nat) (lo hi : Nat) (h : hi ≤ xs.length) :
    ((xs.drop lo).take (hi - lo)).length = hi - lo := by
  simp only [List.length_take, List.length_drop]
  omega

private theorem chain5 (xs : List Nat) (c0 c1 c2 c3 c4 c5 : Nat) (h1 : c0 ≤ c1) (h2 : c1 ≤ c2) (h3 : c2 ≤ c3)
    (h4 : c3 ≤ c4) (h5 : c4 ≤ c5) :
    sumRange xs c0 c1 + (sumRange xs c1 c2 + (sumRange xs c2 c3 + (sumRange xs c3 c4 + (sumRange xs c4 c5 + 0)))) =
      sumRange xs c0 c5 := by
  rw [sumRange_add xs c0 c4 c5 (by omega) h5, sumRange_add xs c0 c3 c4 (by omega) h4,
    sumRange_add xs c0 c2 c3 (by omega) h3, sumRange_add xs c0 c1 c2 h1 h2]
  omega

theorem pushWindows_sum (xs : List Nat) (e last : Nat) :
    ((pushWindows e last).map fun w => sumRange xs w.lo w.hi).sum = sumRange xs (finishWin e last).lo (finishWin e last).hi := by
  simp only [pushWindows, finishWin, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil]
  apply chain5 <;> simp only [clip] <;> omega

theorem pushWindows_unique (e last f : Nat) (h1 : (finishWin e last).lo ≤ f) (h2 : f < (finishWin e last).hi) :
    ((pushWindows e last).filter fun w => decide (w.lo ≤ f ∧ f < w.hi)).length = 1 := by
  simp only [finishWin, clip] at h1 h2
  simp only [pushWindows, clip, List.filter_cons, List.filter_nil, decide_eq_true_eq]
  repeat' split
  all_goals (simp_all; try omega)

theorem pushWindows_outside (e last f : Nat) (h : f < (finishWin e last).lo ∨ (finishWin e last).hi ≤ f) :
    ((pushWindows e last).filter fun w => decide (w.lo ≤ f ∧ f < w.hi)).length = 0 := by
  simp only [finishWin, clip] at h
  simp only [pushWindows, clip, List.filter_cons, List.filter_nil, decide_eq_true_eq]
  repeat' split
  all_goals (simp_all; try omega)

def sumVec (cols : List (String × List Nat)) (w : Win) : Vec :=
  { n := w.len, vals := cols.map fun (k, xs) => (k, sumRange xs w.lo w.hi) }

theorem sumVec_get (cols : List (String × List Nat)) (w : Win) (k : String) (xs : List Nat)
    (hk : (cols.find? (·.1 == k)) = some (k, xs)) : (sumVec cols w).get k = some (sumRange xs w.lo w.hi) := by
  simp only [sumVec, Vec.get, List.find?_map]
  have : (cols.find? (fun x => x.1 == k)) = some (k, xs) := hk
  simp [Function.comp_def, this]

structure Run where
  ys : List Nat
  cols : List (String × List Nat)
  tail : Nat
deriving Repr

def Run.windows (r : Run) : Option (Nat × List (String × Vec)) :=
  match endFrame r.ys with
  | none => none
  | some e =>
    if r.cols.all (fun (_, xs) => xs.length == r.ys.length) then
      some (e, (allWindows e (lastFrame r.ys.length r.tail)).map fun w => (w.name, sumVec r.cols w))
    else none

theorem sumVec_n (cols : List (String × List Nat)) (w : Win) : (sumVec cols w).n = w.len := rfl

theorem Run.windows_end (r : Run) (e : Nat) (ws : List (String × Vec)) (h : r.windows = some (e, ws)) :
    endFrame r.ys = some e := by
  unfold Run.windows at h
  split at h
  · cases h
  · rename_i e' he
    split at h
    · simp only [Option.some.injEq, Prod.mk.injEq] at h
      rw [he, h.1]
    · cases h

theorem Run.windows_names (r : Run) (e : Nat) (ws : List (String × Vec)) (h : r.windows = some (e, ws)) :
    ws.map (·.1) = windowNames := by
  unfold Run.windows at h
  split at h
  · cases h
  · split at h
    · simp only [Option.some.injEq, Prod.mk.injEq] at h
      rw [← h.2]
      simp [windowNames, allWindows, pushWindows, finishWin]
    · cases h

def owner (e last f : Nat) : Option String := ((pushWindows e last).find? fun w => decide (w.lo ≤ f ∧ f < w.hi)).map (·.name)

def vecsOf (runs : List (List (String × Vec))) (name : String) : List Vec := runs.filterMap fun r => r.lookup name

def hasKeysOn (ks : List String) (rs : List Vec) : Bool := ks.all fun k => rs.all fun v => (v.get k).isSome

def usableOn (ks : List String) (base flag : List Vec) : Bool :=
  decide (minRuns ≤ base.length) && decide (minRuns ≤ flag.length) && sameWindow (base ++ flag) && hasKeysOn ks (base ++ flag)

def verdictOn (ks : List String) (base flag : List Vec) : Verdict :=
  if usableOn ks base flag then judge (ks.filterMap (cmpKey slack base flag)) else .noData

theorem verdictOn_keys (base flag : List Vec) : verdictOn keys base flag = verdict base flag := rfl

theorem usableOn_keys (base flag : List Vec) : usableOn keys base flag = usable base flag := rfl

theorem verdictOn_of_usable (ks : List String) (base flag : List Vec) (h : usableOn ks base flag = true) :
    verdictOn ks base flag = judge (ks.filterMap (cmpKey slack base flag)) := by
  simp [verdictOn, h]

theorem usableOn_of_verdict (ks : List String) (base flag : List Vec) (h : verdictOn ks base flag ≠ .noData) :
    usableOn ks base flag = true := by
  cases hu : usableOn ks base flag
  · exact absurd (by simp [verdictOn, hu]) h
  · rfl

theorem noData_of_fewBase (ks : List String) (base flag : List Vec) (h : base.length < minRuns) :
    verdictOn ks base flag = .noData := by
  have : ¬ minRuns ≤ base.length := by omega
  simp [verdictOn, usableOn, this]

theorem noData_of_fewFlag (ks : List String) (base flag : List Vec) (h : flag.length < minRuns) :
    verdictOn ks base flag = .noData := by
  have : ¬ minRuns ≤ flag.length := by omega
  simp [verdictOn, usableOn, this]

theorem noData_of_window (ks : List String) (base flag : List Vec) (h : sameWindow (base ++ flag) = false) :
    verdictOn ks base flag = .noData := by
  simp [verdictOn, usableOn, h]

theorem noData_of_missing (ks : List String) (base flag : List Vec) (h : hasKeysOn ks (base ++ flag) = false) :
    verdictOn ks base flag = .noData := by
  simp [verdictOn, usableOn, h]

theorem noGain_of_more (ks : List String) (base flag : List Vec) (k : String) (hu : usableOn ks base flag = true)
    (hk : k ∈ ks) (hm : cmpKey slack base flag k = some .more) : verdictOn ks base flag = .noGain := by
  rw [verdictOn_of_usable ks base flag hu]
  exact judge_more _ (List.mem_filterMap.2 ⟨k, hk, hm⟩)

theorem gain_sound (ks : List String) (base flag : List Vec) (h : verdictOn ks base flag = .gain) :
    usableOn ks base flag = true ∧ (∃ k ∈ ks, cmpKey slack base flag k = some .less) ∧
      ∀ j ∈ ks, cmpKey slack base flag j ≠ some .more := by
  have hu : usableOn ks base flag = true := usableOn_of_verdict ks base flag (by rw [h]; simp)
  rw [verdictOn_of_usable ks base flag hu] at h
  obtain ⟨hl, hm⟩ := judge_gain_inv _ h
  refine ⟨hu, ?_, fun j hj hjm => hm (List.mem_filterMap.2 ⟨j, hj, hjm⟩)⟩
  obtain ⟨k, hk, hkm⟩ := List.mem_filterMap.1 hl
  exact ⟨k, hk, hkm⟩

theorem verdictOn_gain_needs_runs (ks : List String) (base flag : List Vec) (h : verdictOn ks base flag = .gain) :
    minRuns ≤ base.length ∧ minRuns ≤ flag.length := by
  refine ⟨Nat.not_lt.mp fun hb => ?_, Nat.not_lt.mp fun hf => ?_⟩
  · rw [noData_of_fewBase ks base flag hb] at h; cases h
  · rw [noData_of_fewFlag ks base flag hf] at h; cases h

theorem vecsOf_length_le (runs : List (List (String × Vec))) (name : String) : (vecsOf runs name).length ≤ runs.length :=
  List.length_filterMap_le _ _

def cell (base flag : List Vec) (k : String) : Option (Cmp × (Nat × Nat) × (Nat × Nat)) := do
  let b ← spread (← values base k)
  let f ← spread (← values flag k)
  pure (cmp slack b f, b, f)

theorem cell_cmp (base flag : List Vec) (k : String) : (cell base flag k).map (·.1) = cmpKey slack base flag k := by
  unfold cell cmpKey
  cases values base k <;> cases values flag k <;> simp [Option.bind_eq_bind] <;> (try rfl)
  rename_i bs fs
  cases spread bs <;> cases spread fs <;> simp

def armVerdicts (base flag : List (List (String × Vec))) : List (String × Verdict) :=
  windowNames.map fun n => (n, verdictOn wkeys (vecsOf base n) (vecsOf flag n))

theorem armVerdicts_names (base flag : List (List (String × Vec))) : (armVerdicts base flag).map (·.1) = windowNames := by
  simp [armVerdicts, Function.comp_def]

private theorem lookup_map_pair (g : String → Verdict) (ns : List String) (n : String) (hn : n ∈ ns) :
    (ns.map fun m => (m, g m)).lookup n = some (g n) := by
  induction ns with
  | nil => simp at hn
  | cons m ms ih =>
    simp only [List.map_cons, List.lookup_cons]
    by_cases h : n = m
    · subst h; simp
    · have : (n == m) = false := beq_false_of_ne h
      simp only [this]
      exact ih ((List.mem_cons.1 hn).resolve_left h)

theorem armVerdicts_get (base flag : List (List (String × Vec))) (n : String) (hn : n ∈ windowNames) :
    (armVerdicts base flag).lookup n = some (verdictOn wkeys (vecsOf base n) (vecsOf flag n)) :=
  lookup_map_pair (fun m => verdictOn wkeys (vecsOf base m) (vecsOf flag m)) windowNames n hn

theorem armVerdicts_gain_needs_runs (base flag : List (List (String × Vec))) (n : String)
    (h : (n, Verdict.gain) ∈ armVerdicts base flag) : minRuns ≤ base.length ∧ minRuns ≤ flag.length := by
  obtain ⟨m, -, hm⟩ := List.mem_map.1 h
  simp only [Prod.mk.injEq] at hm
  obtain ⟨-, hv⟩ := hm
  have := verdictOn_gain_needs_runs wkeys _ _ hv
  exact ⟨Nat.le_trans this.1 (vecsOf_length_le base m), Nat.le_trans this.2 (vecsOf_length_le flag m)⟩

theorem armVerdicts_of_usable (base flag : List (List (String × Vec))) (n : String) (hn : n ∈ windowNames)
    (hu : usableOn wkeys (vecsOf base n) (vecsOf flag n) = true) :
    (armVerdicts base flag).lookup n = some (judge (wkeys.filterMap (cmpKey slack (vecsOf base n) (vecsOf flag n)))) := by
  rw [armVerdicts_get base flag n hn, verdictOn_of_usable wkeys _ _ hu]

end Fw.Measure.OffscreenWindows
