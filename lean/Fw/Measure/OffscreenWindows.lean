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

def Win.cap (m : Nat) (w : Win) : Win := { w with hi := min w.hi (w.lo + m) }

theorem Win.cap_len (m : Nat) (w : Win) : (w.cap m).len = min w.len m := by
  simp only [Win.cap, Win.len]; omega

theorem Win.cap_name (m : Nat) (w : Win) : (w.cap m).name = w.name := rfl

theorem Win.cap_of_len_le (m : Nat) (w : Win) (h : w.len ≤ m) : w.cap m = w := by
  cases w with
  | mk name lo hi =>
    simp only [Win.len] at h
    simp only [Win.cap, Win.mk.injEq, true_and]
    omega

def Run.plan (r : Run) : Option (Nat × List Win) :=
  match endFrame r.ys with
  | none => none
  | some e =>
    if r.cols.all (fun (_, xs) => xs.length == r.ys.length) then some (e, allWindows e (lastFrame r.ys.length r.tail))
    else none

theorem Run.windows_eq_plan (r : Run) :
    r.windows = r.plan.map fun p => (p.1, p.2.map fun w => (w.name, sumVec r.cols w)) := by
  unfold Run.windows Run.plan
  split
  · rfl
  · split <;> rfl

def lenOf (ws : List Win) (n : String) : Option Nat := (ws.find? (·.name == n)).map Win.len

def commonLen (plans : List (Nat × List Win)) (n : String) : Nat :=
  ((plans.filterMap fun p => lenOf p.2 n).min?).getD 0

def Run.capped (r : Run) (cap : String → Nat) : Option (List (String × Vec)) :=
  r.plan.map fun p => p.2.map fun w => (w.name, sumVec r.cols (w.cap (cap w.name)))

def ownVerdicts (base flag : List Run) : List (String × Verdict) :=
  let cap := commonLen ((base ++ flag).filterMap (·.plan))
  armVerdicts (base.filterMap (·.capped cap)) (flag.filterMap (·.capped cap))

def ownFrames (base flag : List Run) : List (String × Nat) :=
  let cap := commonLen ((base ++ flag).filterMap (·.plan))
  windowNames.map fun n => (n, cap n)

theorem lookup_windows (ws : List Win) (f : Win → Vec) (n : String) :
    (ws.map fun w => (w.name, f w)).lookup n = (ws.find? (·.name == n)).map f := by
  induction ws with
  | nil => rfl
  | cons w ws ih =>
    simp only [List.map_cons, List.lookup_cons, List.find?_cons]
    by_cases h : (w.name == n) = true
    · have h' : (n == w.name) = true := by simp only [beq_iff_eq] at h ⊢; exact h.symm
      simp [h, h']
    · have h1 : (w.name == n) = false := by simpa using h
      have h' : (n == w.name) = false := by
        simp only [Bool.eq_false_iff, ne_eq, beq_iff_eq] at h1 ⊢
        exact fun e => h1 e.symm
      simp [h1, h', ih]

theorem lookup_capped (r : Run) (cap : String → Nat) (n : String)
    (h : ∀ p, r.plan = some p → ∀ w, p.2.find? (·.name == n) = some w → w.len ≤ cap n) :
    (r.capped cap).bind (List.lookup n) = (r.windows.map (·.2)).bind (List.lookup n) := by
  rw [Run.windows_eq_plan]
  unfold Run.capped
  cases hp : r.plan with
  | none => rfl
  | some p =>
    simp only [Option.map_some, Option.bind_some]
    rw [lookup_windows p.2 (fun w => sumVec r.cols (w.cap (cap w.name))) n,
      lookup_windows p.2 (fun w => sumVec r.cols w) n]
    cases hf : p.2.find? (·.name == n) with
    | none => rfl
    | some w =>
      have hw := h p hp w hf
      have hn : w.name = n := by simpa using List.find?_some hf
      simp only [Option.map_some]
      rw [hn, Win.cap_of_len_le _ _ hw]

theorem vecsOf_capped (rs : List Run) (cap : String → Nat) (n : String)
    (h : ∀ r ∈ rs, ∀ p, r.plan = some p → ∀ w, p.2.find? (·.name == n) = some w → w.len ≤ cap n) :
    vecsOf (rs.filterMap (·.capped cap)) n = vecsOf (rs.filterMap fun r => r.windows.map (·.2)) n := by
  simp only [vecsOf, List.filterMap_filterMap]
  induction rs with
  | nil => rfl
  | cons r rs ih =>
    rw [List.filterMap_cons, List.filterMap_cons, lookup_capped r cap n (h r (List.mem_cons_self ..)),
      ih fun r' hr' => h r' (List.mem_cons_of_mem _ hr')]

theorem lenOf_eq_some (ws : List Win) (n : String) (w : Win) (h : ws.find? (·.name == n) = some w) :
    lenOf ws n = some w.len := by
  simp [lenOf, h]

theorem le_commonLen (plans : List (Nat × List Win)) (n : String) (c : Nat)
    (hmem : c ∈ plans.filterMap fun p => lenOf p.2 n) (hall : ∀ x ∈ plans.filterMap (fun p => lenOf p.2 n), c ≤ x) :
    c ≤ commonLen plans n := by
  unfold commonLen
  cases hm : (plans.filterMap fun p => lenOf p.2 n).min? with
  | none =>
    rw [List.min?_eq_none_iff] at hm
    rw [hm] at hmem
    cases hmem
  | some a =>
    exact hall a (List.min?_mem hm)

theorem cap_ge_of_same_len (rs : List Run) (n : String) (c : Option Nat)
    (h : ∀ r ∈ rs, ∀ p, r.plan = some p → lenOf p.2 n = c) :
    ∀ r ∈ rs, ∀ p, r.plan = some p → ∀ w, p.2.find? (·.name == n) = some w →
      w.len ≤ commonLen (rs.filterMap (·.plan)) n := by
  intro r hr p hp w hw
  have hc : c = some w.len := by rw [← h r hr p hp, lenOf_eq_some _ _ _ hw]
  apply le_commonLen
  · exact List.mem_filterMap.2 ⟨p, List.mem_filterMap.2 ⟨r, hr, hp⟩, by rw [h r hr p hp, hc]⟩
  · intro x hx
    obtain ⟨p', hp', hx⟩ := List.mem_filterMap.1 hx
    obtain ⟨r', hr', hp''⟩ := List.mem_filterMap.1 hp'
    have := h r' hr' p' hp''
    rw [hx, hc] at this
    simp only [Option.some.injEq] at this
    omega

theorem ownVecs_eq (base flag : List Run) (n : String) (c : Option Nat)
    (h : ∀ r ∈ base ++ flag, ∀ p, r.plan = some p → lenOf p.2 n = c) :
    vecsOf (base.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n =
        vecsOf (base.filterMap fun r => r.windows.map (·.2)) n ∧
      vecsOf (flag.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n =
        vecsOf (flag.filterMap fun r => r.windows.map (·.2)) n := by
  have hge := cap_ge_of_same_len (base ++ flag) n c h
  constructor
  · exact vecsOf_capped base _ n fun r hr => hge r (List.mem_append_left _ hr)
  · exact vecsOf_capped flag _ n fun r hr => hge r (List.mem_append_right _ hr)

theorem ownVerdicts_get (base flag : List Run) (n : String) (hn : n ∈ windowNames) :
    (ownVerdicts base flag).lookup n =
      some (verdictOn wkeys (vecsOf (base.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n)
        (vecsOf (flag.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n)) :=
  armVerdicts_get _ _ n hn

theorem ownVerdicts_eq_window (base flag : List Run) (n : String) (hn : n ∈ windowNames) (c : Option Nat)
    (h : ∀ r ∈ base ++ flag, ∀ p, r.plan = some p → lenOf p.2 n = c) :
    (ownVerdicts base flag).lookup n =
      (armVerdicts (base.filterMap fun r => r.windows.map (·.2)) (flag.filterMap fun r => r.windows.map (·.2))).lookup n := by
  rw [ownVerdicts_get base flag n hn, armVerdicts_get _ _ n hn, (ownVecs_eq base flag n c h).1, (ownVecs_eq base flag n c h).2]

theorem ownVerdicts_eq_of_same_end (base flag : List Run) (e last : Nat)
    (h : ∀ r ∈ base ++ flag, r.plan = none ∨ r.plan = some (e, allWindows e last)) :
    ownVerdicts base flag =
      armVerdicts (base.filterMap fun r => r.windows.map (·.2)) (flag.filterMap fun r => r.windows.map (·.2)) := by
  unfold ownVerdicts armVerdicts
  simp only
  apply List.map_congr_left
  intro n hn
  have hv := ownVecs_eq base flag n (lenOf (allWindows e last) n) fun r hr p hp => by
    rcases h r hr with h | h
    · rw [hp] at h; cases h
    · rw [hp] at h; cases h; rfl
  rw [hv.1, hv.2]

theorem length_capped (rs : List Run) (cap : String → Nat) :
    (rs.filterMap (·.capped cap)).length = (rs.filterMap (·.plan)).length := by
  induction rs with
  | nil => rfl
  | cons r rs ih =>
    cases hp : r.plan with
    | none =>
      have h1 : r.capped cap = none := by simp [Run.capped, hp]
      simp [h1, hp, ih]
    | some p =>
      have h1 : r.capped cap = some (p.2.map fun w => (w.name, sumVec r.cols (w.cap (cap w.name)))) := by
        simp [Run.capped, hp]
      simp [h1, hp, ih]

theorem ownVerdicts_gain_needs_runs (base flag : List Run) (n : String) (h : (n, Verdict.gain) ∈ ownVerdicts base flag) :
    minRuns ≤ (base.filterMap (·.plan)).length ∧ minRuns ≤ (flag.filterMap (·.plan)).length := by
  have := armVerdicts_gain_needs_runs _ _ n h
  rw [length_capped, length_capped] at this
  exact this

theorem ownVerdicts_noData_of_fewBase (base flag : List Run) (h : (base.filterMap (·.plan)).length < minRuns) :
    ∀ q ∈ ownVerdicts base flag, q.2 = Verdict.noData := by
  intro q hq
  obtain ⟨n, -, rfl⟩ := List.mem_map.1 hq
  apply noData_of_fewBase
  have := vecsOf_length_le (base.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n
  rw [length_capped] at this
  omega

theorem ownVerdicts_noData_of_fewFlag (base flag : List Run) (h : (flag.filterMap (·.plan)).length < minRuns) :
    ∀ q ∈ ownVerdicts base flag, q.2 = Verdict.noData := by
  intro q hq
  obtain ⟨n, -, rfl⟩ := List.mem_map.1 hq
  apply noData_of_fewFlag
  have := vecsOf_length_le (flag.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n
  rw [length_capped] at this
  omega

theorem vecsOf_capped_n_le (rs : List Run) (cap : String → Nat) (n : String) (v : Vec)
    (hv : v ∈ vecsOf (rs.filterMap (·.capped cap)) n) : v.n ≤ cap n := by
  simp only [vecsOf, List.filterMap_filterMap] at hv
  obtain ⟨r, -, hr⟩ := List.mem_filterMap.1 hv
  unfold Run.capped at hr
  cases hp : r.plan with
  | none => simp [hp] at hr
  | some p =>
    simp only [hp, Option.map_some, Option.bind_some] at hr
    rw [lookup_windows p.2 (fun w => sumVec r.cols (w.cap (cap w.name))) n] at hr
    cases hf : p.2.find? (·.name == n) with
    | none => simp [hf] at hr
    | some w =>
      have hn : w.name = n := by simpa using List.find?_some hf
      simp only [hf, Option.map_some, Option.some.injEq] at hr
      rw [← hr, sumVec_n, Win.cap_len, hn]
      exact Nat.min_le_right _ _

theorem ownVerdicts_noData_of_noFrames (base flag : List Run) (n : String) (hn : n ∈ windowNames)
    (h : commonLen ((base ++ flag).filterMap (·.plan)) n = 0) : (ownVerdicts base flag).lookup n = some Verdict.noData := by
  rw [ownVerdicts_get base flag n hn]
  apply congrArg some
  apply noData_of_window
  unfold sameWindow
  cases hl : vecsOf (base.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n ++
      vecsOf (flag.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n with
  | nil => rfl
  | cons v vs =>
    have hv : v ∈ vecsOf (base.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n ++
        vecsOf (flag.filterMap (·.capped (commonLen ((base ++ flag).filterMap (·.plan))))) n := by rw [hl]; simp
    have hle : v.n ≤ 0 := by
      rcases List.mem_append.1 hv with hv | hv
      · have := vecsOf_capped_n_le _ _ n v hv; omega
      · have := vecsOf_capped_n_le _ _ n v hv; omega
    simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not]
    left; omega

def minEnd120 : Nat := 20

def wholeWindows : List Win := allWindows approachFrames (approachFrames + 120 + minEnd120)

def minFrames (n : String) : Nat := (lenOf wholeWindows n).getD 0

theorem minFrames_eq : windowNames.map minFrames = [34, 20, 40, 60, 20, 174] := by decide

theorem minEnd120_eq_end0 : minEnd120 = minFrames "end 0-19" := by decide

theorem minFrames_push : (pushWindows approachFrames (approachFrames + 120 + minEnd120)).map (minFrames ·.name) =
    (pushWindows approachFrames (approachFrames + 120 + minEnd120)).map Win.len := by decide

theorem minFrames_finish :
    minFrames "finish" = ((pushWindows approachFrames (approachFrames + 120 + minEnd120)).map Win.len).sum := by decide

def framesOk (plans : List (Nat × List Win)) (n : String) : Bool := decide (minFrames n ≤ commonLen plans n)

def minVerdicts (base flag : List Run) : List (String × Verdict) :=
  let plans := (base ++ flag).filterMap (·.plan)
  (ownVerdicts base flag).map fun q => (q.1, if framesOk plans q.1 then q.2 else .noData)

theorem lookup_map_snd (qs : List (String × Verdict)) (g : String → Verdict → Verdict) (n : String) :
    (qs.map fun q => (q.1, g q.1 q.2)).lookup n = (qs.lookup n).map (g n) := by
  induction qs with
  | nil => rfl
  | cons q qs ih =>
    obtain ⟨k, v⟩ := q
    simp only [List.map_cons, List.lookup_cons]
    by_cases h : (n == k) = true
    · have : n = k := beq_iff_eq.1 h
      subst this
      simp
    · simp only [Bool.not_eq_true] at h
      simp [h, ih]

theorem minVerdicts_get (base flag : List Run) (n : String) :
    (minVerdicts base flag).lookup n = ((ownVerdicts base flag).lookup n).map fun v =>
      if framesOk ((base ++ flag).filterMap (·.plan)) n then v else .noData := by
  unfold minVerdicts
  exact lookup_map_snd (ownVerdicts base flag) (fun m v => if framesOk ((base ++ flag).filterMap (·.plan)) m then v else .noData) n

theorem minVerdicts_needs_frames (base flag : List Run) (n : String) (v : Verdict) (h : (n, v) ∈ minVerdicts base flag)
    (hv : v ≠ .noData) : minFrames n ≤ commonLen ((base ++ flag).filterMap (·.plan)) n := by
  obtain ⟨q, -, hq⟩ := List.mem_map.1 h
  simp only [Prod.mk.injEq] at hq
  obtain ⟨rfl, hq⟩ := hq
  by_cases hok : framesOk ((base ++ flag).filterMap (·.plan)) q.1 = true
  · simpa [framesOk] using hok
  · simp only [hok] at hq
    exact absurd hq.symm hv

theorem minVerdicts_eq_or_noData (base flag : List Run) (n : String) (v : Verdict) (h : (n, v) ∈ minVerdicts base flag) :
    v = .noData ∨ (n, v) ∈ ownVerdicts base flag := by
  obtain ⟨q, hq, he⟩ := List.mem_map.1 h
  simp only [Prod.mk.injEq] at he
  obtain ⟨rfl, he⟩ := he
  split at he
  · exact Or.inr (he ▸ hq)
  · exact Or.inl he.symm

theorem minVerdicts_gain_own (base flag : List Run) (n : String) (h : (n, Verdict.gain) ∈ minVerdicts base flag) :
    (n, Verdict.gain) ∈ ownVerdicts base flag :=
  (minVerdicts_eq_or_noData base flag n _ h).resolve_left (by simp)

theorem commonLen_le (plans : List (Nat × List Win)) (n : String) (l : Nat)
    (h : l ∈ plans.filterMap fun p => lenOf p.2 n) : commonLen plans n ≤ l := by
  unfold commonLen
  cases hm : (plans.filterMap fun p => lenOf p.2 n).min? with
  | none => rw [List.min?_eq_none_iff] at hm; rw [hm] at h; cases h
  | some a => exact (List.min?_eq_some_iff.1 hm).2 l h

theorem minVerdicts_short_noData (base flag : List Run) (n : String) (hn : n ∈ windowNames) (r : Run) (p : Nat × List Win)
    (l : Nat) (hr : r ∈ base ++ flag) (hp : r.plan = some p) (hl : lenOf p.2 n = some l) (hs : l < minFrames n) :
    (minVerdicts base flag).lookup n = some .noData := by
  have hc := commonLen_le ((base ++ flag).filterMap (·.plan)) n l
    (List.mem_filterMap.2 ⟨p, List.mem_filterMap.2 ⟨r, hr, hp⟩, hl⟩)
  have hok : framesOk ((base ++ flag).filterMap (·.plan)) n = false := by
    simp only [framesOk, decide_eq_false_iff_not]; omega
  rw [minVerdicts_get, ownVerdicts_get base flag n hn, hok]
  rfl

theorem minVerdicts_short_not_gain (base flag : List Run) (n : String) (hn : n ∈ windowNames) (r : Run)
    (p : Nat × List Win) (l : Nat) (hr : r ∈ base ++ flag) (hp : r.plan = some p) (hl : lenOf p.2 n = some l)
    (hs : l < minFrames n) : (minVerdicts base flag).lookup n ≠ some .gain := by
  rw [minVerdicts_short_noData base flag n hn r p l hr hp hl hs]
  simp

theorem Run.plan_windows (r : Run) (p : Nat × List Win) (h : r.plan = some p) :
    ∃ last, p.2 = allWindows p.1 last := by
  unfold Run.plan at h
  split at h
  · cases h
  · split at h
    · cases h; exact ⟨_, rfl⟩
    · cases h

theorem lenOf_allWindows (e last : Nat) (n : String) (hn : n ∈ windowNames) : (lenOf (allWindows e last) n).isSome := by
  rw [windowNames_eq] at hn
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hn
  rcases hn with rfl | rfl | rfl | rfl | rfl | rfl <;> rfl

theorem minVerdicts_eq_own (base flag : List Run)
    (h : ∀ r ∈ base ++ flag, ∀ p, r.plan = some p → ∀ n l, lenOf p.2 n = some l → minFrames n ≤ l) :
    minVerdicts base flag = ownVerdicts base flag := by
  unfold minVerdicts
  simp only
  conv => rhs; rw [← List.map_id (ownVerdicts base flag)]
  apply List.map_congr_left
  rintro ⟨n, v⟩ hq
  simp only [id]
  by_cases hok : framesOk ((base ++ flag).filterMap (·.plan)) n = true
  · simp only [hok, ↓reduceIte]
  · have hn : n ∈ windowNames := by
      obtain ⟨m, hm, he⟩ := List.mem_map.1 hq
      simp only [Prod.mk.injEq] at he
      exact he.1 ▸ hm
    cases hps : (base ++ flag).filterMap (·.plan) with
    | nil =>
      have hb : (base.filterMap (·.plan)).length < minRuns := by
        rw [List.filterMap_append, List.append_eq_nil_iff] at hps
        rw [hps.1]; decide
      have hv : v = .noData := ownVerdicts_noData_of_fewBase base flag hb _ hq
      subst hv
      split <;> rfl
    | cons p ps =>
      exfalso
      obtain ⟨r, hr, hp⟩ := List.mem_filterMap.1 (hps ▸ List.mem_cons_self : p ∈ (base ++ flag).filterMap (·.plan))
      obtain ⟨last, hw⟩ := Run.plan_windows r p hp
      obtain ⟨l, hl⟩ := Option.isSome_iff_exists.1 (hw ▸ lenOf_allWindows p.1 last n hn)
      cases hm : (((base ++ flag).filterMap (·.plan)).filterMap fun p => lenOf p.2 n).min? with
      | none =>
        rw [List.min?_eq_none_iff] at hm
        have : l ∈ ((base ++ flag).filterMap (·.plan)).filterMap fun p => lenOf p.2 n :=
          List.mem_filterMap.2 ⟨p, List.mem_filterMap.2 ⟨r, hr, hp⟩, hl⟩
        rw [hm] at this
        cases this
      | some a =>
        obtain ⟨ha, -⟩ := List.min?_eq_some_iff.1 hm
        obtain ⟨p', hp', ha⟩ := List.mem_filterMap.1 ha
        obtain ⟨r', hr', hp''⟩ := List.mem_filterMap.1 hp'
        have h1 := h r' hr' p' hp'' n a ha
        have h2 : commonLen ((base ++ flag).filterMap (·.plan)) n = a := by
          unfold commonLen; rw [hm]; rfl
        simp only [framesOk, h2, decide_eq_true_eq] at hok
        omega

end Fw.Measure.OffscreenWindows
