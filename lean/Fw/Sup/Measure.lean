import Lean.Data.Json
import Fw.Sup.Adapt
import Fw.Gate.Smooth
namespace Fw.Sup.Measure
open Lean (Json ToJson toJson)
open Fw.Sup.Adapt

structure QParams where
  loadMarginCenti : Nat := 100
  holdersMax : Nat := 0
  minPasses : Nat := 3
  maxGapS : Nat := 1800
  baseMinSamples : Nat := 8
  baseSpreadCenti : Nat := 150
  floorMaxCenti : Nat := 800
  settleS : Nat := 120
deriving DecidableEq, Repr

def ceilCenti (q : QParams) (fl : Nat) : Nat := fl + q.loadMarginCenti

inductive Why where
  | load | avail | pressure | swapOut | compress | holders
deriving DecidableEq, Repr

def Why.name : Why → String
  | .load => "load" | .avail => "avail" | .pressure => "pressure" | .swapOut => "swapOut" | .compress => "compress"
  | .holders => "holders"

structure Reading where
  s : Sample
  holders : Nat
deriving DecidableEq, Repr

def whysRest (q : QParams) (p : Params) (r : Reading) : List Why :=
  (if r.s.avail < p.floorMB then [Why.avail] else []) ++
  (if r.s.mem.press ≠ 1 then [Why.pressure] else []) ++
  (if swapActive p r.s.mem then [Why.swapOut] else []) ++
  (if thrash p r.s.mem || cmprsHigh p r.s then [Why.compress] else []) ++
  (if q.holdersMax < r.holders then [Why.holders] else [])

def whys (q : QParams) (p : Params) (fl : Nat) (r : Reading) : List Why :=
  (if ceilCenti q fl < r.s.loadCenti then [Why.load] else []) ++ whysRest q p r

def quiet (q : QParams) (p : Params) (fl : Nat) (r : Reading) : Bool := (whys q p fl r).isEmpty

theorem quiet_iff (q : QParams) (p : Params) (fl : Nat) (r : Reading) :
    quiet q p fl r = true ↔ (r.s.loadCenti ≤ ceilCenti q fl ∧ p.floorMB ≤ r.s.avail ∧ r.s.mem.press = 1 ∧
      swapActive p r.s.mem = false ∧ thrash p r.s.mem = false ∧ cmprsHigh p r.s = false ∧ r.holders ≤ q.holdersMax) := by
  simp only [quiet, whys, whysRest, List.isEmpty_iff, List.append_eq_nil_iff, ite_eq_right_iff, reduceCtorEq, imp_false, Nat.not_lt,
    Bool.or_eq_true, not_or, ne_eq, Decidable.not_not, Bool.not_eq_true]
  simp only [Sample.avail] at *
  constructor
  · rintro ⟨h1, ⟨⟨⟨h2, h3⟩, h4⟩, h5, h6⟩, h7⟩
    exact ⟨h1, h2, h3, h4, h5, h6, h7⟩
  · rintro ⟨h1, h2, h3, h4, h5, h6, h7⟩
    exact ⟨h1, ⟨⟨⟨h2, h3⟩, h4⟩, h5, h6⟩, h7⟩

theorem not_quiet_load (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : ceilCenti q fl < r.s.loadCenti) :
    quiet q p fl r = false := by
  simp [quiet, whys, h]

theorem not_quiet_avail (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : r.s.avail < p.floorMB) :
    quiet q p fl r = false := by
  simp [quiet, whys, whysRest, h]

theorem not_quiet_pressure (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : r.s.mem.press ≠ 1) :
    quiet q p fl r = false := by
  simp [quiet, whys, whysRest, h]

theorem not_quiet_swapOut (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : swapActive p r.s.mem = true) :
    quiet q p fl r = false := by
  simp [quiet, whys, whysRest, h]

theorem not_quiet_thrash (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : thrash p r.s.mem = true) :
    quiet q p fl r = false := by
  simp [quiet, whys, whysRest, h]

theorem not_quiet_cmprs (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : cmprsHigh p r.s = true) :
    quiet q p fl r = false := by
  simp [quiet, whys, whysRest, h]

theorem not_quiet_holders (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : q.holdersMax < r.holders) :
    quiet q p fl r = false := by
  simp [quiet, whys, whysRest, h]

theorem quiet_load_le (q : QParams) (p : Params) (fl : Nat) (r : Reading) (h : quiet q p fl r = true) :
    r.s.loadCenti ≤ fl + q.loadMarginCenti := ((quiet_iff q p fl r).1 h).1

theorem quiet_not_overloaded (q : QParams) (p : Params) (fl : Nat) (r : Reading) (prev : Option (Nat × Nat))
    (hq : quiet q p fl r = true) (hl : ceilCenti q fl < p.highCenti) (hs : swapRising p prev r.s = false) :
    overloaded p prev r.s = false := by
  obtain ⟨h1, h2, h3, h4, h5, h6, -⟩ := (quiet_iff q p fl r).1 hq
  have hl' : loadHigh p r.s = false := by simp [loadHigh]; omega
  have hm : memLow p r.s.mem = false := by
    have : availMB r.s.mem = r.s.avail := rfl
    simp [memLow, this, h3, h4, h5]; omega
  simp [overloaded, hl', hm, h6, hs]

theorem quiet_load_antitone (q : QParams) (p : Params) (fl : Nat) (r : Reading) (c : Nat) (hq : quiet q p fl r = true)
    (hc : c ≤ r.s.loadCenti) : quiet q p fl { r with s := { r.s with loadCenti := c } } = true := by
  have := (quiet_iff q p fl r).1 hq
  rw [quiet_iff]
  have e : ({ r with s := { r.s with loadCenti := c } } : Reading).s.avail = r.s.avail := rfl
  simp only [Sample.avail] at *
  obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := this
  refine ⟨?_, h2, h3, h4, h5, ?_, h7⟩
  · exact Nat.le_trans hc h1
  · simpa [cmprsHigh] using h6

theorem quiet_floor_mono (q : QParams) (p : Params) (fl fl' : Nat) (r : Reading) (hq : quiet q p fl r = true) (h : fl ≤ fl') :
    quiet q p fl' r = true := by
  have := (quiet_iff q p fl r).1 hq
  rw [quiet_iff]
  obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := this
  refine ⟨?_, h2, h3, h4, h5, h6, h7⟩
  unfold ceilCenti at *
  omega

inductive Phase where
  | before | after
deriving DecidableEq, Repr

inductive Decision where
  | accept
  | refuse (ph : Phase) (ws : List Why)
  | stale
deriving DecidableEq, Repr

def judge (q : QParams) (p : Params) (fl : Nat) (b a : Reading) : Decision :=
  if quiet q p fl b = false then .refuse .before (whys q p fl b)
  else if quiet q p fl a = false then .refuse .after (whys q p fl a)
  else if a.s.time < b.s.time ∨ b.s.time + q.maxGapS < a.s.time then .stale
  else .accept

theorem judge_refuse_before (q : QParams) (p : Params) (fl : Nat) (b a : Reading) (h : quiet q p fl b = false) :
    judge q p fl b a = .refuse .before (whys q p fl b) := by
  simp [judge, h]

theorem judge_refuse_after (q : QParams) (p : Params) (fl : Nat) (b a : Reading) (hb : quiet q p fl b = true) (h : quiet q p fl a = false) :
    judge q p fl b a = .refuse .after (whys q p fl a) := by
  simp [judge, hb, h]

theorem judge_stale_order (q : QParams) (p : Params) (fl : Nat) (b a : Reading) (hb : quiet q p fl b = true) (ha : quiet q p fl a = true)
    (h : a.s.time < b.s.time) : judge q p fl b a = .stale := by
  simp [judge, hb, ha, h]

theorem judge_stale_gap (q : QParams) (p : Params) (fl : Nat) (b a : Reading) (hb : quiet q p fl b = true) (ha : quiet q p fl a = true)
    (h : b.s.time + q.maxGapS < a.s.time) : judge q p fl b a = .stale := by
  simp [judge, hb, ha, h]

theorem judge_accept (q : QParams) (p : Params) (fl : Nat) (b a : Reading) (hb : quiet q p fl b = true) (ha : quiet q p fl a = true)
    (h1 : b.s.time ≤ a.s.time) (h2 : a.s.time ≤ b.s.time + q.maxGapS) : judge q p fl b a = .accept := by
  have h1' : ¬ a.s.time < b.s.time := by omega
  have h2' : ¬ b.s.time + q.maxGapS < a.s.time := by omega
  simp [judge, hb, ha, h1', h2']

theorem judge_accept_quiet (q : QParams) (p : Params) (fl : Nat) (b a : Reading) (h : judge q p fl b a = .accept) :
    quiet q p fl b = true ∧ quiet q p fl a = true := by
  unfold judge at h
  by_cases hb : quiet q p fl b = false
  · simp [hb] at h
  · by_cases ha : quiet q p fl a = false
    · simp [hb, ha] at h
    · simp at hb ha
      exact ⟨hb, ha⟩

theorem judge_accept_load_le (q : QParams) (p : Params) (fl : Nat) (b a : Reading) (h : judge q p fl b a = .accept) :
    b.s.loadCenti ≤ fl + q.loadMarginCenti ∧ a.s.loadCenti ≤ fl + q.loadMarginCenti := by
  obtain ⟨hb, ha⟩ := judge_accept_quiet q p fl b a h
  exact ⟨quiet_load_le q p fl b hb, quiet_load_le q p fl a ha⟩

def longTenths : Nat := 250

def sortNat (l : List Nat) : List Nat := l.mergeSort fun a b => decide (a ≤ b)

def pct (k : Nat) (ivs : List Nat) : Nat :=
  (sortNat ivs).getD (max 1 ((k * ivs.length + 99) / 100) - 1) 0

def slotOf (ivs : List Nat) : Nat := if pct 50 ivs < 125 then 83 else 167

def skipped (slot : Nat) (ivs : List Nat) : Nat := (ivs.map fun i => (2 * i + slot) / (2 * slot) - 1).sum

def longCount (ivs : List Nat) : Nat := ivs.countP fun i => decide (longTenths < i)

structure Stat where
  frames : Nat
  long : Nat
  skipped : Nat
  p50 : Nat
  p95 : Nat
  mx : Nat
deriving DecidableEq, Repr

def stat (frames : Nat) (ivs : List Nat) : Stat :=
  { frames, long := longCount ivs, skipped := skipped (slotOf ivs) ivs, p50 := pct 50 ivs, p95 := pct 95 ivs, mx := pct 100 ivs }

theorem sortNat_pairwise (l : List Nat) : (sortNat l).Pairwise (· ≤ ·) := by
  have := List.pairwise_mergeSort (le := fun a b : Nat => decide (a ≤ b)) (l := l)
    (by intro a b c h1 h2; simp at *; omega) (by intro a b; simp; omega)
  simpa [sortNat] using this

theorem length_sortNat (l : List Nat) : (sortNat l).length = l.length := by simp [sortNat]

theorem mem_sortNat {l : List Nat} {x : Nat} : x ∈ sortNat l ↔ x ∈ l := List.mem_mergeSort

private theorem getD_le_of_pairwise (s : List Nat) (h : s.Pairwise (· ≤ ·)) (i j : Nat) (hij : i ≤ j) (hj : j < s.length) :
    s.getD i 0 ≤ s.getD j 0 := by
  have hi : i < s.length := by omega
  simp only [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi, List.getElem?_eq_getElem hj, Option.getD_some]
  rcases Nat.eq_or_lt_of_le hij with e | lt
  · subst e; exact Nat.le_refl _
  · exact List.pairwise_iff_getElem.1 h i j hi hj lt

private theorem rank_le (k n : Nat) (hk : k ≤ 100) (hn : 0 < n) : max 1 ((k * n + 99) / 100) - 1 < n := by
  have : (k * n + 99) / 100 ≤ n := by
    have := Nat.mul_le_mul_right n hk
    omega
  omega

theorem pct_mono (a b : Nat) (ivs : List Nat) (hab : a ≤ b) (hb : b ≤ 100) : pct a ivs ≤ pct b ivs := by
  unfold pct
  by_cases hn : ivs.length = 0
  · simp [sortNat, List.length_eq_zero_iff.1 hn]
  · have hn' : 0 < ivs.length := Nat.pos_of_ne_zero hn
    apply getD_le_of_pairwise _ (sortNat_pairwise ivs)
    · have : (a * ivs.length + 99) / 100 ≤ (b * ivs.length + 99) / 100 :=
        Nat.div_le_div_right (by have := Nat.mul_le_mul_right ivs.length hab; omega)
      omega
    · rw [length_sortNat]; exact rank_le b _ hb hn'

theorem p50_le_p95 (ivs : List Nat) : pct 50 ivs ≤ pct 95 ivs := pct_mono 50 95 ivs (by omega) (by omega)

theorem p95_le_max (ivs : List Nat) : pct 95 ivs ≤ pct 100 ivs := pct_mono 95 100 ivs (by omega) (by omega)

theorem max_mem (ivs : List Nat) (h : ivs ≠ []) : pct 100 ivs ∈ ivs := by
  unfold pct
  have hn : 0 < ivs.length := List.length_pos_iff.2 h
  have hr : max 1 ((100 * ivs.length + 99) / 100) - 1 < (sortNat ivs).length := by
    rw [length_sortNat]; exact rank_le 100 _ (by omega) hn
  have : (sortNat ivs).getD (max 1 ((100 * ivs.length + 99) / 100) - 1) 0 ∈ sortNat ivs := by
    simp only [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hr, Option.getD_some]
    exact List.getElem_mem hr
  exact mem_sortNat.1 this

theorem max_ge (ivs : List Nat) (x : Nat) (hx : x ∈ ivs) : x ≤ pct 100 ivs := by
  unfold pct
  have hn : 0 < ivs.length := List.length_pos_iff.2 (List.ne_nil_of_mem hx)
  have hr : max 1 ((100 * ivs.length + 99) / 100) - 1 < (sortNat ivs).length := by
    rw [length_sortNat]; exact rank_le 100 _ (by omega) hn
  have hlast : max 1 ((100 * ivs.length + 99) / 100) - 1 = ivs.length - 1 := by
    have : (100 * ivs.length + 99) / 100 = ivs.length := by omega
    omega
  rw [hlast]
  obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem (mem_sortNat.2 hx)
  have hlen := length_sortNat ivs
  have := getD_le_of_pairwise _ (sortNat_pairwise ivs) i (ivs.length - 1) (by omega) (by omega)
  simpa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi] using this

theorem stat_p_order (frames : Nat) (ivs : List Nat) :
    (stat frames ivs).p50 ≤ (stat frames ivs).p95 ∧ (stat frames ivs).p95 ≤ (stat frames ivs).mx :=
  ⟨p50_le_p95 ivs, p95_le_max ivs⟩

theorem skipped_nil (slot : Nat) : skipped slot [] = 0 := rfl

theorem skipped_eq_zero (slot : Nat) (ivs : List Nat) (h : ∀ i ∈ ivs, 2 * i < 3 * slot) : skipped slot ivs = 0 := by
  unfold skipped
  induction ivs with
  | nil => rfl
  | cons i t ih =>
    have hi := h i (by simp)
    have ht := ih (fun j hj => h j (by simp [hj]))
    have : (2 * i + slot) / (2 * slot) ≤ 1 := by
      apply Nat.le_of_lt_succ
      apply Nat.div_lt_of_lt_mul
      omega
    simp only [List.map_cons, List.sum_cons]
    omega

private theorem le_sum_of_mem (l : List Nat) (x : Nat) (h : x ∈ l) : x ≤ l.sum := by
  induction l with
  | nil => simp at h
  | cons y t ih =>
    simp only [List.sum_cons]
    rcases List.mem_cons.1 h with rfl | hm
    · omega
    · have := ih hm
      omega

theorem skipped_pos (slot : Nat) (ivs : List Nat) (i : Nat) (hi : i ∈ ivs) (hs : 0 < slot) (h : 5 * slot ≤ 2 * i) :
    0 < skipped slot ivs := by
  unfold skipped
  have h1 : 0 < (2 * i + slot) / (2 * slot) - 1 := by
    have : 2 ≤ (2 * i + slot) / (2 * slot) := by
      apply (Nat.le_div_iff_mul_le (by omega)).2
      omega
    omega
  exact Nat.lt_of_lt_of_le h1 (le_sum_of_mem _ _ (List.mem_map.2 ⟨i, hi, rfl⟩))

theorem long_le_length (ivs : List Nat) : longCount ivs ≤ ivs.length := List.countP_le_length

theorem slotOf_cases (ivs : List Nat) : slotOf ivs = 83 ∨ slotOf ivs = 167 := by
  unfold slotOf; split <;> simp

def loads (rs : List Reading) : List Nat := rs.map fun r => r.s.loadCenti

def baselineFloor (q : QParams) (p : Params) (rs : List Reading) : Option Nat :=
  if rs.length < q.baseMinSamples then none
  else if rs.any (fun r => !(whysRest q p r).isEmpty) then none
  else if q.baseSpreadCenti < pct 100 (loads rs) - pct 0 (loads rs) then none
  else if q.floorMaxCenti < pct 50 (loads rs) then none
  else some (pct 50 (loads rs))

theorem baselineFloor_none_few (q : QParams) (p : Params) (rs : List Reading) (h : rs.length < q.baseMinSamples) :
    baselineFloor q p rs = none := by
  simp [baselineFloor, h]

theorem baselineFloor_none_loud (q : QParams) (p : Params) (rs : List Reading) (r : Reading) (hr : r ∈ rs)
    (h : whysRest q p r ≠ []) : baselineFloor q p rs = none := by
  unfold baselineFloor
  have : rs.any (fun r => !(whysRest q p r).isEmpty) = true := by
    rw [List.any_eq_true]
    exact ⟨r, hr, by simpa [List.isEmpty_iff] using h⟩
  split <;> simp

theorem baselineFloor_none_spread (q : QParams) (p : Params) (rs : List Reading) (h : q.baseSpreadCenti < pct 100 (loads rs) - pct 0 (loads rs)) :
    baselineFloor q p rs = none := by
  unfold baselineFloor
  split
  · rfl
  · split
    · rfl
    · simp

theorem baselineFloor_none_high (q : QParams) (p : Params) (rs : List Reading) (h : q.floorMaxCenti < pct 50 (loads rs)) :
    baselineFloor q p rs = none := by
  unfold baselineFloor
  split
  · rfl
  · split
    · rfl
    · split
      · rfl
      · simp

theorem baselineFloor_some (q : QParams) (p : Params) (rs : List Reading) (fl : Nat) (h : baselineFloor q p rs = some fl) :
    fl = pct 50 (loads rs) ∧ q.baseMinSamples ≤ rs.length ∧ (∀ r ∈ rs, whysRest q p r = []) ∧
      pct 100 (loads rs) - pct 0 (loads rs) ≤ q.baseSpreadCenti ∧ fl ≤ q.floorMaxCenti := by
  unfold baselineFloor at h
  by_cases h1 : rs.length < q.baseMinSamples
  · simp [h1] at h
  by_cases h2 : rs.any (fun r => !(whysRest q p r).isEmpty) = true
  · simp [h1, h2] at h
  by_cases h3 : q.baseSpreadCenti < pct 100 (loads rs) - pct 0 (loads rs)
  · simp [h1, h2, h3] at h
  by_cases h4 : q.floorMaxCenti < pct 50 (loads rs)
  · simp [h1, h2, h3, h4] at h
  simp [h1, h2, h3, h4] at h
  subst h
  refine ⟨rfl, by omega, ?_, by omega, by omega⟩
  intro r hr
  have : ¬ rs.any (fun r => !(whysRest q p r).isEmpty) = true := h2
  rw [List.any_eq_true] at this
  refine Classical.byContradiction fun hne => this ⟨r, hr, ?_⟩
  simpa [List.isEmpty_iff] using hne

theorem baselineFloor_between (q : QParams) (p : Params) (rs : List Reading) (fl : Nat) (h : baselineFloor q p rs = some fl) :
    pct 0 (loads rs) ≤ fl ∧ fl ≤ pct 100 (loads rs) := by
  obtain ⟨rfl, -⟩ := baselineFloor_some q p rs fl h
  exact ⟨pct_mono 0 50 _ (by omega) (by omega), pct_mono 50 100 _ (by omega) (by omega)⟩

theorem accepted_load_le_cap (q : QParams) (p : Params) (rs : List Reading) (fl : Nat) (b a : Reading)
    (hf : baselineFloor q p rs = some fl) (h : judge q p fl b a = .accept) :
    b.s.loadCenti ≤ q.floorMaxCenti + q.loadMarginCenti ∧ a.s.loadCenti ≤ q.floorMaxCenti + q.loadMarginCenti := by
  obtain ⟨hb, ha⟩ := judge_accept_load_le q p fl b a h
  have := (baselineFloor_some q p rs fl hf).2.2.2.2
  omega

def settledAfter (q : QParams) (boot : Nat) (rs : List Reading) : List Reading :=
  rs.filter fun r => decide (boot + q.settleS ≤ r.s.time)

theorem mem_settledAfter (q : QParams) (boot : Nat) (rs : List Reading) (r : Reading) (h : r ∈ settledAfter q boot rs) :
    r ∈ rs ∧ boot + q.settleS ≤ r.s.time := by
  simpa [settledAfter] using h

def simFloor (q : QParams) (p : Params) (boot : Nat) (rs : List Reading) : Option Nat :=
  baselineFloor q p (settledAfter q boot rs)

theorem simFloor_none_unsettled (q : QParams) (p : Params) (boot : Nat) (rs : List Reading) (hq : 0 < q.baseMinSamples)
    (h : ∀ r ∈ rs, r.s.time < boot + q.settleS) : simFloor q p boot rs = none := by
  apply baselineFloor_none_few
  have : settledAfter q boot rs = [] := by
    apply List.eq_nil_iff_forall_not_mem.2
    intro r hr
    obtain ⟨h1, h2⟩ := mem_settledAfter q boot rs r hr
    have := h r h1
    omega
  rw [this]; simpa using hq

theorem simFloor_some_settled (q : QParams) (p : Params) (boot : Nat) (rs : List Reading) (fl : Nat)
    (h : simFloor q p boot rs = some fl) : q.baseMinSamples ≤ (settledAfter q boot rs).length :=
  (baselineFloor_some q p _ fl h).2.1

inductive Outcome where
  | better | worse | same | insufficient
deriving DecidableEq, Repr

def Outcome.name : Outcome → String
  | .better => "better" | .worse => "worse" | .same => "same" | .insufficient => "insufficient"

def outcome (q : QParams) (arm base : List Nat) : Outcome :=
  if arm.length < q.minPasses ∨ base.length < q.minPasses then .insufficient
  else match Fw.Gate.Smooth.hitchJudge arm base with
    | .first => .better
    | .second => .worse
    | _ => .same

theorem outcome_insufficient_arm (q : QParams) (arm base : List Nat) (h : arm.length < q.minPasses) :
    outcome q arm base = .insufficient := by
  simp [outcome, h]

theorem outcome_insufficient_base (q : QParams) (arm base : List Nat) (h : base.length < q.minPasses) :
    outcome q arm base = .insufficient := by
  simp [outcome, h]

theorem outcome_better (q : QParams) (arm base : List Nat) (ha : q.minPasses ≤ arm.length) (hb : q.minPasses ≤ base.length)
    (h : Fw.Gate.Smooth.above base arm = true) : outcome q arm base = .better := by
  have : ¬ (arm.length < q.minPasses ∨ base.length < q.minPasses) := by omega
  simp [outcome, this, Fw.Gate.Smooth.hitchJudge_first arm base h]

theorem outcome_worse (q : QParams) (arm base : List Nat) (ha : q.minPasses ≤ arm.length) (hb : q.minPasses ≤ base.length)
    (hq : 0 < q.minPasses) (h : Fw.Gate.Smooth.above arm base = true) : outcome q arm base = .worse := by
  have : ¬ (arm.length < q.minPasses ∨ base.length < q.minPasses) := by omega
  have ha' : arm ≠ [] := by intro e; subst e; simp at ha; omega
  have hb' : base ≠ [] := by intro e; subst e; simp at hb; omega
  simp [outcome, this, Fw.Gate.Smooth.hitchJudge_second arm base ha' hb' h]

theorem outcome_same (q : QParams) (arm base : List Nat) (ha : q.minPasses ≤ arm.length) (hb : q.minPasses ≤ base.length)
    (h1 : Fw.Gate.Smooth.above base arm = false) (h2 : Fw.Gate.Smooth.above arm base = false) :
    outcome q arm base = .same := by
  have : ¬ (arm.length < q.minPasses ∨ base.length < q.minPasses) := by omega
  simp [outcome, this, Fw.Gate.Smooth.hitchJudge_same arm base h1 h2]

theorem outcome_self (q : QParams) (hq : 0 < q.minPasses) (xs : List Nat) : outcome q xs xs ≠ .better ∧ outcome q xs xs ≠ .worse := by
  by_cases hn : xs = []
  · subst hn
    simp [outcome, hq]
  · have hno : Fw.Gate.Smooth.above xs xs = false := by
      cases h : Fw.Gate.Smooth.above xs xs
      · rfl
      · rw [Fw.Gate.Smooth.above_iff] at h
        obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil xs hn
        have := h x hx x hx
        omega
    unfold outcome
    split
    · simp
    · simp [Fw.Gate.Smooth.hitchJudge, hno]

def kept (xs : List (Decision × Nat)) : List Nat := xs.filterMap fun d => if d.1 = .accept then some d.2 else none

theorem kept_length_le (xs : List (Decision × Nat)) : (kept xs).length ≤ xs.length := List.length_filterMap_le _ _

theorem kept_refused (ph : Phase) (ws : List Why) (v : Nat) (xs : List (Decision × Nat)) :
    kept ((.refuse ph ws, v) :: xs) = kept xs := by
  simp [kept]

theorem kept_stale (v : Nat) (xs : List (Decision × Nat)) : kept ((.stale, v) :: xs) = kept xs := by
  simp [kept]

theorem kept_accept (v : Nat) (xs : List (Decision × Nat)) : kept ((.accept, v) :: xs) = v :: kept xs := by
  simp [kept]

def hitchesRecorded (finalized : Bool) (rows : Nat) : Bool := finalized && decide (0 < rows)

theorem hitches_not_finalized (rows : Nat) : hitchesRecorded false rows = false := rfl

theorem hitches_no_rows (fin : Bool) : hitchesRecorded fin 0 = false := by simp [hitchesRecorded]

theorem hitches_recorded (rows : Nat) (h : 0 < rows) : hitchesRecorded true rows = true := by simp [hitchesRecorded, h]

structure ProbeLimits where
  graceS : Nat := 60
  hardGraceS : Nat := 120
  maxTraceMB : Nat := 12288
  minFreeMB : Nat := 30720
deriving DecidableEq, Repr

inductive ProbeAct where
  | wait | interrupt | kill
deriving DecidableEq, Repr

def ProbeAct.name : ProbeAct → String
  | .wait => "wait" | .interrupt => "interrupt" | .kill => "kill"

structure ProbeLook where
  elapsedS : Nat
  limitS : Nat
  traceMB : Nat
  parentAlive : Bool
deriving DecidableEq, Repr

def probeAct (l : ProbeLimits) (s : ProbeLook) : ProbeAct :=
  if s.parentAlive = false then .kill
  else if l.maxTraceMB < s.traceMB then .kill
  else if s.limitS + l.hardGraceS ≤ s.elapsedS then .kill
  else if s.limitS + l.graceS ≤ s.elapsedS then .interrupt
  else .wait

def mayRecord (l : ProbeLimits) (freeMB : Nat) : Bool := decide (l.minFreeMB ≤ freeMB)

theorem probeAct_orphan (l : ProbeLimits) (s : ProbeLook) (h : s.parentAlive = false) : probeAct l s = .kill := by
  simp [probeAct, h]

theorem probeAct_oversize (l : ProbeLimits) (s : ProbeLook) (hp : s.parentAlive = true) (h : l.maxTraceMB < s.traceMB) :
    probeAct l s = .kill := by
  simp [probeAct, hp, h]

theorem probeAct_late (l : ProbeLimits) (s : ProbeLook) (hp : s.parentAlive = true) (hs : s.traceMB ≤ l.maxTraceMB)
    (h : s.limitS + l.hardGraceS ≤ s.elapsedS) : probeAct l s = .kill := by
  have : ¬ l.maxTraceMB < s.traceMB := by omega
  simp [probeAct, hp, this, h]

theorem probeAct_interrupt (l : ProbeLimits) (s : ProbeLook) (hp : s.parentAlive = true) (hs : s.traceMB ≤ l.maxTraceMB)
    (h1 : s.limitS + l.graceS ≤ s.elapsedS) (h2 : s.elapsedS < s.limitS + l.hardGraceS) : probeAct l s = .interrupt := by
  have : ¬ l.maxTraceMB < s.traceMB := by omega
  have h2' : ¬ s.limitS + l.hardGraceS ≤ s.elapsedS := by omega
  simp [probeAct, hp, this, h1, h2']

theorem probeAct_wait (l : ProbeLimits) (s : ProbeLook) (hg : l.graceS ≤ l.hardGraceS) (hp : s.parentAlive = true)
    (hs : s.traceMB ≤ l.maxTraceMB) (h : s.elapsedS < s.limitS + l.graceS) : probeAct l s = .wait := by
  have : ¬ l.maxTraceMB < s.traceMB := by omega
  have h1 : ¬ s.limitS + l.hardGraceS ≤ s.elapsedS := by omega
  have h2 : ¬ s.limitS + l.graceS ≤ s.elapsedS := by omega
  simp [probeAct, hp, this, h1, h2]

theorem probeAct_bounded (l : ProbeLimits) (s : ProbeLook) (h : s.limitS + l.hardGraceS ≤ s.elapsedS) : probeAct l s = .kill := by
  by_cases hp : s.parentAlive = true
  · by_cases hs : l.maxTraceMB < s.traceMB
    · exact probeAct_oversize l s hp hs
    · exact probeAct_late l s hp (by omega) h
  · exact probeAct_orphan l s (by simpa using hp)

theorem mayRecord_low (l : ProbeLimits) (freeMB : Nat) (h : freeMB < l.minFreeMB) : mayRecord l freeMB = false := by
  simp [mayRecord]; omega

theorem mayRecord_room (l : ProbeLimits) (freeMB : Nat) (h : l.minFreeMB ≤ freeMB) : mayRecord l freeMB = true := by
  simp [mayRecord, h]

def line (name op : String) (req : List (String × Json)) (resp : Json) : String :=
  (Json.mkObj [("name", .str name), ("request", Json.mkObj (("op", .str op) :: req)), ("response", resp)]).compress

def memJson (m : Mem) : Json :=
  Json.mkObj [("freeMB", toJson m.freeMB), ("specMB", toJson m.specMB), ("purgMB", toJson m.purgMB), ("fileMB", toJson m.fileMB),
    ("fileMinMB", toJson m.fileMinMB), ("press", toJson m.press), ("comprMBPerMin", toJson m.comprMBPerMin),
    ("swapOutMBPerMin", toJson m.swapOutMBPerMin)]

def readingJson (r : Reading) : Json :=
  Json.mkObj [("time", toJson r.s.time), ("loadCenti", toJson r.s.loadCenti), ("mem", memJson r.s.mem), ("ramMB", toJson r.s.ramMB),
    ("compressorMB", toJson r.s.compressorMB), ("holders", toJson r.holders)]

def decisionJson : Decision → Json
  | .accept => Json.mkObj [("decision", "accept")]
  | .stale => Json.mkObj [("decision", "stale")]
  | .refuse ph ws => Json.mkObj [("decision", "refuse"), ("phase", .str (match ph with | .before => "before" | .after => "after")),
      ("why", .arr (ws.map (fun w => Json.str w.name)).toArray)]

def okRead (t : Nat) : Reading :=
  { s := { time := t, loadCenti := 120, mem := { freeMB := 3000 }, ramMB := 16384, compressorMB := 800, cores := 8 }, holders := 0 }

set_option compiler.extract_closed false in
def quietLines (_ : Unit := ()) : List String :=
  let case := fun (nm : String) (fl : Nat) (b a : Reading) =>
    line nm "measure.judge" [("floorCenti", toJson fl), ("before", readingJson b), ("after", readingJson a)] (decisionJson (judge {} {} fl b a))
  let ok := okRead 100
  [ case "both quiet: accept" 150 ok (okRead 400),
    case "load over the ceiling before" 150 { ok with s := { ok.s with loadCenti := 251 } } (okRead 400),
    case "load at the ceiling is quiet" 150 { ok with s := { ok.s with loadCenti := 250 } } (okRead 400),
    case "floor 400: load 500 is quiet" 400 { ok with s := { ok.s with loadCenti := 500 } } { okRead 400 with s := { (okRead 400).s with loadCenti := 500 } },
    case "floor 400: load 501 after is refused" 400 { ok with s := { ok.s with loadCenti := 500 } } { okRead 400 with s := { (okRead 400).s with loadCenti := 501 } },
    case "floor 0: load 101 is refused" 0 { ok with s := { ok.s with loadCenti := 101 } } (okRead 400),
    case "low memory before" 150 { ok with s := { ok.s with mem := { freeMB := 1023 } } } (okRead 400),
    case "pressure warn before" 150 { ok with s := { ok.s with mem := { freeMB := 3000, press := 2 } } } (okRead 400),
    case "pages leaving for swap after" 150 ok { okRead 400 with s := { (okRead 400).s with mem := { freeMB := 3000, swapOutMBPerMin := 64 } } },
    case "compressor taking in after" 150 ok { okRead 400 with s := { (okRead 400).s with mem := { freeMB := 3000, comprMBPerMin := 1500 } } },
    case "compressor 40 percent of RAM after" 150 ok { okRead 400 with s := { (okRead 400).s with compressorMB := 6554 } },
    case "another slot holder after" 150 ok { okRead 400 with holders := 1 },
    case "several reasons before" 150 { ok with holders := 2, s := { ok.s with loadCenti := 900 } } (okRead 400),
    case "after earlier than before" 150 (okRead 400) (okRead 100),
    case "gap of 1800 s is accepted" 150 ok (okRead 1900),
    case "gap of 1801 s is stale" 150 ok (okRead 1901) ]

def baseRead (t c : Nat) : Reading := { okRead t with s := { (okRead t).s with loadCenti := c } }

set_option compiler.extract_closed false in
def floorLines (_ : Unit := ()) : List String :=
  let steady := [330, 340, 335, 345, 330, 350, 340, 335].zipIdx.map fun (c, i) => baseRead (1000 + 10 * i) c
  let rsJson := fun (rs : List Reading) => Json.arr (rs.map readingJson).toArray
  let optJson := fun (o : Option Nat) => match o with | some n => toJson n | none => Json.null
  let case := fun (nm : String) (rs : List Reading) =>
    line nm "measure.floor" [("readings", rsJson rs)] (Json.mkObj [("floorCenti", optJson (baselineFloor {} {} rs))])
  let sim := fun (nm : String) (boot : Nat) (rs : List Reading) =>
    line nm "measure.simFloor" [("boot", toJson boot), ("readings", rsJson rs)] (Json.mkObj [("floorCenti", optJson (simFloor {} {} boot rs))])
  let late := [330, 340, 335, 345, 330, 350, 340, 335].zipIdx.map fun (c, i) => baseRead (1130 + 10 * i) c
  [ case "eight steady readings: the median" steady,
    case "seven readings are too few" (steady.take 7),
    case "no readings" [],
    case "one other holder spoils the baseline" (steady.map fun r => if r.s.time = 1030 then { r with holders := 1 } else r),
    case "low memory in one reading spoils the baseline" (steady.map fun r => if r.s.time = 1050 then { r with s := { r.s with mem := { freeMB := 500 } } } else r),
    case "spread of 150 is steady" (steady.map fun r => if r.s.time = 1000 then { r with s := { r.s with loadCenti := 200 } } else if r.s.time = 1010 then { r with s := { r.s with loadCenti := 350 } } else r),
    case "spread of 151 is not" (steady.map fun r => if r.s.time = 1000 then { r with s := { r.s with loadCenti := 199 } } else if r.s.time = 1010 then { r with s := { r.s with loadCenti := 350 } } else r),
    case "a load decaying after a boot is no baseline" ([900, 800, 700, 600, 500, 450, 400, 350].zipIdx.map fun (c, i) => baseRead (1000 + 10 * i) c),
    case "median 800 is the highest floor" ((List.replicate 8 800).zipIdx.map fun (c, i) => baseRead (1000 + 10 * i) c),
    case "median 801 is a busy machine, not an idle one" ((List.replicate 8 801).zipIdx.map fun (c, i) => baseRead (1000 + 10 * i) c),
    sim "settled readings give the floor" 1000 late,
    sim "readings before the settle period are left out" 1000 (steady ++ late),
    sim "readings up to 119 s after the boot are all left out" 1000 ((List.range 8).map fun i => baseRead (1112 + i) (330 + i)),
    sim "settle ends exactly 120 s after the boot" 1000 ((List.range 8).map fun i => baseRead (1120 + i) (330 + i)) ]

set_option compiler.extract_closed false in
def cadenceLines (_ : Unit := ()) : List String :=
  let case := fun (nm : String) (frames : Nat) (ivs : List Nat) =>
    let s := stat frames ivs
    line nm "measure.stat" [("frames", toJson frames), ("ivs", toJson ivs)]
      (Json.mkObj [("frames", toJson s.frames), ("long", toJson s.long), ("skipped", toJson s.skipped), ("slot", toJson (slotOf ivs)),
        ("p50", toJson s.p50), ("p95", toJson s.p95), ("mx", toJson s.mx)])
  [ case "no intervals" 0 [], case "one frame" 1 [],
    case "steady 60 Hz" 6 [166, 167, 167, 166, 167],
    case "steady 120 Hz" 6 [83, 84, 83, 83, 84],
    case "one dropped slot at 60 Hz" 6 [167, 167, 334, 167, 167],
    case "a 100 ms stall at 60 Hz" 6 [167, 167, 1000, 167, 167],
    case "1.4 slots rounds to one" 4 [167, 234, 167],
    case "1.5 slots rounds to two" 4 [167, 251, 167],
    case "25 ms is not long, 25.1 is" 5 [250, 251, 167, 167],
    case "tenth-ms jitter around 120 Hz" 8 [83, 90, 76, 83, 124, 83, 126] ]

set_option compiler.extract_closed false in
def outcomeLines (_ : Unit := ()) : List String :=
  let case := fun (nm : String) (arm base : List Nat) =>
    line nm "measure.outcome" [("arm", toJson arm), ("base", toJson base)] (Json.mkObj [("outcome", .str (outcome {} arm base).name)])
  [ case "every default pass above every arm pass" [0, 1, 1] [2, 3, 4],
    case "every arm pass above every default pass" [5, 6, 7] [1, 2, 4],
    case "overlapping ranges are the same" [1, 3, 5] [2, 4, 6],
    case "equal counts are the same" [2, 2, 2] [2, 2, 2],
    case "two arm passes are too few" [0, 0] [5, 5, 5],
    case "two default passes are too few" [0, 0, 0] [5, 5],
    case "no passes" [] [],
    case "touching ranges are the same" [1, 2, 3] [3, 4, 5] ]

set_option compiler.extract_closed false in
def keptLines (_ : Unit := ()) : List String :=
  let d := fun (n : String) => match n with
    | "a" => Decision.accept | "s" => Decision.stale
    | "rb" => Decision.refuse .before [Why.load] | _ => Decision.refuse .after [Why.holders]
  let case := fun (nm : String) (names : List String) =>
    let xs := names.zipIdx.map fun (n, i) => (d n, i * 10)
    line nm "measure.kept" [("decisions", toJson names), ("values", toJson (xs.map (·.2)))] (Json.mkObj [("kept", toJson (kept xs))])
  [ case "all accepted" ["a", "a", "a"], case "refused and stale left out" ["a", "rb", "s", "a", "ra", "a"], case "none" [] ]

set_option compiler.extract_closed false in
def traceLines (_ : Unit := ()) : List String :=
  let case := fun (nm : String) (fin : Bool) (rows : Nat) =>
    line nm "measure.trace" [("finalized", .bool fin), ("rows", toJson rows)] (Json.mkObj [("recorded", .bool (hitchesRecorded fin rows))])
  [ case "finalized with rows" true 42, case "finalized, empty table" true 0, case "never finalized" false 42 ]

set_option compiler.extract_closed false in
def probeLines (_ : Unit := ()) : List String :=
  let l : ProbeLimits := {}
  let look := fun (nm : String) (e lim mb : Nat) (alive : Bool) =>
    line nm "measure.probeAct" [("elapsedS", toJson e), ("limitS", toJson lim), ("traceMB", toJson mb), ("parentAlive", .bool alive)]
      (Json.mkObj [("act", .str (probeAct l { elapsedS := e, limitS := lim, traceMB := mb, parentAlive := alive }).name)])
  let room := fun (nm : String) (mb : Nat) =>
    line nm "measure.mayRecord" [("freeMB", toJson mb)] (Json.mkObj [("may", .bool (mayRecord l mb))])
  [ line "probe limits" "measure.probeParams" []
      (Json.mkObj [("graceS", toJson l.graceS), ("hardGraceS", toJson l.hardGraceS), ("maxTraceMB", toJson l.maxTraceMB), ("minFreeMB", toJson l.minFreeMB)]),
    look "inside the time limit" 3 6 10 true,
    look "just before the grace" 65 6 10 true,
    look "grace reached: interrupt" 66 6 10 true,
    look "just before the hard deadline" 125 6 10 true,
    look "hard deadline reached: kill" 126 6 10 true,
    look "far past the deadline: kill" 4000 6 10 true,
    look "trace at the cap is fine" 3 6 12288 true,
    look "trace over the cap: kill" 3 6 12289 true,
    look "parent gone: kill at once" 0 6 0 false,
    look "parent gone during the grace: kill, not interrupt" 70 6 10 false,
    room "free disk at the minimum" 30720, room "free disk one MB under" 30719, room "no free disk" 0 ]

def paramsLine : String :=
  let q : QParams := {}
  line "default parameters" "measure.params" []
    (Json.mkObj [("loadMarginCenti", toJson q.loadMarginCenti), ("holdersMax", toJson q.holdersMax), ("minPasses", toJson q.minPasses),
      ("maxGapS", toJson q.maxGapS), ("baseMinSamples", toJson q.baseMinSamples), ("baseSpreadCenti", toJson q.baseSpreadCenti),
      ("floorMaxCenti", toJson q.floorMaxCenti), ("settleS", toJson q.settleS), ("longTenths", toJson longTenths)])

set_option compiler.extract_closed false in
def goldenLines (_ : Unit := ()) : List String :=
  [paramsLine] ++ quietLines () ++ floorLines () ++ cadenceLines () ++ outcomeLines () ++ keptLines () ++ traceLines () ++ probeLines ()

def genPath : System.FilePath := "../packages/contracts/golden/sup/measure.jsonl"

set_option compiler.extract_closed false in
def genText (_ : Unit := ()) : String := String.join ((goldenLines ()).map (· ++ "\n"))

def gen (args : List String) : IO Unit := do
  if args.contains "--check" then
    let cur ← IO.FS.readFile genPath
    if cur != genText () then
      throw (IO.userError s!"sup-measure: {genPath} is stale; regenerate with Fw.Sup.Measure.gen []")
    IO.println s!"sup-measure: {genPath} equals the Lean output"
  else
    IO.FS.createDirAll "../packages/contracts/golden/sup"
    IO.FS.writeFile genPath (genText ())

end Fw.Sup.Measure
