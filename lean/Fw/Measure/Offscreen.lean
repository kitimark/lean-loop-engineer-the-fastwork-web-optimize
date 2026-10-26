/-!
# Offscreen windows of one section (lane offscreen-count-lane)

Which recorded frames count as "offscreen for section S", what the window sums of a run are, and the verdict of a flag.
-/
namespace Fw.Measure.Offscreen

/-- The section's top edge below the viewport top, its height and the viewport height, all in thousandths of a CSS px. -/
structure Rec where
  top : Int
  height : Nat
  vh : Nat
deriving Repr, DecidableEq

/-- No pixel row of the viewport shows a row of the section (the zero-area rule of `sceneHidden`). -/
def Rec.hidden (r : Rec) : Bool :=
  decide (r.height = 0 ∨ r.vh = 0 ∨ r.top + r.height ≤ 0 ∨ (r.vh : Int) ≤ r.top)

/-- Some viewport row shows a row of the section. -/
def Rec.shows (r : Rec) : Prop :=
  ∃ y : Int, 0 ≤ y ∧ y < r.vh ∧ r.top ≤ y ∧ y < r.top + r.height

theorem hidden_iff (r : Rec) : r.hidden = true ↔ ¬ r.shows := by
  unfold Rec.hidden Rec.shows
  constructor
  · intro h ⟨y, h0, h1, h2, h3⟩
    simp only [decide_eq_true_eq] at h
    omega
  · intro h
    simp only [decide_eq_true_eq]
    refine Classical.byContradiction fun hc => h ⟨max r.top 0, ?_, ?_, ?_, ?_⟩ <;> omega

theorem hidden_of_empty (r : Rec) (h : r.height = 0) : r.hidden = true := by
  simp [Rec.hidden, h]

theorem hidden_of_noViewport (r : Rec) (h : r.vh = 0) : r.hidden = true := by
  simp [Rec.hidden, h]

theorem hidden_of_above (r : Rec) (h : r.top + r.height ≤ 0) : r.hidden = true := by
  simp [Rec.hidden, h]

theorem hidden_of_below (r : Rec) (h : (r.vh : Int) ≤ r.top) : r.hidden = true := by
  simp [Rec.hidden, h]

theorem shown_of_overlap (r : Rec) (h0 : 0 < r.height) (hv : 0 < r.vh) (h1 : 0 < r.top + r.height) (h2 : r.top < r.vh) :
    r.hidden = false := by
  simp only [Rec.hidden, decide_eq_false_iff_not]
  omega

/-- The run of consecutive hidden frames that ends at each frame, 0 at a shown frame; `c` is the run before the list. -/
def runLen : Nat → List Bool → List Nat
  | _, [] => []
  | c, b :: bs => (if b then c + 1 else 0) :: runLen (if b then c + 1 else 0) bs

/-- Hidden frames after the first `k` of their run. -/
def steady (k : Nat) (hid : List Bool) : List Bool := (runLen 0 hid).map fun n => decide (k < n)

/-- `sub m m'`: same length and every frame set in `m` is set in `m'`. -/
def sub : List Bool → List Bool → Bool
  | [], [] => true
  | b :: bs, c :: cs => (!b || c) && sub bs cs
  | _, _ => false

/-- The sum of `xs` over the frames set in `m`. -/
def sumWhere : List Bool → List Nat → Nat
  | b :: bs, x :: xs => (if b then x else 0) + sumWhere bs xs
  | _, _ => 0

theorem length_runLen (c : Nat) (hid : List Bool) : (runLen c hid).length = hid.length := by
  induction hid generalizing c with
  | nil => rfl
  | cons b bs ih => simp [runLen, ih]

theorem length_steady (k : Nat) (hid : List Bool) : (steady k hid).length = hid.length := by
  simp [steady, length_runLen]

theorem steady_zero_of (k c : Nat) (hid : List Bool) :
    sub ((runLen c hid).map fun n => decide (k < n)) hid = true := by
  induction hid generalizing c with
  | nil => rfl
  | cons b bs ih =>
    simp only [runLen, List.map_cons, sub, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true']
    refine ⟨?_, ih _⟩
    cases b <;> simp

/-- A steady frame is a hidden frame. -/
theorem steady_sub_hidden (k : Nat) (hid : List Bool) : sub (steady k hid) hid = true :=
  steady_zero_of k 0 hid

theorem steady_mono_of (k k' : Nat) (hk : k ≤ k') (c : Nat) (hid : List Bool) :
    sub ((runLen c hid).map fun n => decide (k' < n)) ((runLen c hid).map fun n => decide (k < n)) = true := by
  induction hid generalizing c with
  | nil => rfl
  | cons b bs ih =>
    simp only [runLen, List.map_cons, sub, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true']
    refine ⟨?_, ih _⟩
    cases b <;> simp <;> omega

/-- A longer settle never adds a frame. -/
theorem steady_mono (k k' : Nat) (hk : k ≤ k') (hid : List Bool) : sub (steady k' hid) (steady k hid) = true :=
  steady_mono_of k k' hk 0 hid

theorem steady_zero_hidden_of (c : Nat) (hid : List Bool) :
    sub hid ((runLen c hid).map fun n => decide (0 < n)) = true := by
  induction hid generalizing c with
  | nil => rfl
  | cons b bs ih =>
    simp only [runLen, List.map_cons, sub, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true']
    refine ⟨?_, ih _⟩
    cases b <;> simp

/-- With no settle every hidden frame is steady. -/
theorem steady_zero (hid : List Bool) : sub hid (steady 0 hid) = true := steady_zero_hidden_of 0 hid

theorem sumWhere_mono (m m' : List Bool) (xs : List Nat) (h : sub m m' = true) : sumWhere m xs ≤ sumWhere m' xs := by
  induction m generalizing m' xs with
  | nil => simp [sumWhere]
  | cons b bs ih =>
    cases m' with
    | nil => simp [sub] at h
    | cons c cs =>
      cases xs with
      | nil => simp [sumWhere]
      | cons x xs =>
        simp only [sub, Bool.and_eq_true] at h
        obtain ⟨h1, h2⟩ := h
        have := ih cs xs h2
        simp only [sumWhere]
        cases b <;> cases c <;> simp at h1 ⊢ <;> omega

theorem sumWhere_le_sum (m : List Bool) (xs : List Nat) : sumWhere m xs ≤ xs.sum := by
  induction m generalizing xs with
  | nil => simp [sumWhere]
  | cons b bs ih =>
    cases xs with
    | nil => simp [sumWhere]
    | cons x xs =>
      have := ih xs
      simp only [sumWhere, List.sum_cons]
      cases b <;> simp <;> omega

theorem sumWhere_none (n : Nat) (xs : List Nat) : sumWhere (List.replicate n false) xs = 0 := by
  induction n generalizing xs with
  | zero => simp [sumWhere]
  | succ n ih =>
    cases xs with
    | nil => simp [sumWhere]
    | cons x xs => simp [List.replicate, sumWhere, ih]

/-- A run's steady-window sum never exceeds its hidden-window sum, and that never exceeds the run total. -/
theorem steady_sum_le (k : Nat) (hid : List Bool) (xs : List Nat) :
    sumWhere (steady k hid) xs ≤ sumWhere hid xs ∧ sumWhere hid xs ≤ xs.sum :=
  ⟨sumWhere_mono _ _ _ (steady_sub_hidden k hid), sumWhere_le_sum hid xs⟩

/-- Sum of `xs` over each maximal block of set frames of `m`; `cur` is the open block. -/
def blockSumsFrom : Option Nat → List Bool → List Nat → List Nat
  | cur, b :: bs, x :: xs =>
    if b then blockSumsFrom (some (cur.getD 0 + x)) bs xs
    else (match cur with
      | some s => s :: blockSumsFrom none bs xs
      | none => blockSumsFrom none bs xs)
  | cur, _, _ => cur.toList

def blockSums (m : List Bool) (xs : List Nat) : List Nat := blockSumsFrom none m xs

theorem blockSumsFrom_sum (cur : Option Nat) (m : List Bool) (xs : List Nat) :
    (blockSumsFrom cur m xs).sum = cur.getD 0 + sumWhere m xs := by
  induction m generalizing cur xs with
  | nil => cases cur <;> simp [blockSumsFrom, sumWhere]
  | cons b bs ih =>
    cases xs with
    | nil => cases cur <;> simp [blockSumsFrom, sumWhere]
    | cons x xs =>
      cases b <;> cases cur <;> simp [blockSumsFrom, sumWhere, ih] <;> omega

/-- The windows of a run partition its steady sum. -/
theorem blockSums_sum (m : List Bool) (xs : List Nat) : (blockSums m xs).sum = sumWhere m xs := by
  simp [blockSums, blockSumsFrom_sum]

/-- The steady window of a run: its frame count and, per counter, the sum over those frames. -/
structure Vec where
  n : Nat
  vals : List (String × Nat)
deriving Repr, DecidableEq

def Vec.get (v : Vec) (k : String) : Option Nat := (v.vals.find? (·.1 == k)).map (·.2)

/-- Frames after the first `settle` of an offscreen run. -/
def settle : Nat := 3

/-- A comparison needs at least this many runs per arm, each on its own CI job. -/
def minRuns : Nat := 3

/-- Counts that differ by at most this many are the same. -/
def slack : Nat := 0

/-- The counters a verdict reads: style recalcs, layouts, paints, commits, draws, main frames and composited ticks. -/
def keys : List String :=
  ["metric.RecalcStyleCount", "metric.LayoutCount", "trace.UpdateLayoutTree", "trace.Layout", "trace.PrePaint", "trace.Paint",
   "trace.Commit", "trace.cc.Draw", "trace.cc.BeginMainFrame", "trace.cc.NeedsTick", "trace.cc.TickAnimations", "trace.FireAnimationFrame"]

/-- Base count minus flag count. -/
def reduction (base flag : Nat) : Int := (base : Int) - flag

theorem reduction_pos_iff (b f : Nat) : 0 < reduction b f ↔ f < b := by
  unfold reduction; omega

theorem reduction_self (b : Nat) : reduction b b = 0 := by
  unfold reduction; omega

inductive Cmp where
  | less
  | same
  | more
deriving Repr, DecidableEq

/-- Compare the flag's spread `(min, max)` over its runs with the base's: less when every flag run is below every base run by more than the slack. -/
def cmp (sl : Nat) (b f : Nat × Nat) : Cmp :=
  if f.2 + sl < b.1 then .less else if b.2 + sl < f.1 then .more else .same

theorem cmp_less (sl : Nat) (b f : Nat × Nat) (h : cmp sl b f = .less) : f.2 + sl < b.1 := by
  unfold cmp at h
  split at h
  · assumption
  · split at h <;> cases h

theorem cmp_more (sl : Nat) (b f : Nat × Nat) (h : cmp sl b f = .more) : b.2 + sl < f.1 := by
  unfold cmp at h
  split at h
  · cases h
  · split at h
    · assumption
    · cases h

theorem cmp_same (sl : Nat) (b f : Nat × Nat) (h : cmp sl b f = .same) : ¬ f.2 + sl < b.1 ∧ ¬ b.2 + sl < f.1 := by
  unfold cmp at h
  split at h
  · cases h
  · split at h
    · cases h
    · exact ⟨by assumption, by assumption⟩

theorem cmp_swap (sl : Nat) (b f : Nat × Nat) (hb : b.1 ≤ b.2) (hf : f.1 ≤ f.2) :
    cmp sl b f = .less ↔ cmp sl f b = .more := by
  unfold cmp
  by_cases h1 : f.2 + sl < b.1 <;> by_cases h2 : b.2 + sl < f.1 <;> simp [h1, h2] <;> omega

/-- Less is exactly a positive guaranteed reduction: the base minimum minus the flag maximum exceeds the slack. -/
theorem cmp_less_iff_reduction (sl : Nat) (b f : Nat × Nat) : cmp sl b f = .less ↔ (sl : Int) < reduction b.1 f.2 := by
  unfold cmp reduction
  constructor
  · intro h; have := cmp_less sl b f h; omega
  · intro h
    have : f.2 + sl < b.1 := by omega
    simp [this]

/-- Equal spreads with min ≤ max are the same. -/
theorem cmp_self (sl : Nat) (b : Nat × Nat) (h : b.1 ≤ b.2) : cmp sl b b = .same := by
  unfold cmp
  have h1 : ¬ b.2 + sl < b.1 := by omega
  simp [h1]

/-- The values of key `k` over the runs, none if a run lacks it. -/
def values (rs : List Vec) (k : String) : Option (List Nat) := rs.mapM (·.get k)

def spread (xs : List Nat) : Option (Nat × Nat) :=
  match xs.min?, xs.max? with
  | some a, some b => some (a, b)
  | _, _ => none

def cmpKey (sl : Nat) (base flag : List Vec) (k : String) : Option Cmp := do
  let bs ← values base k
  let fs ← values flag k
  let b ← spread bs
  let f ← spread fs
  pure (cmp sl b f)

/-- Every run has the same positive window length. -/
def sameWindow : List Vec → Bool
  | [] => false
  | r :: rs => decide (0 < r.n) && rs.all fun x => x.n == r.n

def hasKeys (rs : List Vec) : Bool := keys.all fun k => rs.all fun v => (v.get k).isSome

/-- Enough runs per arm, one positive window length across both arms, every counter present. -/
def usable (base flag : List Vec) : Bool :=
  decide (minRuns ≤ base.length) && decide (minRuns ≤ flag.length) && sameWindow (base ++ flag) && hasKeys (base ++ flag)

inductive Verdict where
  | gain
  | noGain
  | noData
deriving Repr, DecidableEq

/-- More wins over less: a flag with any counter above the base is no gain. -/
def judge (cs : List Cmp) : Verdict :=
  if Cmp.more ∈ cs then .noGain else if Cmp.less ∈ cs then .gain else .noGain

/-- A flag gains when some counter is less and none is more, on usable data; no data otherwise. -/
def verdict (base flag : List Vec) : Verdict :=
  if usable base flag then judge (keys.filterMap (cmpKey slack base flag)) else .noData

/-- Each flag is judged against the base alone. -/
def verdictAll (base : List Vec) (flags : List (List Vec)) : List Verdict := flags.map (verdict base)

theorem verdictAll_cons (base f : List Vec) (fs : List (List Vec)) :
    verdictAll base (f :: fs) = verdict base f :: verdictAll base fs := rfl

theorem judge_ne (cs : List Cmp) : judge cs ≠ .noData := by
  unfold judge
  split <;> (try split) <;> simp

theorem judge_more (cs : List Cmp) (h : Cmp.more ∈ cs) : judge cs = .noGain := by
  simp [judge, h]

theorem judge_gain (cs : List Cmp) (hl : Cmp.less ∈ cs) (hm : Cmp.more ∉ cs) : judge cs = .gain := by
  simp [judge, hm, hl]

theorem judge_same (cs : List Cmp) (hl : Cmp.less ∉ cs) (hm : Cmp.more ∉ cs) : judge cs = .noGain := by
  simp [judge, hm, hl]

theorem judge_gain_inv (cs : List Cmp) (h : judge cs = .gain) : Cmp.less ∈ cs ∧ Cmp.more ∉ cs := by
  unfold judge at h
  by_cases hm : Cmp.more ∈ cs
  · simp [hm] at h
  · by_cases hl : Cmp.less ∈ cs
    · exact ⟨hl, hm⟩
    · simp [hm, hl] at h

theorem verdict_of_usable (base flag : List Vec) (hu : usable base flag = true) :
    verdict base flag = judge (keys.filterMap (cmpKey slack base flag)) := by
  simp [verdict, hu]

theorem noData_of_usable (base flag : List Vec) : verdict base flag = .noData ↔ usable base flag = false := by
  cases hu : usable base flag
  · simp [verdict, hu]
  · rw [verdict_of_usable base flag hu]
    constructor
    · intro hv; exact absurd hv (judge_ne _)
    · intro hv; cases hv

theorem noData_of_fewBase (base flag : List Vec) (h : base.length < minRuns) : verdict base flag = .noData := by
  rw [noData_of_usable]
  unfold usable
  have : ¬ minRuns ≤ base.length := by omega
  simp [this]

theorem noData_of_fewFlag (base flag : List Vec) (h : flag.length < minRuns) : verdict base flag = .noData := by
  rw [noData_of_usable]
  unfold usable
  have : ¬ minRuns ≤ flag.length := by omega
  simp [this]

theorem noData_of_window (base flag : List Vec) (h : sameWindow (base ++ flag) = false) : verdict base flag = .noData := by
  rw [noData_of_usable]
  unfold usable
  simp [h]

theorem noData_of_missing (base flag : List Vec) (h : hasKeys (base ++ flag) = false) : verdict base flag = .noData := by
  rw [noData_of_usable]
  unfold usable
  simp [h]

theorem noData_of_emptyWindow (base flag : List Vec) (r : Vec) (hr : r ∈ base ++ flag) (h : r.n = 0) :
    verdict base flag = .noData := by
  apply noData_of_window
  unfold sameWindow
  generalize hs : base ++ flag = s at hr
  cases s with
  | nil => simp at hr
  | cons a rest =>
    simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not, Nat.not_lt, Nat.le_zero]
    by_cases ha : a.n = 0
    · exact Or.inl ha
    · right
      simp only [List.all_eq_false, beq_iff_eq]
      rcases List.mem_cons.mp hr with rfl | hm
      · exact absurd h ha
      · exact ⟨r, hm, by simp [h]; omega⟩

theorem verdict_usable (base flag : List Vec) (h : verdict base flag ≠ .noData) : usable base flag = true := by
  cases hu : usable base flag
  · exact absurd ((noData_of_usable base flag).2 hu) h
  · rfl

theorem noGain_of_more (base flag : List Vec) (k : String) (hu : usable base flag = true)
    (hk : k ∈ keys) (hm : cmpKey slack base flag k = some .more) : verdict base flag = .noGain := by
  rw [verdict_of_usable base flag hu]
  exact judge_more _ (List.mem_filterMap.2 ⟨k, hk, hm⟩)

theorem gain_of_less (base flag : List Vec) (k : String) (hu : usable base flag = true)
    (hk : k ∈ keys) (hl : cmpKey slack base flag k = some .less)
    (hn : ∀ j ∈ keys, cmpKey slack base flag j ≠ some .more) : verdict base flag = .gain := by
  rw [verdict_of_usable base flag hu]
  refine judge_gain _ (List.mem_filterMap.2 ⟨k, hk, hl⟩) fun hm => ?_
  obtain ⟨j, hj, hjm⟩ := List.mem_filterMap.1 hm
  exact hn j hj hjm

theorem noGain_of_same (base flag : List Vec) (hu : usable base flag = true)
    (hs : ∀ j ∈ keys, cmpKey slack base flag j ≠ some .less ∧ cmpKey slack base flag j ≠ some .more) :
    verdict base flag = .noGain := by
  rw [verdict_of_usable base flag hu]
  refine judge_same _ (fun hm => ?_) (fun hm => ?_)
  · obtain ⟨j, hj, hjm⟩ := List.mem_filterMap.1 hm
    exact (hs j hj).1 hjm
  · obtain ⟨j, hj, hjm⟩ := List.mem_filterMap.1 hm
    exact (hs j hj).2 hjm

/-- A gain names a counter whose every flag run is below every base run by more than the slack, and no counter is more. -/
theorem gain_sound (base flag : List Vec) (h : verdict base flag = .gain) :
    usable base flag = true ∧ (∃ k ∈ keys, cmpKey slack base flag k = some .less) ∧
      ∀ j ∈ keys, cmpKey slack base flag j ≠ some .more := by
  have hu : usable base flag = true := verdict_usable base flag (by rw [h]; simp)
  rw [verdict_of_usable base flag hu] at h
  obtain ⟨hl, hm⟩ := judge_gain_inv _ h
  refine ⟨hu, ?_, fun j hj hjm => hm (List.mem_filterMap.2 ⟨j, hj, hjm⟩)⟩
  obtain ⟨k, hk, hkm⟩ := List.mem_filterMap.1 hl
  exact ⟨k, hk, hkm⟩

theorem gain_needs_runs (base flag : List Vec) (h : verdict base flag = .gain) :
    minRuns ≤ base.length ∧ minRuns ≤ flag.length := by
  refine ⟨Nat.not_lt.mp fun hb => ?_, Nat.not_lt.mp fun hf => ?_⟩
  · rw [noData_of_fewBase base flag hb] at h; cases h
  · rw [noData_of_fewFlag base flag hf] at h; cases h

theorem verdict_empty_base (flag : List Vec) : verdict [] flag = .noData := noData_of_fewBase [] flag (by decide)

theorem verdict_empty_flag (base : List Vec) : verdict base [] = .noData := noData_of_fewFlag base [] (by decide)

/-- Frames of the section's hidden mask. -/
def hiddenMask (rs : List Rec) : List Bool := rs.map Rec.hidden

/-- One run's window: the steady frames after `k` settle frames and, per counter, its sum over them. -/
def windowVec (k : Nat) (rs : List Rec) (cols : List (String × List Nat)) : Vec :=
  let m := steady k (hiddenMask rs)
  { n := m.count true, vals := cols.map fun (key, xs) => (key, sumWhere m xs) }

theorem windowVec_n_le (k : Nat) (rs : List Rec) (cols : List (String × List Nat)) :
    (windowVec k rs cols).n ≤ rs.length := by
  simp only [windowVec]
  have := List.count_le_length (a := true) (l := steady k (hiddenMask rs))
  rw [length_steady] at this
  simpa [hiddenMask] using this

/-- A run with no hidden frame has an empty window and so no verdict. -/
theorem windowVec_empty (k : Nat) (rs : List Rec) (cols : List (String × List Nat))
    (h : ∀ r ∈ rs, r.hidden = false) : (windowVec k rs cols).n = 0 := by
  have hm : ∀ b ∈ hiddenMask rs, b = false := by
    intro b hb
    obtain ⟨r, hr, rfl⟩ := List.mem_map.1 hb
    exact h r hr
  have key : ∀ (c : Nat) (hid : List Bool), (∀ b ∈ hid, b = false) →
      ∀ x ∈ (runLen c hid).map (fun n => decide (k < n)), x = false := by
    intro c hid
    induction hid generalizing c with
    | nil => intro _ x hx; simp [runLen] at hx
    | cons b bs ih =>
      intro hb x hx
      have hb0 : b = false := hb b (List.mem_cons_self ..)
      subst hb0
      simp only [runLen, List.map_cons, List.mem_cons] at hx
      rcases hx with rfl | hx
      · simp
      · exact ih _ (fun b' hb' => hb b' (List.mem_cons_of_mem _ hb')) x (by simpa using hx)
  simp only [windowVec, steady]
  rw [List.count_eq_zero]
  intro hx
  have := key 0 _ hm true hx
  cases this

end Fw.Measure.Offscreen
