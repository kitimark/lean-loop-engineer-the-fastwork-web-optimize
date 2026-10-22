import Lean.Data.Json
import Fw.Sup.Adapt
import Fw.Gate.Smooth
/-!
# Quiet rule and per-zone cadence of the local Safari lane (task mac-safari-measure)
A pass counts only when the machine was quiet before and after it; the kept passes reduce to cadence statistics and a verdict against the default arm.
-/
namespace Fw.Sup.Measure
open Lean (Json ToJson toJson)
open Fw.Sup.Adapt

/-! ## The quiet rule -/

/-- Limits of the quiet rule: load ceiling (centi), other live slot holders allowed, passes a verdict needs, longest span between the two readings. -/
structure QParams where
  loadMaxCenti : Nat := 250
  holdersMax : Nat := 0
  minPasses : Nat := 3
  maxGapS : Nat := 1800
deriving DecidableEq, Repr

/-- Why a reading is not quiet. -/
inductive Why where
  | load | avail | pressure | swapOut | compress | holders
deriving DecidableEq, Repr

def Why.name : Why → String
  | .load => "load" | .avail => "avail" | .pressure => "pressure" | .swapOut => "swapOut" | .compress => "compress"
  | .holders => "holders"

/-- A sampler reading and the number of live slot holders other than the measuring lease. -/
structure Reading where
  s : Sample
  holders : Nat
deriving DecidableEq, Repr

/-- Every reason a reading is not quiet, in a fixed order. -/
def whys (q : QParams) (p : Params) (r : Reading) : List Why :=
  (if q.loadMaxCenti < r.s.loadCenti then [Why.load] else []) ++
  (if r.s.avail < p.floorMB then [Why.avail] else []) ++
  (if r.s.mem.press ≠ 1 then [Why.pressure] else []) ++
  (if swapActive p r.s.mem then [Why.swapOut] else []) ++
  (if thrash p r.s.mem || cmprsHigh p r.s then [Why.compress] else []) ++
  (if q.holdersMax < r.holders then [Why.holders] else [])

def quiet (q : QParams) (p : Params) (r : Reading) : Bool := (whys q p r).isEmpty

theorem quiet_iff (q : QParams) (p : Params) (r : Reading) :
    quiet q p r = true ↔ (r.s.loadCenti ≤ q.loadMaxCenti ∧ p.floorMB ≤ r.s.avail ∧ r.s.mem.press = 1 ∧
      swapActive p r.s.mem = false ∧ thrash p r.s.mem = false ∧ cmprsHigh p r.s = false ∧ r.holders ≤ q.holdersMax) := by
  simp only [quiet, whys, List.isEmpty_iff, List.append_eq_nil_iff, ite_eq_right_iff, reduceCtorEq, imp_false, Nat.not_lt,
    Bool.or_eq_true, not_or, ne_eq, Decidable.not_not, Bool.not_eq_true]
  simp only [Sample.avail] at *
  constructor
  · rintro ⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5, h6⟩, h7⟩
    exact ⟨h1, h2, h3, h4, h5, h6, h7⟩
  · rintro ⟨h1, h2, h3, h4, h5, h6, h7⟩
    exact ⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5, h6⟩, h7⟩

theorem not_quiet_load (q : QParams) (p : Params) (r : Reading) (h : q.loadMaxCenti < r.s.loadCenti) :
    quiet q p r = false := by
  simp [quiet, whys, h]

theorem not_quiet_avail (q : QParams) (p : Params) (r : Reading) (h : r.s.avail < p.floorMB) :
    quiet q p r = false := by
  simp [quiet, whys, h]

theorem not_quiet_pressure (q : QParams) (p : Params) (r : Reading) (h : r.s.mem.press ≠ 1) :
    quiet q p r = false := by
  simp [quiet, whys, h]

theorem not_quiet_swapOut (q : QParams) (p : Params) (r : Reading) (h : swapActive p r.s.mem = true) :
    quiet q p r = false := by
  simp [quiet, whys, h]

theorem not_quiet_thrash (q : QParams) (p : Params) (r : Reading) (h : thrash p r.s.mem = true) :
    quiet q p r = false := by
  simp [quiet, whys, h]

theorem not_quiet_cmprs (q : QParams) (p : Params) (r : Reading) (h : cmprsHigh p r.s = true) :
    quiet q p r = false := by
  simp [quiet, whys, h]

theorem not_quiet_holders (q : QParams) (p : Params) (r : Reading) (h : q.holdersMax < r.holders) :
    quiet q p r = false := by
  simp [quiet, whys, h]

/-- A quiet reading is not an overload of the slot limit, when the quiet load ceiling is below the overload one and swap is not rising. -/
theorem quiet_not_overloaded (q : QParams) (p : Params) (r : Reading) (prev : Option (Nat × Nat))
    (hq : quiet q p r = true) (hl : q.loadMaxCenti < p.highCenti) (hs : swapRising p prev r.s = false) :
    overloaded p prev r.s = false := by
  obtain ⟨h1, h2, h3, h4, h5, h6, -⟩ := (quiet_iff q p r).1 hq
  have hl' : loadHigh p r.s = false := by simp [loadHigh]; omega
  have hm : memLow p r.s.mem = false := by
    have : availMB r.s.mem = r.s.avail := rfl
    simp [memLow, this, h3, h4, h5]; omega
  simp [overloaded, hl', hm, h6, hs]

/-- A lower load never turns a quiet reading into a refused one. -/
theorem quiet_load_antitone (q : QParams) (p : Params) (r : Reading) (c : Nat) (hq : quiet q p r = true)
    (hc : c ≤ r.s.loadCenti) : quiet q p { r with s := { r.s with loadCenti := c } } = true := by
  have := (quiet_iff q p r).1 hq
  rw [quiet_iff]
  have e : ({ r with s := { r.s with loadCenti := c } } : Reading).s.avail = r.s.avail := rfl
  simp only [Sample.avail] at *
  obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := this
  refine ⟨?_, h2, h3, h4, h5, ?_, h7⟩
  · exact Nat.le_trans hc h1
  · simpa [cmprsHigh] using h6

/-! ## Decision on one pass -/

inductive Phase where
  | before | after
deriving DecidableEq, Repr

/-- The decision on a pass from the readings taken before and after it. -/
inductive Decision where
  | accept
  | refuse (ph : Phase) (ws : List Why)
  | stale
deriving DecidableEq, Repr

def judge (q : QParams) (p : Params) (b a : Reading) : Decision :=
  if quiet q p b = false then .refuse .before (whys q p b)
  else if quiet q p a = false then .refuse .after (whys q p a)
  else if a.s.time < b.s.time ∨ b.s.time + q.maxGapS < a.s.time then .stale
  else .accept

theorem judge_refuse_before (q : QParams) (p : Params) (b a : Reading) (h : quiet q p b = false) :
    judge q p b a = .refuse .before (whys q p b) := by
  simp [judge, h]

theorem judge_refuse_after (q : QParams) (p : Params) (b a : Reading) (hb : quiet q p b = true) (h : quiet q p a = false) :
    judge q p b a = .refuse .after (whys q p a) := by
  simp [judge, hb, h]

theorem judge_stale_order (q : QParams) (p : Params) (b a : Reading) (hb : quiet q p b = true) (ha : quiet q p a = true)
    (h : a.s.time < b.s.time) : judge q p b a = .stale := by
  simp [judge, hb, ha, h]

theorem judge_stale_gap (q : QParams) (p : Params) (b a : Reading) (hb : quiet q p b = true) (ha : quiet q p a = true)
    (h : b.s.time + q.maxGapS < a.s.time) : judge q p b a = .stale := by
  simp [judge, hb, ha, h]

theorem judge_accept (q : QParams) (p : Params) (b a : Reading) (hb : quiet q p b = true) (ha : quiet q p a = true)
    (h1 : b.s.time ≤ a.s.time) (h2 : a.s.time ≤ b.s.time + q.maxGapS) : judge q p b a = .accept := by
  have h1' : ¬ a.s.time < b.s.time := by omega
  have h2' : ¬ b.s.time + q.maxGapS < a.s.time := by omega
  simp [judge, hb, ha, h1', h2']

/-- A pass is accepted only when both readings are quiet. -/
theorem judge_accept_quiet (q : QParams) (p : Params) (b a : Reading) (h : judge q p b a = .accept) :
    quiet q p b = true ∧ quiet q p a = true := by
  unfold judge at h
  by_cases hb : quiet q p b = false
  · simp [hb] at h
  · by_cases ha : quiet q p a = false
    · simp [hb, ha] at h
    · simp at hb ha
      exact ⟨hb, ha⟩

/-! ## Cadence of one window -/

/-- A frame interval above this many tenths of a millisecond counts as long (25 ms). -/
def longTenths : Nat := 250

def sortNat (l : List Nat) : List Nat := l.mergeSort fun a b => decide (a ≤ b)

/-- Nearest-rank percentile of tenths-of-ms intervals (0 for none). -/
def pct (k : Nat) (ivs : List Nat) : Nat :=
  (sortNat ivs).getD (max 1 ((k * ivs.length + 99) / 100) - 1) 0

/-- The refresh slot in tenths of ms: 8.3 ms when the median interval is under 12.5 ms, else 16.7 ms. -/
def slotOf (ivs : List Nat) : Nat := if pct 50 ivs < 125 then 83 else 167

/-- Whole refresh slots missed over a window: each interval counts its rounded number of slots, less the one it is owed. -/
def skipped (slot : Nat) (ivs : List Nat) : Nat := (ivs.map fun i => (2 * i + slot) / (2 * slot) - 1).sum

def longCount (ivs : List Nat) : Nat := ivs.countP fun i => decide (longTenths < i)

/-- The statistics of one window: frames, intervals over 25 ms, skipped slots, p50, p95 and max interval (tenths of ms). -/
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

/-- Percentiles are ordered: a lower rank never reads a longer interval. -/
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

/-- The 100th percentile is the longest interval, and it is one of them. -/
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

/-- A window whose intervals are all under one and a half slots skipped nothing. -/
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

/-- An interval of at least two slots (rounded) is a skipped slot. -/
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

/-! ## Verdict against the default arm -/

inductive Outcome where
  | better | worse | same | insufficient
deriving DecidableEq, Repr

def Outcome.name : Outcome → String
  | .better => "better" | .worse => "worse" | .same => "same" | .insufficient => "insufficient"

/-- Per-pass counts of a metric (lower is smoother) of an arm against the default's: better when every default pass is above every arm pass. -/
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

/-- The default judged against itself is never told apart. -/
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

/-- The passes kept by the quiet rule: a refused or stale pass is not in the list. -/
def kept (xs : List (Decision × Nat)) : List Nat := xs.filterMap fun d => if d.1 = .accept then some d.2 else none

theorem kept_length_le (xs : List (Decision × Nat)) : (kept xs).length ≤ xs.length := List.length_filterMap_le _ _

theorem kept_refused (ph : Phase) (ws : List Why) (v : Nat) (xs : List (Decision × Nat)) :
    kept ((.refuse ph ws, v) :: xs) = kept xs := by
  simp [kept]

theorem kept_stale (v : Nat) (xs : List (Decision × Nat)) : kept ((.stale, v) :: xs) = kept xs := by
  simp [kept]

theorem kept_accept (v : Nat) (xs : List (Decision × Nat)) : kept ((.accept, v) :: xs) = v :: kept xs := by
  simp [kept]

/-! ## The local trace probe -/

/-- A trace records hitches when it finalized and its hitches table has a row. -/
def hitchesRecorded (finalized : Bool) (rows : Nat) : Bool := finalized && decide (0 < rows)

theorem hitches_not_finalized (rows : Nat) : hitchesRecorded false rows = false := rfl

theorem hitches_no_rows (fin : Bool) : hitchesRecorded fin 0 = false := by simp [hitchesRecorded]

theorem hitches_recorded (rows : Nat) (h : 0 < rows) : hitchesRecorded true rows = true := by simp [hitchesRecorded, h]

/-! ## Golden vectors -/

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

def quietLines : List String :=
  let case := fun (nm : String) (b a : Reading) =>
    line nm "measure.judge" [("before", readingJson b), ("after", readingJson a)] (decisionJson (judge {} {} b a))
  let ok := okRead 100
  [ case "both quiet: accept" ok (okRead 400),
    case "load over the ceiling before" { ok with s := { ok.s with loadCenti := 251 } } (okRead 400),
    case "load at the ceiling is quiet" { ok with s := { ok.s with loadCenti := 250 } } (okRead 400),
    case "low memory before" { ok with s := { ok.s with mem := { freeMB := 1023 } } } (okRead 400),
    case "pressure warn before" { ok with s := { ok.s with mem := { freeMB := 3000, press := 2 } } } (okRead 400),
    case "pages leaving for swap after" ok { okRead 400 with s := { (okRead 400).s with mem := { freeMB := 3000, swapOutMBPerMin := 64 } } },
    case "compressor taking in after" ok { okRead 400 with s := { (okRead 400).s with mem := { freeMB := 3000, comprMBPerMin := 1500 } } },
    case "compressor 40 percent of RAM after" ok { okRead 400 with s := { (okRead 400).s with compressorMB := 6554 } },
    case "another slot holder after" ok { okRead 400 with holders := 1 },
    case "several reasons before" { ok with holders := 2, s := { ok.s with loadCenti := 900 } } (okRead 400),
    case "after earlier than before" (okRead 400) (okRead 100),
    case "gap of 1800 s is accepted" ok (okRead 1900),
    case "gap of 1801 s is stale" ok (okRead 1901) ]

def cadenceLines : List String :=
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

def outcomeLines : List String :=
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

def keptLines : List String :=
  let d := fun (n : String) => match n with
    | "a" => Decision.accept | "s" => Decision.stale
    | "rb" => Decision.refuse .before [Why.load] | _ => Decision.refuse .after [Why.holders]
  let case := fun (nm : String) (names : List String) =>
    let xs := names.zipIdx.map fun (n, i) => (d n, i * 10)
    line nm "measure.kept" [("decisions", toJson names), ("values", toJson (xs.map (·.2)))] (Json.mkObj [("kept", toJson (kept xs))])
  [ case "all accepted" ["a", "a", "a"], case "refused and stale left out" ["a", "rb", "s", "a", "ra", "a"], case "none" [] ]

def traceLines : List String :=
  let case := fun (nm : String) (fin : Bool) (rows : Nat) =>
    line nm "measure.trace" [("finalized", .bool fin), ("rows", toJson rows)] (Json.mkObj [("recorded", .bool (hitchesRecorded fin rows))])
  [ case "finalized with rows" true 42, case "finalized, empty table" true 0, case "never finalized" false 42 ]

def paramsLine : String :=
  let q : QParams := {}
  line "default parameters" "measure.params" []
    (Json.mkObj [("loadMaxCenti", toJson q.loadMaxCenti), ("holdersMax", toJson q.holdersMax), ("minPasses", toJson q.minPasses),
      ("maxGapS", toJson q.maxGapS), ("longTenths", toJson longTenths)])

set_option compiler.extract_closed false in
def goldenLines (_ : Unit := ()) : List String :=
  [paramsLine] ++ quietLines ++ cadenceLines ++ outcomeLines ++ keptLines ++ traceLines

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
