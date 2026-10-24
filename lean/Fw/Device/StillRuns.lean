import Lean.Data.Json
import Fw.Device.Session
/-!
# Still runs of `scrollY` and the throttle-lift verdict
The still-run count of `packages/measure-webkit/src/throttle/stillruns.mjs` and the verdict of the toolbar-throttle probe.
-/
namespace Fw.Device.StillRuns
open Lean

/-! ## Still runs -/

/-- A value (per mille) inside the exit range. -/
def mid (v : Int) : Bool := decide (0 < v) && decide (v < 1000)

/-- The distance between two positions. -/
def dist (a b : Int) : Int := if a ≤ b then b - a else a - b

/-- A run of `k` frames with the position of the frame before, ended by a move of `jump`; `mid` when every value in it is in the exit range. -/
structure Run where
  k : Nat
  jump : Int
  mid : Bool
  deriving DecidableEq, Repr

/-- Scan the rows after `prev`, with the open run's length `k` and its value flag `m`. A trailing run has no move to end it and is dropped. -/
def scan (prev : Int) (k : Nat) (m : Bool) : List (Int × Int) → List Run
  | [] => []
  | (y, v) :: rest =>
    if y == prev then scan prev (k + 1) (m && mid v) rest
    else if k == 0 then scan y 0 true rest
    else ⟨k, dist prev y, m⟩ :: scan y 0 true rest

/-- The still runs of a part series (`partSeries ys vs`: position, value). -/
def runs : List (Int × Int) → List Run
  | [] => []
  | (y, _) :: rest => scan y 0 true rest

/-- A run in the exit range of `lo` to `hi` frames. -/
def inBand (lo hi : Nat) (r : Run) : Bool := r.mid && decide (lo ≤ r.k) && decide (r.k ≤ hi)

/-- The runs of `lo` to `hi` frames in the exit range. -/
def count (lo hi : Nat) (rows : List (Int × Int)) : Nat := ((runs rows).filter (inBand lo hi)).length

/-- The throttle band: 5 to 6 frames is 100 ms at 17 ms per frame. -/
def bandLo : Nat := 5
def bandHi : Nat := 6

/-- The runs of 5 to 6 frames. -/
def bandRuns (rows : List (Int × Int)) : Nat := count bandLo bandHi rows

/-- The runs of 1 to 9 frames. -/
def shortRuns (rows : List (Int × Int)) : Nat := count 1 9 rows

/-- The frames whose value is in the exit range. -/
def exitFrames (rows : List (Int × Int)) : Nat := (rows.filter fun r => mid r.2).length

theorem runs_nil : runs [] = [] := rfl

theorem runs_single (r : Int × Int) : runs [r] = [] := by
  obtain ⟨y, v⟩ := r
  simp [runs, scan]

theorem scan_length_le (prev : Int) : ∀ (rows : List (Int × Int)) (k : Nat) (m : Bool),
    (scan prev k m rows).length ≤ (rows.length + k) / 2
  | [], k, m => by simp [scan]
  | (y, v) :: rest, k, m => by
    have ih1 := scan_length_le prev rest (k + 1) (m && mid v)
    have ih2 := fun p => scan_length_le p rest 0
    simp only [scan, List.length_cons]
    split
    · omega
    · split
      · have := ih2 y true
        omega
      · rename_i hk
        have := ih2 y true
        have hk' : 0 < k := by
          cases k with
          | zero => simp at hk
          | succ n => omega
        simp only [List.length_cons]
        omega

/-- There is at most one run per two frames. -/
theorem runs_length_le (rows : List (Int × Int)) : (runs rows).length ≤ rows.length / 2 := by
  cases rows with
  | nil => simp [runs]
  | cons r rest =>
    have := scan_length_le r.1 rest 0 true
    simp only [runs, List.length_cons]
    omega

theorem count_le_runs (lo hi : Nat) (rows : List (Int × Int)) : count lo hi rows ≤ (runs rows).length :=
  List.length_filter_le _ _

/-- A run counted in a band is counted in the wider one. -/
theorem count_mono {lo hi lo' hi' : Nat} (hl : lo' ≤ lo) (hh : hi ≤ hi') (rows : List (Int × Int)) :
    count lo hi rows ≤ count lo' hi' rows := by
  unfold count
  have key : ∀ l : List Run, (l.filter (inBand lo hi)).length ≤ (l.filter (inBand lo' hi')).length := by
    intro l
    induction l with
    | nil => simp
    | cons r t ih =>
      have himp : inBand lo hi r = true → inBand lo' hi' r = true := by
        intro hr
        simp only [inBand, Bool.and_eq_true, decide_eq_true_eq] at hr ⊢
        obtain ⟨⟨a, b⟩, c⟩ := hr
        exact ⟨⟨a, by omega⟩, by omega⟩
      by_cases h1 : inBand lo hi r = true
      · have h2 := himp h1
        simp [h1, h2, ih]
      · by_cases h2 : inBand lo' hi' r = true
        · simp [h1, h2]
          omega
        · simp [h1, h2, ih]
  exact key _

theorem scan_const (y v : Int) : ∀ (n k : Nat) (m : Bool), scan y k m (List.replicate n (y, v)) = []
  | 0, k, m => by simp [scan]
  | n + 1, k, m => by simp [List.replicate_succ, scan, scan_const y v n]

/-- A position that never moves has no run: a trailing run is not counted. -/
theorem runs_const (y v : Int) (n : Nat) : runs (List.replicate n (y, v)) = [] := by
  cases n with
  | zero => rfl
  | succ n => simp [List.replicate_succ, runs, scan_const]

/-- Whether every position differs from the one before. -/
def allMove : List (Int × Int) → Bool
  | a :: b :: rest => a.1 != b.1 && allMove (b :: rest)
  | _ => true

theorem scan_moving (v : Int) : ∀ (rows : List (Int × Int)) (prev : Int), allMove ((prev, v) :: rows) = true →
    scan prev 0 true rows = []
  | [], prev, _ => by simp [scan]
  | (y, w) :: rest, prev, h => by
    simp only [allMove, Bool.and_eq_true, bne_iff_ne, ne_eq] at h
    have hne : ¬ (y == prev) = true := by simpa [beq_iff_eq] using Ne.symm h.1
    simp [scan, hne, scan_moving w rest y h.2]

/-- A series that moves in every frame has no run. -/
theorem runs_moving (rows : List (Int × Int)) (h : allMove rows = true) : runs rows = [] := by
  cases rows with
  | nil => rfl
  | cons r rest =>
    obtain ⟨y, v⟩ := r
    exact scan_moving v rest y h


/-! ## The throttled series -/

/-- A position that moves once every `p` frames: `p` frames at each position of `ys`, value `v`. -/
def stairs (ys : List Int) (p : Nat) (v : Int) : List (Int × Int) := ys.flatMap fun y => List.replicate p (y, v)

/-- The runs the throttled series has: one of `k` frames per move between neighbouring positions. -/
def stairRuns (k : Nat) (m : Bool) : List Int → List Run
  | y :: y' :: rest => ⟨k, dist y y', m⟩ :: stairRuns k m (y' :: rest)
  | _ => []

/-- A run that opens on a position and stays through `n + 1` more frames of it. -/
theorem scan_plateau (y v : Int) : ∀ (n k : Nat) (m : Bool) (l : List (Int × Int)),
    scan y k m (List.replicate (n + 1) (y, v) ++ l) = scan y (k + n + 1) (m && mid v) l
  | 0, k, m, l => by simp [scan]
  | n + 1, k, m, l => by
    have ih := scan_plateau y v n (k + 1) (m && mid v) l
    rw [List.replicate_succ, List.cons_append, scan]
    simp only [beq_self_eq_true, ite_true]
    rw [ih]
    simp [Nat.add_assoc, Nat.add_comm 1 n]

/-- An open run ends at the first frame at another position. -/
theorem scan_move (prev y v : Int) (k : Nat) (m : Bool) (l : List (Int × Int)) (hk : 0 < k) (hne : y ≠ prev) :
    scan prev k m ((y, v) :: l) = ⟨k, dist prev y, m⟩ :: scan y 0 true l := by
  have h1 : ¬ (y == prev) = true := by simpa using hne
  have h2 : ¬ (k == 0) = true := by simpa using Nat.pos_iff_ne_zero.mp hk
  simp [scan, h1, h2]

/-- Whether neighbouring positions differ. -/
def moves : List Int → Bool
  | a :: b :: rest => a != b && moves (b :: rest)
  | _ => true

theorem scan_stairs (v : Int) (q : Nat) : ∀ (ys : List Int) (y : Int), moves (y :: ys) = true →
    scan y 0 true (List.replicate (q + 1) (y, v) ++ stairs ys (q + 2) v) = stairRuns (q + 1) (mid v) (y :: ys)
  | [], y, _ => by simp [stairs, stairRuns, scan_const]
  | y' :: rest, y, h => by
    simp only [moves, Bool.and_eq_true, bne_iff_ne, ne_eq] at h
    have ih := scan_stairs v q rest y' h.2
    have e : stairs (y' :: rest) (q + 2) v = (y', v) :: (List.replicate (q + 1) (y', v) ++ stairs rest (q + 2) v) := by
      simp [stairs, List.replicate_succ]
    rw [e, scan_plateau]
    rw [scan_move _ _ _ _ _ _ (by omega) (Ne.symm h.1), ih]
    simp [stairRuns]

/-- **A throttled series has one run per move.** A position that changes once every `p ≥ 2` frames, with every value in the
exit range, has exactly one run of `p - 1` frames between neighbouring positions, and the trailing plateau is not counted. -/
theorem runs_stairs (v : Int) (q : Nat) (y : Int) (ys : List Int) (h : moves (y :: ys) = true) :
    runs (stairs (y :: ys) (q + 2) v) = stairRuns (q + 1) (mid v) (y :: ys) := by
  have e : stairs (y :: ys) (q + 2) v = (y, v) :: (List.replicate (q + 1) (y, v) ++ stairs ys (q + 2) v) := by
    simp [stairs, List.replicate_succ]
  rw [e]
  exact scan_stairs v q ys y h


theorem stairRuns_filter (lo hi k : Nat) (m : Bool) (hm : m = true) (hl : lo ≤ k) (hh : k ≤ hi) :
    ∀ l : List Int, ((stairRuns k m l).filter (inBand lo hi)).length = l.length - 1
  | [] => by simp [stairRuns]
  | [_] => by simp [stairRuns]
  | y :: y' :: rest => by
    have ih := stairRuns_filter lo hi k m hm hl hh (y' :: rest)
    have hb : inBand lo hi ⟨k, dist y y', m⟩ = true := by simp [inBand, hm, hl, hh]
    simp only [stairRuns, List.filter_cons, hb, ite_true, List.length_cons] at ih ⊢
    omega

/-- **The throttle band counts every move.** A series that moves once every 6 or 7 frames inside the exit range has one band
run per move. -/
theorem bandRuns_stairs (v : Int) (q : Nat) (hv : mid v = true) (hl : 4 ≤ q) (hh : q ≤ 5) (y : Int) (ys : List Int)
    (h : moves (y :: ys) = true) : bandRuns (stairs (y :: ys) (q + 2) v) = ys.length := by
  unfold bandRuns count
  rw [runs_stairs v q y ys h, stairRuns_filter bandLo bandHi (q + 1) (mid v) hv (by simp [bandLo]; omega)
    (by simp [bandHi]; omega)]
  simp

/-- A series outside the exit range has no band run. -/
theorem bandRuns_stairs_out (v : Int) (q : Nat) (hv : mid v = false) (y : Int) (ys : List Int)
    (h : moves (y :: ys) = true) : bandRuns (stairs (y :: ys) (q + 2) v) = 0 := by
  unfold bandRuns count
  rw [runs_stairs v q y ys h]
  have : ∀ l : List Int, ((stairRuns (q + 1) (mid v) l).filter (inBand bandLo bandHi)).length = 0 := by
    intro l
    induction l with
    | nil => simp [stairRuns]
    | cons a t ih =>
      cases t with
      | nil => simp [stairRuns]
      | cons b u =>
        simp only [stairRuns, List.filter_cons]
        simp [inBand, hv] at ih ⊢
        exact ih
  exact this _

/-! ## Why 5 to 6 frames -/

/-- The still frames between two updates that arrive 100 ms apart, at a frame interval of `d` hundredths of a millisecond: the frames
until the first one at or after 100 ms, less the one that moves. -/
def throttleK (d : Nat) : Nat := (10000 + d - 1) / d - 1

theorem throttleK_60hz : throttleK 1667 = 5 := by decide
theorem throttleK_slow : throttleK 1700 = 5 := by decide
theorem throttleK_fast : throttleK 1600 = 6 := by decide

/-- **The band holds for 14.3 to 20 ms frames.** Every interval from 1429 to 1999 hundredths of a millisecond gives 5 or 6 still frames,
so a 100 ms throttle shows up in the band at any rate between 50 and 70 Hz. -/
theorem throttleK_mem_band (d : Nat) (h1 : 1429 ≤ d) (h2 : d < 2000) : bandLo ≤ throttleK d ∧ throttleK d ≤ bandHi := by
  have hd : 0 < d := by omega
  have a : 6 ≤ (10000 + d - 1) / d := (Nat.le_div_iff_mul_le hd).2 (by omega)
  have b : (10000 + d - 1) / d < 8 := (Nat.div_lt_iff_lt_mul hd).2 (by omega)
  unfold throttleK bandLo bandHi
  omega

/-! ## The verdict -/

/-- The counts of one arm over all its passes. -/
structure Arm where
  runs : Nat
  frames : Nat
  deriving DecidableEq, Repr

/-- What the probe found. -/
inductive Verdict where
  | lifted | notLifted | noData | confounded
  deriving DecidableEq, Repr

/-- The word written in the output. -/
def Verdict.name : Verdict → String
  | .lifted => "lifted" | .notLifted => "not-lifted" | .noData => "no-data" | .confounded => "confounded"

/-- Whether every viewport height equals the first. -/
def sameHeight : List Int → Bool
  | [] => true
  | h :: t => t.all (· == h)

/-- The fewest band runs the baseline arm needs for a comparison. -/
def minBase : Nat := 10

/-- The lift arm's rate must be at most one in `dropDen` of the baseline's. -/
def dropDen : Nat := 5

/-- The probe verdict: the heights of every pass of every arm must be equal; the baseline needs `minBase` band runs and both arms some exit
frames; then the lift arm's band runs per exit frame, times `dropDen`, must not exceed the baseline's. -/
def verdict (hs : List Int) (base lift : Arm) : Verdict :=
  if !sameHeight hs then .confounded
  else if base.runs < minBase || base.frames == 0 || lift.frames == 0 then .noData
  else if lift.runs * base.frames * dropDen ≤ base.runs * lift.frames then .lifted
  else .notLifted

theorem verdict_confounded {hs : List Int} (h : sameHeight hs = false) (base lift : Arm) :
    verdict hs base lift = .confounded := by
  simp [verdict, h]

theorem verdict_noData_base {hs : List Int} (hh : sameHeight hs = true) {base : Arm} (lift : Arm)
    (h : base.runs < minBase) : verdict hs base lift = .noData := by
  simp [verdict, hh, h]

theorem verdict_noData_frames {hs : List Int} (hh : sameHeight hs = true) {base lift : Arm}
    (h : base.frames = 0 ∨ lift.frames = 0) : verdict hs base lift = .noData := by
  rcases h with h | h <;> simp [verdict, hh, h]

theorem verdict_lifted {hs : List Int} (hh : sameHeight hs = true) {base lift : Arm} (h1 : minBase ≤ base.runs)
    (h2 : 0 < base.frames) (h3 : 0 < lift.frames) (h4 : lift.runs * base.frames * dropDen ≤ base.runs * lift.frames) :
    verdict hs base lift = .lifted := by
  have : ¬ base.runs < minBase := by omega
  simp [verdict, hh, this, Nat.pos_iff_ne_zero.mp h2, Nat.pos_iff_ne_zero.mp h3, h4]

theorem verdict_notLifted {hs : List Int} (hh : sameHeight hs = true) {base lift : Arm} (h1 : minBase ≤ base.runs)
    (h2 : 0 < base.frames) (h3 : 0 < lift.frames) (h4 : ¬ lift.runs * base.frames * dropDen ≤ base.runs * lift.frames) :
    verdict hs base lift = .notLifted := by
  have : ¬ base.runs < minBase := by omega
  simp [verdict, hh, this, Nat.pos_iff_ne_zero.mp h2, Nat.pos_iff_ne_zero.mp h3, h4]

/-- A lifted verdict means the lift arm's rate is at most a fifth of the baseline's, whatever the heights. -/
theorem lifted_rate {hs : List Int} {base lift : Arm} (h : verdict hs base lift = .lifted) :
    lift.runs * base.frames * dropDen ≤ base.runs * lift.frames := by
  unfold verdict at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · assumption
      · simp at h


open Fw.Device.Session (Class classes partSeries)

structure CRun where
  run : Run
  cls : Class
  deriving DecidableEq, Repr

def clsOf (mv : Bool) : Class := if mv then .moving else .still

def scanC (prev : Int) (k : Nat) (m : Bool) (mv : Bool) : List (Int × Int × Class) → List CRun
  | [] => []
  | (y, v, c) :: rest =>
    if y == prev then scanC prev (k + 1) (m && mid v) (mv || c == .moving) rest
    else if k == 0 then scanC y 0 true (c == .moving) rest
    else ⟨⟨k, dist prev y, m⟩, clsOf (mv || c == .moving)⟩ :: scanC y 0 true (c == .moving) rest

def runsC : List (Int × Int × Class) → List CRun
  | [] => []
  | (y, _, c) :: rest => scanC y 0 true (c == .moving) rest

def dropClass (rows : List (Int × Int × Class)) : List (Int × Int) := rows.map fun r => (r.1, r.2.1)

theorem scanC_run (prev : Int) : ∀ (rows : List (Int × Int × Class)) (k : Nat) (m mv : Bool),
    (scanC prev k m mv rows).map (·.run) = scan prev k m (dropClass rows)
  | [], k, m, mv => by simp [scanC, scan, dropClass]
  | (y, v, c) :: rest, k, m, mv => by
    have ih1 := scanC_run prev rest (k + 1) (m && mid v) (mv || c == .moving)
    have ih2 := fun p mv' => scanC_run p rest 0 true mv'
    simp only [scanC, scan, dropClass, List.map_cons] at ih1 ih2 ⊢
    split
    · exact ih1
    · split
      · exact ih2 y _
      · simp only [List.map_cons]
        rw [ih2 y _]

theorem runsC_run (rows : List (Int × Int × Class)) : (runsC rows).map (·.run) = runs (dropClass rows) := by
  cases rows with
  | nil => simp [runsC, runs, dropClass]
  | cons r rest =>
    obtain ⟨y, v, c⟩ := r
    simp only [runsC, runs, dropClass, List.map_cons]
    exact scanC_run y rest 0 true _


def countC (c : Class) (lo hi : Nat) (rows : List (Int × Int × Class)) : Nat :=
  ((runsC rows).filter fun r => r.cls == c && inBand lo hi r.run).length

def exitFramesC (c : Class) (rows : List (Int × Int × Class)) : Nat :=
  (rows.filter fun r => r.2.2 == c && mid r.2.1).length

theorem countC_split (lo hi : Nat) (rows : List (Int × Int × Class)) :
    countC .moving lo hi rows + countC .still lo hi rows = count lo hi (dropClass rows) := by
  have key : ∀ l : List CRun, (l.filter fun r => r.cls == Class.moving && inBand lo hi r.run).length +
      (l.filter fun r => r.cls == Class.still && inBand lo hi r.run).length =
        ((l.map (·.run)).filter (inBand lo hi)).length := by
    intro l
    induction l with
    | nil => simp
    | cons r t ih =>
      obtain ⟨u, c⟩ := r
      cases c <;> by_cases hb : inBand lo hi u = true <;> simp [hb] at ih ⊢ <;> omega
  unfold countC count
  rw [← runsC_run]
  exact key _

theorem exitFramesC_split (rows : List (Int × Int × Class)) :
    exitFramesC .moving rows + exitFramesC .still rows = exitFrames (dropClass rows) := by
  unfold exitFramesC exitFrames dropClass
  induction rows with
  | nil => simp
  | cons r t ih =>
    obtain ⟨y, v, c⟩ := r
    cases c <;> by_cases hv : mid v = true <;> simp [hv] at ih ⊢ <;> omega

theorem scanC_still : ∀ (prev : Int) (rows : List (Int × Int × Class)) (k : Nat) (m : Bool),
    (∀ r ∈ rows, r.2.2 = Class.still) → ∀ x ∈ scanC prev k m false rows, x.cls = Class.still
  | prev, [], k, m, _, x, hx => by simp [scanC] at hx
  | prev, (y, v, c) :: rest, k, m, h, x, hx => by
    have hc : c = Class.still := h (y, v, c) (by simp)
    subst hc
    have hr : ∀ r ∈ rest, r.2.2 = Class.still := fun r hr => h r (List.mem_cons_of_mem _ hr)
    have e : (Class.still == Class.moving) = false := by decide
    simp only [scanC, e, Bool.or_self] at hx
    split at hx
    · exact scanC_still prev rest _ _ hr x hx
    · split at hx
      · exact scanC_still y rest _ _ hr x hx
      · rcases List.mem_cons.1 hx with rfl | hx
        · simp [clsOf]
        · exact scanC_still y rest _ _ hr x hx

theorem countC_allStill (lo hi : Nat) (rows : List (Int × Int × Class)) (h : ∀ r ∈ rows, r.2.2 = Class.still) :
    countC .still lo hi rows = count lo hi (dropClass rows) ∧ countC .moving lo hi rows = 0 := by
  have hs : ∀ x ∈ runsC rows, x.cls = Class.still := by
    cases rows with
    | nil => simp [runsC]
    | cons r rest =>
      obtain ⟨y, v, c⟩ := r
      have hc : c = Class.still := h (y, v, c) (by simp)
      subst hc
      exact scanC_still y rest 0 true (fun r hr => h r (List.mem_cons_of_mem _ hr))
  have := countC_split lo hi rows
  have hm : countC .moving lo hi rows = 0 := by
    unfold countC
    rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
    intro x hx
    simp [hs x hx]
  omega

theorem exitFramesC_allStill (rows : List (Int × Int × Class)) (h : ∀ r ∈ rows, r.2.2 = Class.still) :
    exitFramesC .still rows = exitFrames (dropClass rows) ∧ exitFramesC .moving rows = 0 := by
  have hm : exitFramesC .moving rows = 0 := by
    unfold exitFramesC
    rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
    intro x hx
    simp [h x hx]
  have := exitFramesC_split rows
  omega


structure Pass where
  h : Int
  vh : List Int := []
  ys : List Int
  vs : List Int

def Pass.hasField (p : Pass) : Bool := !p.vh.isEmpty && p.vh.length == p.ys.length

def Pass.cs (p : Pass) : List Class := if p.hasField then classes p.vh else List.replicate p.ys.length .still

theorem Pass.cs_length (p : Pass) : p.cs.length = p.ys.length := by
  unfold Pass.cs
  split
  · rename_i h
    simp [Pass.hasField] at h
    simp [Fw.Device.Session.classes_length, h.2]
  · simp

def Pass.rowsWith (p : Pass) (cs : List Class) : List (Int × Int × Class) :=
  ((partSeries p.ys p.vs).zip cs).map fun (q, c) => (q.1, q.2, c)

def Pass.rows (p : Pass) : List (Int × Int × Class) := p.rowsWith p.cs

theorem Pass.rowsWith_drop (p : Pass) {cs : List Class} (hl : p.ys.length ≤ cs.length) :
    dropClass (p.rowsWith cs) = partSeries p.ys p.vs := by
  have hl' : (partSeries p.ys p.vs).length ≤ cs.length := by
    simp only [partSeries, List.length_zip, List.length_drop]
    exact Nat.le_trans (Nat.min_le_left _ _) hl
  have := List.map_fst_zip hl'
  simpa [Pass.rowsWith, dropClass, List.map_map, Function.comp_def] using this

theorem Pass.rows_drop (p : Pass) : dropClass p.rows = partSeries p.ys p.vs :=
  p.rowsWith_drop (by rw [Pass.cs_length]; exact Nat.le_refl _)

theorem Pass.rowsWith_still (p : Pass) {cs : List Class} (h : ∀ c ∈ cs, c = Class.still) :
    ∀ r ∈ p.rowsWith cs, r.2.2 = Class.still := by
  intro r hr
  simp only [Pass.rowsWith, List.mem_map] at hr
  obtain ⟨⟨q, c⟩, hq, rfl⟩ := hr
  exact h c (List.of_mem_zip hq).2

def armOf (c : Class) (ps : List Pass) : Arm :=
  ⟨(ps.map fun p => countC c bandLo bandHi p.rows).sum, (ps.map fun p => exitFramesC c p.rows).sum⟩

def armToday (ps : List Pass) : Arm :=
  ⟨(ps.map fun p => bandRuns (partSeries p.ys p.vs)).sum, (ps.map fun p => exitFrames (partSeries p.ys p.vs)).sum⟩

def verdictToday (base lift : List Pass) : Verdict :=
  verdict ((base ++ lift).map (·.h)) (armToday base) (armToday lift)

theorem armOf_split (ps : List Pass) :
    (armOf .moving ps).runs + (armOf .still ps).runs = (armToday ps).runs ∧
      (armOf .moving ps).frames + (armOf .still ps).frames = (armToday ps).frames := by
  have key : ∀ (f g h : Pass → Nat), (∀ p ∈ ps, f p + g p = h p) →
      (ps.map f).sum + (ps.map g).sum = (ps.map h).sum := by
    intro f g h hfg
    induction ps with
    | nil => simp
    | cons p t ih =>
      have := hfg p (by simp)
      have ih' := ih (fun p hp => hfg p (by simp [hp]))
      simp only [List.map_cons, List.sum_cons]
      omega
  constructor
  · exact key _ _ _ fun p _ => by rw [countC_split, Pass.rows_drop]; rfl
  · exact key _ _ _ fun p _ => by rw [exitFramesC_split, Pass.rows_drop]

theorem Pass.rows_noField {p : Pass} (h : p.hasField = false) : ∀ r ∈ p.rows, r.2.2 = Class.still :=
  p.rowsWith_still fun c hc => by simp [Pass.cs, h] at hc; exact hc.2

theorem Pass.rows_const {p : Pass} {h : Int} (hv : p.vh = List.replicate p.ys.length h) : ∀ r ∈ p.rows, r.2.2 = Class.still :=
  p.rowsWith_still fun c hc => by
    unfold Pass.cs at hc
    split at hc
    · rw [hv, Fw.Device.Session.classes_const] at hc
      exact (List.mem_replicate.1 hc).2
    · exact (List.mem_replicate.1 hc).2

theorem armOf_allStill {ps : List Pass} (h : ∀ p ∈ ps, ∀ r ∈ p.rows, r.2.2 = Class.still) :
    armOf .still ps = armToday ps ∧ armOf .moving ps = ⟨0, 0⟩ := by
  have key : ∀ (f g : Pass → Nat), (∀ p ∈ ps, f p = g p) → (ps.map f).sum = (ps.map g).sum := by
    intro f g hfg
    exact congrArg List.sum (List.map_congr_left hfg)
  have zero : ∀ (f : Pass → Nat), (∀ p ∈ ps, f p = 0) → (ps.map f).sum = 0 := by
    intro f hf
    have zsum : ∀ l : List Nat, (∀ x ∈ l, x = 0) → l.sum = 0 := by
      intro l
      induction l with
      | nil => simp
      | cons a t ih => intro hl; simp [hl a (by simp), ih (fun x hx => hl x (by simp [hx]))]
    exact zsum _ fun x hx => by
      obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hx
      exact hf p hp
  constructor
  · unfold armOf armToday
    congr 1
    · exact key _ _ fun p hp => by rw [(countC_allStill _ _ _ (h p hp)).1, Pass.rows_drop]; rfl
    · exact key _ _ fun p hp => by rw [(exitFramesC_allStill _ (h p hp)).1, Pass.rows_drop]
  · unfold armOf
    congr 1
    · exact zero _ fun p hp => (countC_allStill _ _ _ (h p hp)).2
    · exact zero _ fun p hp => (exitFramesC_allStill _ (h p hp)).2

theorem verdict_congr {hs hs' : List Int} (h : sameHeight hs = sameHeight hs') (base lift : Arm) :
    verdict hs base lift = verdict hs' base lift := by
  unfold verdict
  rw [h]

theorem sameHeight_iff (l : List Int) : sameHeight l = true ↔ ∀ a ∈ l, ∀ b ∈ l, a = b := by
  cases l with
  | nil => simp [sameHeight]
  | cons h t =>
    simp only [sameHeight, List.all_eq_true, beq_iff_eq, List.mem_cons]
    constructor
    · rintro ht a (rfl | ha) b (rfl | hb)
      · rfl
      · exact (ht b hb).symm
      · exact ht a ha
      · exact (ht a ha).trans (ht b hb).symm
    · intro hall x hx
      exact hall x (Or.inr hx) h (Or.inl rfl)


def verdictMoving (base lift : List Pass) : Verdict := verdict [] (armOf .moving base) (armOf .moving lift)

theorem verdictMoving_noData {base lift : List Pass}
    (h : ∀ p ∈ base ++ lift, ∀ r ∈ p.rows, r.2.2 = Class.still) : verdictMoving base lift = .noData := by
  have hb := (armOf_allStill (ps := base) (fun p hp => h p (by simp [hp]))).2
  have hl := (armOf_allStill (ps := lift) (fun p hp => h p (by simp [hp]))).2
  unfold verdictMoving
  rw [hb, hl]
  exact verdict_noData_frames (by rfl) (Or.inl rfl)


def Pass.stillHeights (p : Pass) : List Int :=
  if p.hasField then ((p.vh.zip p.cs).filter fun q => q.2 == Class.still).map (·.1) else [p.h]

def Pass.csAt (g : Int) (p : Pass) : List Class :=
  if p.hasField then (p.vh.zip p.cs).map fun q => if q.2 == Class.still && q.1 == g then Class.still else Class.moving
  else List.replicate p.ys.length (if p.h == g then Class.still else Class.moving)

theorem Pass.csAt_length (g : Int) (p : Pass) : (p.csAt g).length = p.ys.length := by
  unfold Pass.csAt
  split
  · rename_i h
    simp [Pass.hasField] at h
    simp [Pass.cs_length, h.2]
  · simp

def Pass.rowsAt (g : Int) (p : Pass) : List (Int × Int × Class) := p.rowsWith (p.csAt g)

def armAt (g : Int) (ps : List Pass) : Arm :=
  ⟨(ps.map fun p => countC .still bandLo bandHi (p.rowsAt g)).sum, (ps.map fun p => exitFramesC .still (p.rowsAt g)).sum⟩

theorem Pass.csAt_still_iff {g : Int} {p : Pass} (hf : p.hasField = true) (i : Nat) (hi : i < p.ys.length) :
    (p.csAt g)[i]'(by rw [Pass.csAt_length]; exact hi) = Class.still ↔
      p.cs[i]'(by rw [Pass.cs_length]; exact hi) = Class.still ∧ p.vh[i]'(by simp [Pass.hasField] at hf; omega) = g := by
  have hl : p.vh.length = p.ys.length := by simp [Pass.hasField] at hf; exact hf.2
  simp only [Pass.csAt, hf, ↓reduceIte, List.getElem_map, List.getElem_zip]
  by_cases h1 : p.cs[i]'(by rw [Pass.cs_length]; exact hi) = Class.still <;>
    by_cases h2 : p.vh[i]'(by omega) = g <;> simp [h1, h2]

theorem armAt_allStill {ps : List Pass} {g : Int} (h : ∀ p ∈ ps, ∀ r ∈ p.rowsAt g, r.2.2 = Class.still) :
    armAt g ps = armToday ps := by
  have key : ∀ (f k : Pass → Nat), (∀ p ∈ ps, f p = k p) → (ps.map f).sum = (ps.map k).sum := by
    intro f k hfg
    exact congrArg List.sum (List.map_congr_left hfg)
  have hd : ∀ p ∈ ps, dropClass (p.rowsAt g) = partSeries p.ys p.vs :=
    fun p _ => p.rowsWith_drop (by rw [Pass.csAt_length]; exact Nat.le_refl _)
  unfold armAt armToday
  congr 1
  · exact key _ _ fun p hp => by rw [(countC_allStill _ _ _ (h p hp)).1, hd p hp]; rfl
  · exact key _ _ fun p hp => by rw [(exitFramesC_allStill _ (h p hp)).1, hd p hp]

def present (g : Int) (ps : List Pass) : Bool := ps.any fun p => p.stillHeights.contains g

def groupHeights (base lift : List Pass) : List Int := ((base ++ lift).flatMap Pass.stillHeights).eraseDups

def verdictAt (g : Int) (base lift : List Pass) : Verdict := verdict [g] (armAt g base) (armAt g lift)

inductive Group where
  | judged (v : Verdict) | notComparable
  deriving DecidableEq, Repr

def Group.name : Group → String
  | .judged v => v.name | .notComparable => "not-comparable"

def groupOf (g : Int) (base lift : List Pass) : Group :=
  if present g base && present g lift then .judged (verdictAt g base lift) else .notComparable

def verdictByHeight (base lift : List Pass) : List (Int × Group) :=
  (groupHeights base lift).map fun g => (g, groupOf g base lift)

theorem groupOf_absent_base {g : Int} {base : List Pass} (h : present g base = false) (lift : List Pass) :
    groupOf g base lift = .notComparable := by
  simp [groupOf, h]

theorem groupOf_absent_lift {g : Int} {lift : List Pass} (h : present g lift = false) (base : List Pass) :
    groupOf g base lift = .notComparable := by
  simp [groupOf, h]

theorem groupOf_present {g : Int} {base lift : List Pass} (hb : present g base = true) (hl : present g lift = true) :
    groupOf g base lift = .judged (verdictAt g base lift) := by
  simp [groupOf, hb, hl]

theorem verdictAt_ne_confounded (g : Int) (base lift : List Pass) : verdictAt g base lift ≠ .confounded := by
  unfold verdictAt verdict
  have : sameHeight [g] = true := by simp [sameHeight]
  simp only [this, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  split <;> (try split) <;> simp

theorem verdictByHeight_ne_confounded (base lift : List Pass) :
    ∀ e ∈ verdictByHeight base lift, e.2 ≠ Group.judged .confounded := by
  intro e he hc
  obtain ⟨g, _, rfl⟩ := List.mem_map.1 he
  simp only [groupOf] at hc
  split at hc
  · exact verdictAt_ne_confounded g base lift (Group.judged.inj hc)
  · cases hc

theorem groupHeights_const {base lift : List Pass} {g : Int} (hb : base ≠ []) 
    (h : ∀ p ∈ base ++ lift, p.stillHeights ≠ [] ∧ ∀ x ∈ p.stillHeights, x = g) : groupHeights base lift = [g] := by
  unfold groupHeights
  obtain ⟨p, ps, rfl⟩ := List.exists_cons_of_ne_nil hb
  have hp := h p (by simp)
  obtain ⟨x, xs, hx⟩ := List.exists_cons_of_ne_nil hp.1
  have hall : ∀ y ∈ ((p :: ps) ++ lift).flatMap Pass.stillHeights, y = g := by
    intro y hy
    obtain ⟨q, hq, hyq⟩ := List.mem_flatMap.1 hy
    exact (h q hq).2 y hyq
  have hne : ((p :: ps) ++ lift).flatMap Pass.stillHeights = x :: (xs ++ (ps ++ lift).flatMap Pass.stillHeights) := by
    simp [List.flatMap_append, hx]
  rw [hne] at hall ⊢
  have hxg : x = g := hall x (by simp)
  rw [List.eraseDups_cons]
  have : (xs ++ (ps ++ lift).flatMap Pass.stillHeights).filter (fun b => !b == x) = [] := by
    rw [List.filter_eq_nil_iff]
    intro y hy
    have := hall y (List.mem_cons_of_mem _ hy)
    simp [this, hxg]
  rw [this, hxg]
  rfl

theorem verdictByHeight_const (base lift : List Pass) (g : Int) (hb : base ≠ []) (hl : lift ≠ [])
    (h : ∀ p ∈ base ++ lift, p.h = g ∧ (p.hasField = false ∨ p.vh = List.replicate p.ys.length g)) :
    verdictByHeight base lift = [(g, .judged (verdictToday base lift))] := by
  have hsh : ∀ p ∈ base ++ lift, p.stillHeights ≠ [] ∧ ∀ x ∈ p.stillHeights, x = g := by
    intro p hp
    obtain ⟨hpg, hf⟩ := h p hp
    by_cases hfield : p.hasField = true
    · have hv : p.vh = List.replicate p.ys.length g := by
        rcases hf with hf | hf
        · simp [hfield] at hf
        · exact hf
      have hc : p.cs = List.replicate p.ys.length Class.still := by
        simp [Pass.cs, hfield, hv, Fw.Device.Session.classes_const]
      have hn : p.ys.length ≠ 0 := by
        simp [Pass.hasField] at hfield
        intro e
        apply hfield.1
        rw [hv, e]
        rfl
      have hsh' : p.stillHeights = List.replicate p.ys.length g := by
        simp [Pass.stillHeights, hfield, hc, hv]
      rw [hsh']
      exact ⟨by simpa using hn, fun x hx => (List.mem_replicate.1 hx).2⟩
    · have hfield' : p.hasField = false := by simpa using hfield
      simp [Pass.stillHeights, hfield', hpg]
  have hgh : groupHeights base lift = [g] := groupHeights_const hb hsh
  have hpres : ∀ ps : List Pass, ps ≠ [] → (∀ p ∈ ps, p ∈ base ++ lift) → present g ps = true := by
    intro ps hne hsub
    obtain ⟨p, ps', rfl⟩ := List.exists_cons_of_ne_nil hne
    have hp := hsh p (hsub p (by simp))
    obtain ⟨x, xs, hx⟩ := List.exists_cons_of_ne_nil hp.1
    have : x = g := hp.2 x (by simp [hx])
    simp [present, hx, this]
  have hpb := hpres base hb (fun p hp => by simp [hp])
  have hpl := hpres lift hl (fun p hp => by simp [hp])
  have hrow : ∀ p ∈ base ++ lift, ∀ r ∈ p.rowsAt g, r.2.2 = Class.still := by
    intro p hp
    obtain ⟨hpg, hf⟩ := h p hp
    exact p.rowsWith_still fun c hc => by
      unfold Pass.csAt at hc
      split at hc
      · rename_i hfield
        have hv : p.vh = List.replicate p.ys.length g := by
          rcases hf with hf | hf
          · simp [hfield] at hf
          · exact hf
        have hcs : p.cs = List.replicate p.ys.length Class.still := by
          simp [Pass.cs, hfield, hv, Fw.Device.Session.classes_const]
        obtain ⟨⟨a, b⟩, hab, rfl⟩ := List.mem_map.1 hc
        have h1 := (List.of_mem_zip hab)
        rw [hcs] at h1
        rw [hv] at h1
        simp [(List.mem_replicate.1 h1.1).2, (List.mem_replicate.1 h1.2).2]
      · simp only [hpg, beq_self_eq_true, ↓reduceIte] at hc
        exact (List.mem_replicate.1 hc).2
  have hbr := armAt_allStill (ps := base) (g := g) (fun p hp => hrow p (by simp [hp]))
  have hlr := armAt_allStill (ps := lift) (g := g) (fun p hp => hrow p (by simp [hp]))
  have hv : verdictAt g base lift = verdictToday base lift := by
    unfold verdictAt verdictToday
    rw [hbr, hlr]
    apply verdict_congr
    rw [Bool.eq_iff_iff, sameHeight_iff, sameHeight_iff]
    constructor
    · intro _ a ha b hb
      obtain ⟨p, hpm, rfl⟩ := List.mem_map.1 ha
      obtain ⟨q, hqm, rfl⟩ := List.mem_map.1 hb
      rw [(h p hpm).1, (h q hqm).1]
    · intro _ a ha b hb
      simp at ha hb
      rw [ha, hb]
  unfold verdictByHeight
  rw [hgh]
  simp [groupOf_present hpb hpl, hv]

theorem verdictByHeight_noField (base lift : List Pass) (g : Int) (hb : base ≠ []) (hl : lift ≠ [])
    (h : ∀ p ∈ base ++ lift, p.h = g ∧ p.hasField = false) :
    verdictByHeight base lift = [(g, .judged (verdictToday base lift))] :=
  verdictByHeight_const base lift g hb hl fun p hp => ⟨(h p hp).1, Or.inl (h p hp).2⟩


private def pairsJ (l : List (Int × Int)) : Json := Json.arr (l.map fun p => toJson [p.1, p.2]).toArray

private def runJ (r : Run) : Json := Json.mkObj [("k", r.k), ("jump", r.jump), ("mid", r.mid)]

/-- Part series: short, throttled, with out-of-range values, trailing and moving. -/
private def rowCases : List (List (Int × Int)) :=
  [[], [(0, 500)], [(0, 500), (0, 500)], [(0, 500), (10, 500), (20, 500), (30, 500)],
   [(0, 500), (0, 500), (0, 500), (40, 500), (40, 500), (90, 500)],
   [(0, 500), (0, 0), (50, 500)], [(0, 500), (0, 1000), (50, 500)], [(0, 500), (0, 500), (50, 0)],
   [(0, 500), (0, 500), (0, 500)], [(100, 500), (100, 500), (0, 500), (0, 500), (100, 500)],
   (stairs [0, 100, 200, 300] 6 400), (stairs [0, 100, 200, 300] 7 400), (stairs [0, 100, 200] 8 400),
   (stairs [0, 100, 200] 5 400), (stairs [0, 100, 150, 400] 6 0), (stairs [0, 100, 150, 400] 3 999)]

private def lcg (s : Nat) : Nat := (s * 1103515245 + 12345) % 2147483648

/-- A pseudo-random series: positions step or stay, values wander across the range ends. -/
private def noisy (n : Nat) : List (Int × Int) :=
  ((List.range n).foldl (fun (acc : Nat × Int × List (Int × Int)) _ =>
    let s := lcg acc.1
    let y := if s % 7 < 3 then acc.2.1 else acc.2.1 + ((s / 7 % 9 : Nat) : Int) + 1
    (s, y, (y, ((s / 64 % 1100 : Nat) : Int)) :: acc.2.2)) (7, 0, [])).2.2.reverse

private def stairCases : List (Int × Nat × List Int) :=
  [(400, 4, [0, 100, 200, 300]), (400, 5, [0, 100, 200, 300, 400]), (400, 2, [5, 105, 50])]

private def verdictCases : List (List Int × Arm × Arm) :=
  [([8150, 8150], ⟨83, 430⟩, ⟨2, 410⟩), ([8150, 7750], ⟨83, 430⟩, ⟨2, 410⟩), ([7750], ⟨83, 430⟩, ⟨83, 400⟩),
   ([7750], ⟨83, 430⟩, ⟨17, 430⟩), ([7750], ⟨83, 430⟩, ⟨16, 430⟩), ([7750], ⟨9, 430⟩, ⟨0, 400⟩),
   ([7750], ⟨10, 430⟩, ⟨0, 400⟩), ([7750], ⟨83, 0⟩, ⟨0, 400⟩), ([7750], ⟨83, 430⟩, ⟨0, 0⟩), ([], ⟨83, 430⟩, ⟨0, 400⟩),
   ([7750, 7750, 7750], ⟨12, 100⟩, ⟨1, 50⟩)]

private def classStr (cs : List Class) : String := String.join (cs.map Class.code)

private def crowJ (r : Int × Int × Class) : Json := toJson [Json.num r.1, Json.num r.2.1, Json.str r.2.2.code]

private def crunJ (r : CRun) : Json := Json.mkObj [("k", r.run.k), ("jump", r.run.jump), ("mid", r.run.mid), ("cls", r.cls.code)]

private def classPattern (n : Nat) : Nat → List Class
  | 0 => List.replicate n .still
  | 1 => List.replicate n .moving
  | 2 => (List.range n).map fun i => if n / 3 ≤ i ∧ i < n / 3 + n / 4 then .moving else .still
  | _ => (List.range n).map fun i => if i % 50 < 20 then .moving else .still

private def crunCases : List (List (Int × Int × Class)) :=
  (rowCases.flatMap fun rows => (List.range 4).map fun k => (rows.zip (classPattern rows.length k)).map fun (r, c) => (r.1, r.2, c)) ++
  ((List.range 4).map fun k => ((noisy 400).zip (classPattern 400 k)).map fun (r, c) => (r.1, r.2, c))

private def mkPass (h : Int) (vh : List Int) (rows : List (Int × Int)) : Pass := ⟨h, vh, rows.map (·.1), 0 :: rows.map (·.2)⟩

private def passJ (p : Pass) : Json :=
  Json.mkObj [("h", p.h), ("vh", toJson p.vh), ("ys", toJson p.ys), ("vs", toJson p.vs)]

private def armJ (a : Arm) : Json := Json.mkObj [("runs", a.runs), ("frames", a.frames)]

private def pos20 : List Int := (List.range 20).map fun k => ((k * 100 : Nat) : Int)

private def baseRows : List (Int × Int) := stairs pos20 6 400
private def liftRows : List (Int × Int) := stairs pos20 2 400

private def constVh (h : Int) (rows : List (Int × Int)) : List Int := List.replicate rows.length h

private def startCollapsed (rows : List (Int × Int)) : List Int := 8150 :: List.replicate (rows.length - 1) 7750

private def pos60 : List Int := (List.range 60).map fun k => ((k * 100 : Nat) : Int)
private def baseLong : List (Int × Int) := stairs pos60 6 400
private def liftLong : List (Int × Int) := stairs pos60 2 400

private def collapseFor (k : Nat) (rows : List (Int × Int)) : List Int :=
  List.replicate (min k rows.length) 8150 ++ List.replicate (rows.length - min k rows.length) 7750

private def midSlide (rows : List (Int × Int)) : List Int :=
  List.replicate (rows.length / 2) 7750 ++ List.replicate (rows.length - rows.length / 2) 8150

private def busy (rows : List (Int × Int)) : List Int := (List.range rows.length).map fun i => if i / 20 % 2 == 0 then 7750 else 7800

private def cverdictCases (_ : Unit) : List (List Pass × List Pass) :=
  [([mkPass 8150 [] baseRows], [mkPass 8150 [] liftRows]),
   ([mkPass 8150 [] baseRows], [mkPass 7750 [] liftRows]),
   ([mkPass 7750 (constVh 7750 baseRows) baseRows, mkPass 7750 (constVh 7750 baseRows) baseRows], [mkPass 7750 (constVh 7750 liftRows) liftRows]),
   ([mkPass 7750 (constVh 7750 baseRows) baseRows], [mkPass 8150 (constVh 8150 liftRows) liftRows]),
   ([mkPass 8150 (startCollapsed baseRows) baseRows], [mkPass 7750 (constVh 7750 liftRows) liftRows]),
   ([mkPass 8150 (startCollapsed baseRows) baseRows, mkPass 7750 (constVh 7750 baseRows) baseRows],
    [mkPass 7750 (constVh 7750 liftRows) liftRows, mkPass 8150 (startCollapsed liftRows) liftRows]),
   ([mkPass 7750 (midSlide baseRows) baseRows], [mkPass 7750 (constVh 7750 liftRows) liftRows]),
   ([mkPass 7750 (busy baseRows) baseRows], [mkPass 7750 (busy liftRows) liftRows]),
   ([mkPass 7750 (busy baseRows) baseRows], [mkPass 7750 (constVh 7750 liftRows) liftRows]),
   ([], []),
   ([mkPass 7750 [] []], [mkPass 7750 [] []]),
   ([mkPass 7750 (constVh 7750 baseRows.tail) baseRows], [mkPass 7750 [] liftRows]),
   ([mkPass 8150 (collapseFor 31 baseLong) baseLong], [mkPass 7750 (constVh 7750 liftLong) liftLong]),
   ([mkPass 8150 (collapseFor 60 baseLong) baseLong], [mkPass 7750 (constVh 7750 liftLong) liftLong]),
   ([mkPass 8150 (collapseFor 60 baseLong) baseLong, mkPass 7750 (constVh 7750 baseLong) baseLong],
    [mkPass 7750 (constVh 7750 liftLong) liftLong, mkPass 7750 (constVh 7750 liftLong) liftLong]),
   ([mkPass 7750 (midSlide baseLong) baseLong], [mkPass 7750 (midSlide liftLong) liftLong]),
   ([mkPass 8150 (collapseFor 60 baseLong) baseLong], [mkPass 8150 (collapseFor 60 liftLong) liftLong]),
   ([mkPass 8150 (collapseFor 60 baseLong) baseLong], [mkPass 8150 (constVh 8150 liftLong) liftLong])]

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("bandLo", bandLo), ("bandHi", bandHi), ("minBase", minBase), ("dropDen", dropDen),
    ("throttleMs", (100 : Int))]).compress] ++
  ((rowCases ++ [noisy 120, noisy 400]).map fun rows =>
    (Json.mkObj [("kind", "runs"), ("rows", pairsJ rows), ("runs", Json.arr ((runs rows).map runJ).toArray),
      ("short", shortRuns rows), ("band", bandRuns rows), ("exitFrames", exitFrames rows),
      ("moving", allMove rows)]).compress) ++
  (stairCases.map fun (v, q, ys) =>
    let rows := stairs ys (q + 2) v
    (Json.mkObj [("kind", "stairs"), ("positions", toJson ys), ("period", toJson (q + 2)), ("value", v),
      ("moves", moves ys), ("rows", pairsJ rows), ("runs", Json.arr ((runs rows).map runJ).toArray),
      ("band", bandRuns rows)]).compress) ++
  ([1429, 1500, 1600, 1667, 1700, 2000, 3400].map fun (d : Nat) =>
    (Json.mkObj [("kind", "throttleK"), ("d", d), ("k", throttleK d)]).compress) ++
  (verdictCases.map fun (hs, b, l) =>
    (Json.mkObj [("kind", "verdict"), ("heights", toJson hs), ("sameHeight", sameHeight hs),
      ("base", Json.mkObj [("runs", b.runs), ("frames", b.frames)]),
      ("lift", Json.mkObj [("runs", l.runs), ("frames", l.frames)]),
      ("verdict", (verdict hs b l).name)]).compress) ++
  (crunCases.map fun rows =>
    let by_ (f : Class → Nat) : Json := Json.mkObj [("moving", f .moving), ("still", f .still)]
    (Json.mkObj [("kind", "cruns"), ("rows", Json.arr (rows.map crowJ).toArray), ("runs", Json.arr ((runsC rows).map crunJ).toArray),
      ("band", by_ fun c => countC c bandLo bandHi rows), ("exitFrames", by_ fun c => exitFramesC c rows),
      ("wholeBand", bandRuns (dropClass rows)), ("wholeExit", exitFrames (dropClass rows))]).compress) ++
  ((cverdictCases ()).map fun (b, l) =>
    let arms (ps : List Pass) : Json :=
      Json.mkObj [("moving", armJ (armOf .moving ps)), ("still", armJ (armOf .still ps)), ("today", armJ (armToday ps))]
    (Json.mkObj [("kind", "cverdict"), ("base", Json.arr (b.map passJ).toArray), ("lift", Json.arr (l.map passJ).toArray),
      ("classes", Json.mkObj [("base", toJson ((b.map fun p => classStr p.cs))), ("lift", toJson ((l.map fun p => classStr p.cs)))]),
      ("stillHeights", toJson ((b ++ l).flatMap Pass.stillHeights)),
      ("arms", Json.mkObj [("base", arms b), ("lift", arms l)]),
      ("groups", Json.arr ((verdictByHeight b l).map fun (g, r) =>
        Json.mkObj [("h", g), ("base", armJ (armAt g b)), ("lift", armJ (armAt g l)), ("result", r.name)]).toArray),
      ("moving", (verdictMoving b l).name), ("today", (verdictToday b l).name)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-stillruns golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-stillruns golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.StillRuns
