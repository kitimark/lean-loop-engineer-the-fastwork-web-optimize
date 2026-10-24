import Lean.Data.Json
import Fw.Measure.WebKitLag
/-!
# Felt-lag sessions on the real phone
Frame-interval counts per zone, felt-mark windows, the arm comparison rule and the replay strokes of `packages/measure-webkit/src/device-session.mjs`.
-/
namespace Fw.Device.Session
open Lean

/-! ## Thresholds and zones -/

/-- 34 ms in hundredths of a millisecond. -/
def slow : Int := 3400

/-- 50 ms in hundredths of a millisecond. -/
def bad : Int := 5000

theorem slow_lt_bad : slow < bad := by decide

/-- The window a scroll position (tenth px) falls in. -/
inductive Zone where
  | hero | finish | rest
  deriving DecidableEq, Repr

/-- The name written in the output. -/
def Zone.name : Zone → String
  | .hero => "hero" | .finish => "finish" | .rest => "rest"

/-- Hero to people is the first two viewports, the end of the page its last viewport, positions in tenth px. -/
def zoneOf (vh10 maxY10 y : Int) : Zone :=
  if y < 2 * vh10 then .hero
  else if maxY10 - y < vh10 then .finish
  else .rest

theorem zoneOf_hero {vh10 maxY10 y : Int} (h : y < 2 * vh10) : zoneOf vh10 maxY10 y = .hero := by
  simp [zoneOf, h]

theorem zoneOf_finish {vh10 maxY10 y : Int} (h1 : ¬ y < 2 * vh10) (h2 : maxY10 - y < vh10) :
    zoneOf vh10 maxY10 y = .finish := by
  simp [zoneOf, h1, h2]

theorem zoneOf_rest {vh10 maxY10 y : Int} (h1 : ¬ y < 2 * vh10) (h2 : ¬ maxY10 - y < vh10) :
    zoneOf vh10 maxY10 y = .rest := by
  simp [zoneOf, h1, h2]

/-- The first region of the lag probe lies in the hero window. -/
theorem regionA_in_hero {vh : Nat} (hv : 0 < vh) {maxY y : Int}
    (h : Fw.Measure.WebKitLag.regionOf vh maxY y = .a) : zoneOf (vh * 10) (maxY * 10) (y * 10) = .hero := by
  have := (Fw.Measure.WebKitLag.regionOf_a_iff_zone (vh := vh) (maxY := maxY) y).1 h
  have h0 : Fw.Measure.WebKitLag.zoneOf vh y = 0 := this
  have := (Fw.Measure.WebKitLag.zoneOf_eq_zero_iff hv y).1 h0
  apply zoneOf_hero
  omega

/-- The last region of the lag probe lies in the finish or hero window. -/
theorem regionB_in_finish_or_hero {vh : Nat} (hv : 0 < vh) {maxY y : Int}
    (h : Fw.Measure.WebKitLag.regionOf vh maxY y = .b) :
    zoneOf (vh * 10) (maxY * 10) (y * 10) = .finish ∨ zoneOf (vh * 10) (maxY * 10) (y * 10) = .hero := by
  unfold Fw.Measure.WebKitLag.regionOf at h
  by_cases h1 : Fw.Measure.WebKitLag.zoneOf vh y = 0
  · simp [h1] at h
  · by_cases h2 : Fw.Measure.WebKitLag.zoneOf vh (maxY - y) = 0
    · have := (Fw.Measure.WebKitLag.zoneOf_eq_zero_iff hv (maxY - y)).1 h2
      by_cases h3 : y * 10 < 2 * ((vh : Int) * 10)
      · exact Or.inr (zoneOf_hero (by push_cast; omega))
      · exact Or.inl (zoneOf_finish (by push_cast; omega) (by push_cast; omega))
    · by_cases h3 : 2 ≤ Fw.Measure.WebKitLag.zoneOf vh y ∧ 2 ≤ Fw.Measure.WebKitLag.zoneOf vh (maxY - y) <;>
        simp [h1, h2, h3] at h

/-! ## Frame intervals -/

/-- A frame in which the page scrolled: the interval to the frame before (hundredths of a ms) and the position (tenth px). -/
structure Row where
  dt : Int
  y : Int
  deriving Repr, DecidableEq

/-- The moving frames of a list of (time, position) frames. -/
def movingRows : List (Int × Int) → List Row
  | a :: b :: rest => (if b.2 ≠ a.2 then [⟨b.1 - a.1, b.2⟩] else []) ++ movingRows (b :: rest)
  | _ => []

theorem movingRows_length : ∀ l : List (Int × Int), (movingRows l).length ≤ l.length - 1
  | [] => by simp [movingRows]
  | [_] => by simp [movingRows]
  | a :: b :: rest => by
    have ih := movingRows_length (b :: rest)
    simp only [movingRows, List.length_append, List.length_cons] at ih ⊢
    split <;> simp <;> omega

/-- The frames of a list that exceed `th`. -/
def countOver (th : Int) (rs : List Row) : Nat := rs.countP fun r => decide (th < r.dt)

theorem countOver_bad_le_slow (rs : List Row) : countOver bad rs ≤ countOver slow rs := by
  apply List.countP_mono_left
  intro r _ h
  have := slow_lt_bad
  simp only [decide_eq_true_eq] at h ⊢
  omega

theorem countOver_le_length (th : Int) (rs : List Row) : countOver th rs ≤ rs.length :=
  List.countP_le_length

/-- The largest value of a list, 0 when it is empty. -/
def maxOf0 (l : List Int) : Int := l.foldr max 0

theorem le_maxOf0 : ∀ {l : List Int} {x : Int}, x ∈ l → x ≤ maxOf0 l
  | [], _, h => by simp at h
  | a :: l, x, h => by
    rcases List.mem_cons.1 h with rfl | h
    · exact Int.le_max_left _ _
    · exact Int.le_trans (le_maxOf0 h) (Int.le_max_right _ _)

/-- The longest interval. -/
def longest (rs : List Row) : Int := maxOf0 (rs.map (·.dt))

theorem le_longest {rs : List Row} {r : Row} (h : r ∈ rs) : r.dt ≤ longest rs :=
  le_maxOf0 (List.mem_map.2 ⟨r, h, rfl⟩)

/-- The interval at index `n / 2` of the sorted intervals, 0 when there are none. -/
def median (rs : List Row) : Int := ((rs.map (·.dt)).mergeSort fun a b => decide (a ≤ b)).getD (rs.length / 2) 0

theorem median_mem {rs : List Row} (h : rs ≠ []) : ∃ r ∈ rs, r.dt = median rs := by
  have hl : rs.length / 2 < ((rs.map (·.dt)).mergeSort fun a b => decide (a ≤ b)).length := by
    rw [List.length_mergeSort, List.length_map]
    have : 0 < rs.length := List.length_pos_iff.2 h
    omega
  have hm : median rs ∈ (rs.map (·.dt)).mergeSort fun a b => decide (a ≤ b) := by
    unfold median
    rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hl]
    exact List.getElem_mem _
  obtain ⟨r, hr, e⟩ := List.mem_map.1 ((List.mem_mergeSort).1 hm)
  exact ⟨r, hr, e⟩

theorem median_le_longest {rs : List Row} (h : rs ≠ []) : median rs ≤ longest rs := by
  obtain ⟨r, hr, e⟩ := median_mem h
  rw [← e]
  exact le_longest hr

/-- Hundredths of a count per 100 frames, rounded down; 0 for no frames. -/
def per100 (k n : Nat) : Nat := 10000 * k / n

theorem per100_le {k n : Nat} (h : k ≤ n) : per100 k n ≤ 10000 := by
  unfold per100
  rcases Nat.eq_zero_or_pos n with rfl | hn
  · simp
  · exact Nat.div_le_of_le_mul (by have := Nat.mul_le_mul_left 10000 h; omega)

/-- The counts of one set of moving frames. -/
structure Stat where
  n : Nat
  over34 : Nat
  over50 : Nat
  per34 : Nat
  per50 : Nat
  longest : Int
  median : Int
  deriving Repr, DecidableEq

/-- Counts over 34 and 50 ms, per 100 frames, longest and median interval. -/
def stat (rs : List Row) : Stat :=
  ⟨rs.length, countOver slow rs, countOver bad rs, per100 (countOver slow rs) rs.length,
    per100 (countOver bad rs) rs.length, longest rs, median rs⟩

theorem stat_over50_le_over34 (rs : List Row) : (stat rs).over50 ≤ (stat rs).over34 := countOver_bad_le_slow rs

theorem stat_over34_le_n (rs : List Row) : (stat rs).over34 ≤ (stat rs).n := countOver_le_length _ _

/-- The moving frames in zone `z`. -/
def inZone (vh10 maxY10 : Int) (z : Zone) (rs : List Row) : List Row :=
  rs.filter fun r => zoneOf vh10 maxY10 r.y == z

/-- The three zones hold every moving frame once. -/
theorem zone_counts_sum (vh10 maxY10 : Int) :
    ∀ rs : List Row, (inZone vh10 maxY10 .hero rs).length + (inZone vh10 maxY10 .finish rs).length +
      (inZone vh10 maxY10 .rest rs).length = rs.length
  | [] => by simp [inZone]
  | r :: rs => by
    have ih := zone_counts_sum vh10 maxY10 rs
    unfold inZone at ih ⊢
    cases h : zoneOf vh10 maxY10 r.y <;> simp [h] <;> omega

/-! ## The toolbar class of a frame -/

/-- Frames on each side of a height change in which a frame counts as toolbar-moving: 30 frames, half a second at 60 per second, longer than the toolbar's own slide. -/
def moveWin : Nat := 30

/-- The smallest change of the viewport height (tenth px) between two frames that counts as the toolbar moving: any change at the recorded resolution. -/
def moveMin : Nat := 1

/-- Whether the toolbar is moving or still at a frame. -/
inductive Class where
  | moving | still
  deriving DecidableEq, Repr

/-- The letter written in the golden. -/
def Class.code : Class → String
  | .moving => "m" | .still => "s"

/-- The viewport height changed by `moveMin` or more between frame `k - 1` and frame `k`. -/
def jumpAt (vh : List Int) (k : Nat) : Bool :=
  decide (k < vh.length) && decide (moveMin ≤ (vh.getD k 0 - vh.getD (k - 1) 0).natAbs)

/-- Whether a height change lies within `moveWin` frames of frame `i`: between frames `k - 1` and `k` for `i + 1 - moveWin ≤ k ≤ i + moveWin`. -/
def movingAt (vh : List Int) (i : Nat) : Bool :=
  (List.range' (i + 1 - moveWin) (i + moveWin + 1 - (i + 1 - moveWin))).any (jumpAt vh)

/-- The class of frame `i` of a list of viewport heights (tenth px). -/
def classAt (vh : List Int) (i : Nat) : Class := if movingAt vh i then .moving else .still

/-- The class of every frame. -/
def classes (vh : List Int) : List Class := (List.range vh.length).map (classAt vh)

theorem classes_length (vh : List Int) : (classes vh).length = vh.length := by simp [classes]

theorem movingAt_iff (vh : List Int) (i : Nat) :
    movingAt vh i = true ↔ ∃ k, i < k + moveWin ∧ k ≤ i + moveWin ∧ jumpAt vh k = true := by
  unfold movingAt
  rw [List.any_eq_true]
  constructor
  · rintro ⟨k, hk, hj⟩
    rw [List.mem_range'_1] at hk
    exact ⟨k, by omega, by omega, hj⟩
  · rintro ⟨k, h1, h2, hj⟩
    refine ⟨k, ?_, hj⟩
    rw [List.mem_range'_1]
    omega

/-- A frame is toolbar-moving exactly when a height change lies within the window. -/
theorem classAt_moving_iff (vh : List Int) (i : Nat) :
    classAt vh i = .moving ↔ ∃ k, i < k + moveWin ∧ k ≤ i + moveWin ∧ jumpAt vh k = true := by
  rw [← movingAt_iff]
  unfold classAt
  cases movingAt vh i <;> simp

/-- A frame is toolbar-still exactly when no height change lies within the window. -/
theorem classAt_still_iff (vh : List Int) (i : Nat) :
    classAt vh i = .still ↔ ∀ k, i < k + moveWin → k ≤ i + moveWin → jumpAt vh k = false := by
  unfold classAt
  by_cases h : movingAt vh i = true
  · simp only [h, ↓reduceIte]
    obtain ⟨k, h1, h2, hj⟩ := (movingAt_iff vh i).1 h
    constructor
    · intro hh; cases hh
    · intro hh; have := hh k h1 h2; simp [hj] at this
  · simp only [h]
    constructor
    · intro _ k h1 h2
      cases hk : jumpAt vh k
      · rfl
      · exact absurd ((movingAt_iff vh i).2 ⟨k, h1, h2, hk⟩) h
    · intro _; rfl

/-- Every change of the height makes the frames within the window moving. -/
theorem classAt_moving_of_jump {vh : List Int} {k i : Nat} (hj : jumpAt vh k = true) (h1 : i < k + moveWin)
    (h2 : k ≤ i + moveWin) : classAt vh i = .moving :=
  (classAt_moving_iff vh i).2 ⟨k, h1, h2, hj⟩

/-- A frame farther than the window from every change is still. -/
theorem classAt_still_of_far {vh : List Int} {i : Nat}
    (h : ∀ k, i < k + moveWin → k ≤ i + moveWin → jumpAt vh k = false) : classAt vh i = .still :=
  (classAt_still_iff vh i).2 h

/-- The two classes hold every frame once. -/
theorem classes_count (vh : List Int) :
    (classes vh).count .moving + (classes vh).count .still = vh.length := by
  have key : ∀ cs : List Class, cs.count .moving + cs.count .still = cs.length := by
    intro cs
    induction cs with
    | nil => simp
    | cons c t ih => cases c <;> simp <;> omega
  rw [key, classes_length]

/-- The indices of the moving frames and of the still frames together are the indices of all frames. -/
theorem index_partition (vh : List Int) :
    ((List.range vh.length).filter (movingAt vh) ++ (List.range vh.length).filter (fun i => !movingAt vh i)).Perm
      (List.range vh.length) := List.filter_append_perm _ _

/-- A height that never changes leaves every frame still. -/
theorem classes_const (h : Int) (n : Nat) : classes (List.replicate n h) = List.replicate n .still := by
  have hj : ∀ k, jumpAt (List.replicate n h) k = false := by
    intro k
    by_cases hk : k < n
    · have hk' : k - 1 < n := by omega
      simp [jumpAt, moveMin, List.getD_eq_getElem?_getD, hk, hk']
    · simp [jumpAt, hk]
  have hs : ∀ i, classAt (List.replicate n h) i = .still := fun i =>
    classAt_still_of_far (fun k _ _ => hj k)
  apply List.ext_getElem
  · simp [classes]
  · intro i h1 h2
    simp [classes, hs]

/-- The moving frames of (time, position, class) frames, each with the class of its later frame. -/
def movingRowsC : List (Int × Int × Class) → List (Class × Row)
  | a :: b :: rest => (if b.2.1 ≠ a.2.1 then [(b.2.2, ⟨b.1 - a.1, b.2.1⟩)] else []) ++ movingRowsC (b :: rest)
  | _ => []

/-- Dropping the classes gives the moving frames of today. -/
theorem movingRowsC_map : ∀ l : List (Int × Int × Class),
    (movingRowsC l).map (·.2) = movingRows (l.map fun f => (f.1, f.2.1))
  | [] => by simp [movingRowsC, movingRows]
  | [_] => by simp [movingRowsC, movingRows]
  | a :: b :: rest => by
    have ih := movingRowsC_map (b :: rest)
    simp only [movingRowsC, movingRows, List.map_cons, List.map_append] at ih ⊢
    rw [ih]
    split <;> simp

/-- When every frame is still, so is every interval. -/
theorem movingRowsC_still : ∀ l : List (Int × Int × Class), (∀ f ∈ l, f.2.2 = .still) →
    ∀ r ∈ movingRowsC l, r.1 = .still
  | [], _, r, hr => by simp [movingRowsC] at hr
  | [_], _, r, hr => by simp [movingRowsC] at hr
  | a :: b :: rest, h, r, hr => by
    have hb : b.2.2 = .still := h b (by simp)
    have ih := movingRowsC_still (b :: rest) (fun f hf => h f (List.mem_cons_of_mem a hf))
    simp only [movingRowsC, List.mem_append] at hr
    rcases hr with hr | hr
    · split at hr
      · simp at hr; subst hr; exact hb
      · simp at hr
    · exact ih r hr

/-- The intervals of one class, without the class. -/
def rowsOf (c : Class) (rs : List (Class × Row)) : List Row := (rs.filter fun r => r.1 == c).map (·.2)

/-- The two classes hold every interval once. -/
theorem rowsOf_split (rs : List (Class × Row)) : (rowsOf .moving rs).length + (rowsOf .still rs).length = rs.length := by
  induction rs with
  | nil => simp [rowsOf]
  | cons r t ih =>
    obtain ⟨c, w⟩ := r
    simp only [rowsOf, List.length_map] at ih ⊢
    cases c <;> simp <;> omega

/-- The two classes hold every interval of a zone once. -/
theorem inZone_rowsOf_split (vh10 maxY10 : Int) (z : Zone) (rs : List (Class × Row)) :
    (inZone vh10 maxY10 z (rowsOf .moving rs)).length + (inZone vh10 maxY10 z (rowsOf .still rs)).length =
      (inZone vh10 maxY10 z (rs.map (·.2))).length := by
  induction rs with
  | nil => simp [rowsOf, inZone]
  | cons r t ih =>
    obtain ⟨c, w⟩ := r
    unfold rowsOf inZone at ih ⊢
    cases c <;> by_cases hz : zoneOf vh10 maxY10 w.y == z <;> simp [hz] <;> omega

/-- With every interval still, the still class is all of them and the moving class none. -/
theorem rowsOf_still (rs : List (Class × Row)) (h : ∀ r ∈ rs, r.1 = .still) :
    rowsOf .still rs = rs.map (·.2) ∧ rowsOf .moving rs = [] := by
  induction rs with
  | nil => simp [rowsOf]
  | cons r t ih =>
    obtain ⟨c, w⟩ := r
    have hc : c = .still := h (c, w) (by simp)
    subst hc
    have := ih (fun x hx => h x (by simp [hx]))
    unfold rowsOf at this ⊢
    simp [this.1, this.2]

/-! ## The arm comparison rule -/

/-- Largest minus smallest of the per-pass values, 0 when there are none. -/
def spread (l : List Int) : Int :=
  match l.max?, l.min? with
  | some h, some m => h - m
  | _, _ => 0

/-- How an arm compares with the original; lower values are better. -/
inductive Verdict where
  | beats | worse | same | unresolved
  deriving DecidableEq, Repr

/-- The name written in the output. -/
def Verdict.name : Verdict → String
  | .beats => "beats" | .worse => "worse" | .same => "same" | .unresolved => "unresolved"

/-- An arm beats (or loses to) the original only when its extreme pass is clear of the original's by more than the original's pass-to-pass spread. -/
def verdict (orig arm : List Int) : Verdict :=
  if orig.length < 2 then .unresolved else
  match orig.min?, orig.max?, arm.min?, arm.max? with
  | some oLo, some oHi, some aLo, some aHi =>
    if aHi + spread orig < oLo then .beats
    else if oHi + spread orig < aLo then .worse
    else .same
  | _, _, _, _ => .unresolved

theorem verdict_unresolved_single {orig : List Int} (arm : List Int) (h : orig.length < 2) :
    verdict orig arm = .unresolved := by
  simp [verdict, h]

theorem verdict_unresolved_no_arm (orig : List Int) : verdict orig [] = .unresolved := by
  unfold verdict
  split <;> simp

theorem verdict_beats_beyond {orig arm : List Int} (h : verdict orig arm = .beats) :
    ∀ o ∈ orig, ∀ a ∈ arm, a + spread orig < o := by
  intro o ho a ha
  unfold verdict at h
  split at h
  · simp at h
  · split at h
    · rename_i oLo oHi aLo aHi e1 e2 e3 e4
      split at h
      · rename_i hb
        have h1 := ((List.min?_eq_some_iff).1 e1).2 o ho
        have h2 := ((List.max?_eq_some_iff).1 e4).2 a ha
        omega
      · split at h <;> simp at h
    · simp at h

theorem verdict_worse_beyond {orig arm : List Int} (h : verdict orig arm = .worse) :
    ∀ o ∈ orig, ∀ a ∈ arm, o + spread orig < a := by
  intro o ho a ha
  unfold verdict at h
  split at h
  · simp at h
  · split at h
    · rename_i oLo oHi aLo aHi e1 e2 e3 e4
      split at h
      · simp at h
      · split at h
        · rename_i hb
          have h1 := ((List.max?_eq_some_iff).1 e2).2 o ho
          have h2 := ((List.min?_eq_some_iff).1 e3).2 a ha
          omega
        · simp at h
    · simp at h

theorem verdict_beats_of {orig arm : List Int} {oLo oHi aLo aHi : Int} (hl : 2 ≤ orig.length)
    (e1 : orig.min? = some oLo) (e2 : orig.max? = some oHi) (e3 : arm.min? = some aLo) (e4 : arm.max? = some aHi)
    (h : aHi + spread orig < oLo) : verdict orig arm = .beats := by
  simp [verdict, show ¬ orig.length < 2 by omega, e1, e2, e3, e4, h]

theorem verdict_worse_of {orig arm : List Int} {oLo oHi aLo aHi : Int} (hl : 2 ≤ orig.length)
    (e1 : orig.min? = some oLo) (e2 : orig.max? = some oHi) (e3 : arm.min? = some aLo) (e4 : arm.max? = some aHi)
    (h1 : ¬ aHi + spread orig < oLo) (h2 : oHi + spread orig < aLo) : verdict orig arm = .worse := by
  simp [verdict, show ¬ orig.length < 2 by omega, e1, e2, e3, e4, h1, h2]

theorem verdict_same_of {orig arm : List Int} {oLo oHi aLo aHi : Int} (hl : 2 ≤ orig.length)
    (e1 : orig.min? = some oLo) (e2 : orig.max? = some oHi) (e3 : arm.min? = some aLo) (e4 : arm.max? = some aHi)
    (h1 : ¬ aHi + spread orig < oLo) (h2 : ¬ oHi + spread orig < aLo) : verdict orig arm = .same := by
  simp [verdict, show ¬ orig.length < 2 by omega, e1, e2, e3, e4, h1, h2]

/-- An arm pass within the original's spread of an original pass is never a win. -/
theorem not_beats_within {orig arm : List Int} {o a : Int} (ho : o ∈ orig) (ha : a ∈ arm)
    (h : o ≤ a + spread orig) : verdict orig arm ≠ .beats := by
  intro hb
  have := verdict_beats_beyond hb o ho a ha
  omega

/-! ## Animated values of a part -/

/-- A frame pair in which the page moved but the value (per mille) stayed, mid-transition. -/
def stallAt (a b : Int × Int) : Bool :=
  a.1 != b.1 && a.2 == b.2 && decide (0 < a.2) && decide (a.2 < 1000)

/-- Frame pairs in which the page moved but the value stayed mid-transition. -/
def stalls : List (Int × Int) → Nat
  | a :: b :: rest => (if stallAt a b then 1 else 0) + stalls (b :: rest)
  | _ => 0

/-- Absolute value steps between consecutive frames. -/
def stepAbs : List (Int × Int) → List Int
  | a :: b :: rest => (if a.2 ≤ b.2 then b.2 - a.2 else a.2 - b.2) :: stepAbs (b :: rest)
  | _ => []

/-- The largest step of the value. -/
def maxStep (l : List (Int × Int)) : Int := maxOf0 (stepAbs l)

theorem stalls_le : ∀ l : List (Int × Int), stalls l ≤ l.length - 1
  | [] => by simp [stalls]
  | [_] => by simp [stalls]
  | a :: b :: rest => by
    have ih := stalls_le (b :: rest)
    simp only [stalls, List.length_cons] at ih ⊢
    split <;> omega

theorem stallAt_moved {a b : Int × Int} (h : stallAt a b = true) : a.1 ≠ b.1 := by
  simp [stallAt] at h
  exact h.1.1.1

theorem stallAt_mid {a b : Int × Int} (h : stallAt a b = true) : 0 < a.2 ∧ a.2 < 1000 := by
  simp [stallAt] at h
  exact ⟨h.1.2, h.2⟩

theorem stallAt_held {a b : Int × Int} (h : stallAt a b = true) : a.2 = b.2 := by
  simp [stallAt] at h
  exact h.1.1.2

theorem le_maxStep {l : List (Int × Int)} {a b : Int × Int} (h : [a, b] <+: l) :
    (if a.2 ≤ b.2 then b.2 - a.2 else a.2 - b.2) ≤ maxStep l := by
  obtain ⟨t, rfl⟩ := h
  apply le_maxOf0
  simp [stepAbs]

/-- A value that never changes has no step. -/
theorem maxStep_const (v : Int) : ∀ l : List Int, maxStep (l.map fun y => (y, v)) = 0
  | [] => by simp [maxStep, stepAbs, maxOf0]
  | [_] => by simp [maxStep, stepAbs, maxOf0]
  | a :: b :: rest => by
    have ih := maxStep_const v (b :: rest)
    simp only [List.map_cons] at ih ⊢
    simp [maxStep, stepAbs, maxOf0] at ih ⊢
    omega

/-- The part series of a pass: each value paired with the scroll position it was computed from.
The recorder's `requestAnimationFrame` callback runs before the page's in a frame, so the value it reads in frame `i + 1` is the one
the page wrote in frame `i` from the position `ys[i]`. Pairing `ys[i]` with `vs[i + 1]` therefore compares what the page did with
the value it made. -/
def partSeries (ys vs : List Int) : List (Int × Int) := ys.zip (vs.drop 1)

/-- A value that is a function `f` of the position one frame earlier gives pairs (position, f position): each value is paired with its source. -/
theorem partSeries_lag (f : Int → Int) (x : Int) (ys : List Int) :
    partSeries ys (x :: ys.map f) = ys.map fun y => (y, f y) := by
  induction ys with
  | nil => simp [partSeries]
  | cons y rest ih => simp [partSeries] at ih ⊢; exact ih

/-- A pair of the lagged series is a stall exactly when the page moved, the function gave the same value for both positions, and that value is mid-transition. -/
theorem stallAt_fn (f : Int → Int) (y y' : Int) :
    stallAt (y, f y) (y', f y') = true ↔ y ≠ y' ∧ f y = f y' ∧ 0 < f y ∧ f y < 1000 := by
  simp [stallAt, and_assoc]

/-- Pairing a value with the position of its own frame (the old rule) counts a stall where nothing stalled: the page stood at 100 for
two frames, then moved to 200 and 300, and the value is 500, 500, 600 from those positions (read one frame late). -/
theorem partSeries_no_false_stall :
    stalls (partSeries [100, 100, 200, 300] [0, 500, 500, 600]) = 0 ∧ stalls ([100, 100, 200, 300].zip [0, 500, 500, 600]) = 1 := by
  decide

/-! ## Touches, taps and felt marks -/

/-- A touch event: start, move, stop or cancel. -/
inductive Phase where
  | start | move | stop | cancel
  deriving DecidableEq, Repr

/-- The letter written in the record. -/
def Phase.code : Phase → String
  | .start => "s" | .move => "m" | .stop => "e" | .cancel => "c"

/-- One touch event: time (hundredths of a ms), position (tenth px), fingers down after it. -/
structure Touch where
  t : Int
  ph : Phase
  x : Int
  y : Int
  n : Nat
  deriving Repr, DecidableEq

/-- Strokes: start to stop; a cancel or a start inside a stroke drops the open one, events outside a stroke are ignored. -/
def strokesAux : Option (List Touch) → List Touch → List (List Touch)
  | _, [] => []
  | none, e :: es => if e.ph = .start then strokesAux (some [e]) es else strokesAux none es
  | some cur, e :: es =>
    match e.ph with
    | .start => strokesAux (some [e]) es
    | .move => strokesAux (some (cur ++ [e])) es
    | .stop => (cur ++ [e]) :: strokesAux none es
    | .cancel => strokesAux none es

/-- The strokes of a touch stream. -/
def strokes (ts : List Touch) : List (List Touch) := strokesAux none ts

/-- A stroke is a tap when it lasts at most 300 ms and no event is more than 10 px from its start. -/
def isTap (s : List Touch) : Bool :=
  match s.head?, s.getLast? with
  | some a, some z =>
    decide (z.t - a.t ≤ 30000) && s.all fun e => decide ((e.x - a.x).natAbs ≤ 100 ∧ (e.y - a.y).natAbs ≤ 100)
  | _, _ => false

theorem isTap_long {s : List Touch} {a z : Touch} (ha : s.head? = some a) (hz : s.getLast? = some z)
    (h : 30000 < z.t - a.t) : isTap s = false := by
  simp [isTap, ha, hz]
  omega

theorem isTap_travel {s : List Touch} {a e : Touch} (ha : s.head? = some a) (he : e ∈ s)
    (h : 100 < (e.x - a.x).natAbs ∨ 100 < (e.y - a.y).natAbs) : isTap s = false := by
  unfold isTap
  rw [ha]
  cases hz : s.getLast? with
  | none => simp
  | some z =>
    simp only [Bool.and_eq_false_iff]
    right
    rw [Bool.eq_false_iff, Ne, List.all_eq_true]
    intro hall
    have := hall e he
    simp at this
    omega

theorem isTap_nil : isTap [] = false := by simp [isTap]

/-- A tap: when it ended and where it began (tenth px). -/
structure Tap where
  t : Int
  x : Int
  y : Int
  deriving Repr, DecidableEq

/-- The tap of a stroke, if it is one. -/
def tapOf (s : List Touch) : Option Tap :=
  match s.head?, s.getLast? with
  | some a, some z => if isTap s then some ⟨z.t, a.x, a.y⟩ else none
  | _, _ => none

/-- The taps of a touch stream. -/
def taps (ts : List Touch) : List Tap := (strokes ts).filterMap tapOf

/-- Two taps within 40 px of each other on both axes. -/
def near (a b : Tap) : Bool := decide ((a.x - b.x).natAbs ≤ 400 ∧ (a.y - b.y).natAbs ≤ 400)

/-- Three taps are a felt mark when each follows the one before within 500 ms and lies near it. -/
def triple (a b c : Tap) : Bool :=
  decide (b.t - a.t ≤ 50000 ∧ c.t - b.t ≤ 50000) && near a b && near b c

theorem triple_slow_first {a b c : Tap} (h : 50000 < b.t - a.t) : triple a b c = false := by
  simp [triple]
  omega

theorem triple_slow_second {a b c : Tap} (h : 50000 < c.t - b.t) : triple a b c = false := by
  simp [triple]
  omega

theorem triple_far_first {a b c : Tap} (h : near a b = false) : triple a b c = false := by
  simp [triple, h]

theorem triple_far_second {a b c : Tap} (h : near b c = false) : triple a b c = false := by
  simp [triple, h]

/-- The third tap of every felt mark, scanning from the left; a mark uses its three taps once. -/
def marksOf : List Tap → List Tap
  | a :: b :: c :: rest => if triple a b c then c :: marksOf rest else marksOf (b :: c :: rest)
  | _ => []
termination_by l => l.length

theorem marksOf_length : ∀ l : List Tap, 3 * (marksOf l).length ≤ l.length
  | [] => by simp [marksOf]
  | [_] => by simp [marksOf]
  | [_, _] => by simp [marksOf]
  | a :: b :: c :: rest => by
    have h1 := marksOf_length rest
    have h2 := marksOf_length (b :: c :: rest)
    rw [marksOf]
    split
    · simp only [List.length_cons] at h1 ⊢
      omega
    · simp only [List.length_cons] at h2 ⊢
      omega
termination_by l => l.length

theorem marksOf_mem : ∀ {l : List Tap} {m : Tap}, m ∈ marksOf l → m ∈ l
  | [], _, h => by simp [marksOf] at h
  | [_], _, h => by simp [marksOf] at h
  | [_, _], _, h => by simp [marksOf] at h
  | a :: b :: c :: rest, m, h => by
    rw [marksOf] at h
    split at h
    · rcases List.mem_cons.1 h with rfl | h
      · simp
      · exact List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (marksOf_mem h)))
    · exact List.mem_cons_of_mem _ (marksOf_mem h)
termination_by l => l.length

/-- Two taps are never a mark. -/
theorem marksOf_pair (a b : Tap) : marksOf [a, b] = [] := by simp [marksOf]

/-- The scroll position at time `t`: the last frame at or before it, else the first frame, else 0. -/
def yAt (fs : List (Int × Int)) (t : Int) : Int :=
  match (fs.filter fun f => decide (f.1 ≤ t)).getLast? with
  | some f => f.2
  | none => match fs with
    | f :: _ => f.2
    | [] => 0

theorem yAt_nil (t : Int) : yAt [] t = 0 := by simp [yAt]

/-- The lookback of a felt mark: 1.5 s in hundredths of a ms. -/
def lookback : Int := 150000

/-- The frames from `lookback` before time `t` up to `t`. -/
def windowFrames (fs : List (Int × Int)) (t : Int) : List (Int × Int) :=
  fs.filter fun f => decide (t - lookback ≤ f.1 ∧ f.1 ≤ t)

theorem mem_windowFrames {fs : List (Int × Int)} {t : Int} {f : Int × Int} :
    f ∈ windowFrames fs t ↔ f ∈ fs ∧ t - lookback ≤ f.1 ∧ f.1 ≤ t := by
  simp [windowFrames]

/-- A felt mark: when, where, in which zone, and the frame intervals of its lookback window. -/
structure Felt where
  t : Int
  y : Int
  zone : Zone
  stat : Stat
  deriving Repr, DecidableEq

/-- The felt mark of a triple tap. -/
def feltOf (vh10 maxY10 : Int) (fs : List (Int × Int)) (m : Tap) : Felt :=
  let y := yAt fs m.t
  ⟨m.t, y, zoneOf vh10 maxY10 y, stat (movingRows (windowFrames fs m.t))⟩

theorem felt_n_le (vh10 maxY10 : Int) (fs : List (Int × Int)) (m : Tap) :
    (feltOf vh10 maxY10 fs m).stat.n ≤ (windowFrames fs m.t).length - 1 :=
  movingRows_length _

theorem windowFrames_length_le (fs : List (Int × Int)) (t : Int) : (windowFrames fs t).length ≤ fs.length :=
  List.length_filter_le _ _

/-! ## The replay strokes -/

/-- The frame of time `t` on the 60 Hz grid that starts at `t0` (hundredths of a ms). -/
def frameOf (t0 t : Int) : Nat := ((t - t0) * 60 / 100000).toNat

/-- A replayed stroke: the frame of its touch start and the finger position (tenth px) in each frame from there. -/
structure Stroke where
  f0 : Nat
  path : List (Int × Int)
  deriving Repr, DecidableEq

/-- The finger position at frame `j`: the last event at or before it, else the first. -/
def posAt (s : List Touch) (t0 : Int) (j : Nat) : Int × Int :=
  match (s.filter fun e => decide (frameOf t0 e.t ≤ j)).getLast? with
  | some e => (e.x, e.y)
  | none => match s with
    | e :: _ => (e.x, e.y)
    | [] => (0, 0)

/-- A point clamped into the viewport box. -/
def clampPt (w10 h10 : Int) (p : Int × Int) : Int × Int := (max 0 (min w10 p.1), max 0 (min h10 p.2))

/-- Whether a point lies in the viewport box. -/
def inBox (w10 h10 : Int) (p : Int × Int) : Bool :=
  decide (0 ≤ p.1 ∧ p.1 ≤ w10 ∧ 0 ≤ p.2 ∧ p.2 ≤ h10)

theorem clampPt_inBox {w10 h10 : Int} (hw : 0 ≤ w10) (hh : 0 ≤ h10) (p : Int × Int) :
    inBox w10 h10 (clampPt w10 h10 p) = true := by
  unfold inBox
  exact decide_eq_true (by simp only [clampPt]; refine ⟨?_, ?_, ?_, ?_⟩ <;> omega)

/-- A stroke on the frame grid, not before frame `floor`, at least two frames long, clamped into the viewport. -/
def strokeOf (t0 : Int) (floor : Nat) (w10 h10 : Int) (s : List Touch) : Option Stroke :=
  match s.head?, s.getLast? with
  | some a, some z =>
    let ks := max (frameOf t0 a.t) floor
    let ke := max (frameOf t0 z.t) (ks + 1)
    some ⟨ks, (List.range (ke - ks + 1)).map fun i => clampPt w10 h10 (posAt s t0 (ks + i))⟩
  | _, _ => none

/-- The strokes in order, each starting after the one before has ended. -/
def strokesGo (t0 : Int) (w10 h10 : Int) : Nat → List (List Touch) → List Stroke
  | _, [] => []
  | floor, s :: ss =>
    match strokeOf t0 floor w10 h10 s with
    | some st => st :: strokesGo t0 w10 h10 (st.f0 + st.path.length) ss
    | none => strokesGo t0 w10 h10 floor ss

/-- A stroke the loader accepts: two points or more, all inside the viewport. -/
def strokeOk (w10 h10 : Int) (st : Stroke) : Bool :=
  decide (2 ≤ st.path.length) && st.path.all (inBox w10 h10)

/-- Strokes in order and disjoint: each starts at or after `floor`, and the next floor is after its last frame. -/
def ordered : Nat → List Stroke → Bool
  | _, [] => true
  | floor, st :: r => decide (floor ≤ st.f0) && ordered (st.f0 + st.path.length) r

/-- The last frame after the strokes, 0 for none. -/
def endFrame : List Stroke → Nat
  | [] => 0
  | [st] => st.f0 + st.path.length
  | _ :: r => endFrame r

/-- The loader refuses a replay longer than 200 s at 60 Hz, whatever its file says. -/
def replayCap : Nat := 12000

/-- What the CI profile loader accepts of a replay: every stroke ok, in order, ending within `cap` frames. -/
def replayOk (w10 h10 : Int) (cap : Nat) (ss : List Stroke) : Bool :=
  !ss.isEmpty && ss.all (strokeOk w10 h10) && ordered 0 ss && decide (endFrame ss ≤ cap)

theorem strokeOf_spec {t0 : Int} {floor : Nat} {w10 h10 : Int} (hw : 0 ≤ w10) (hh : 0 ≤ h10) {s : List Touch} {st : Stroke}
    (h : strokeOf t0 floor w10 h10 s = some st) : floor ≤ st.f0 ∧ strokeOk w10 h10 st = true := by
  unfold strokeOf at h
  split at h
  · simp only [Option.some.injEq] at h
    subst h
    refine ⟨Nat.le_max_right _ _, ?_⟩
    simp only [strokeOk, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true, List.mem_map, List.length_map,
      List.length_range]
    refine ⟨by omega, ?_⟩
    rintro p ⟨i, _, rfl⟩
    exact clampPt_inBox hw hh _
  · simp at h

theorem strokesGo_ok (t0 : Int) {w10 h10 : Int} (hw : 0 ≤ w10) (hh : 0 ≤ h10) :
    ∀ (ss : List (List Touch)) (floor : Nat),
      ordered floor (strokesGo t0 w10 h10 floor ss) = true ∧ (strokesGo t0 w10 h10 floor ss).all (strokeOk w10 h10) = true
  | [], floor => by simp [strokesGo, ordered]
  | s :: ss, floor => by
    unfold strokesGo
    split
    · rename_i st hst
      obtain ⟨h1, h2⟩ := strokeOf_spec hw hh hst
      obtain ⟨ih1, ih2⟩ := strokesGo_ok t0 hw hh ss (st.f0 + st.path.length)
      simp [ordered, h1, h2, ih1, ih2]
    · exact strokesGo_ok t0 hw hh ss floor

/-- The strokes of a stream that are not taps. -/
def replayStrokes (ts : List Touch) : List (List Touch) := (strokes ts).filter fun s => !isTap s

theorem replayStrokes_not_tap {ts : List Touch} {s : List Touch} (h : s ∈ replayStrokes ts) : isTap s = false := by
  simp [replayStrokes] at h
  exact h.2

/-- The first replayed stroke's first event time, 0 for none. -/
def t0Of (ss : List (List Touch)) : Int :=
  match ss with
  | (a :: _) :: _ => a.t
  | _ => 0

/-- Whether no event had more than one finger down. -/
def singleFinger (ts : List Touch) : Bool := ts.all fun e => decide (e.n ≤ 1)

/-- The replay of a stream in a viewport of `w` by `h` px, none when a second finger was ever down. -/
def replay (ts : List Touch) (w h : Nat) : Option (List Stroke) :=
  if singleFinger ts then
    some (strokesGo (t0Of (replayStrokes ts)) ((w : Int) * 10) ((h : Int) * 10) 0 (replayStrokes ts))
  else none

theorem replay_multi_refused {ts : List Touch} (w h : Nat) (hm : singleFinger ts = false) : replay ts w h = none := by
  simp [replay, hm]

theorem replay_ok_of_single {ts : List Touch} (w h : Nat) (hs : singleFinger ts = true) :
    ∃ ss, replay ts w h = some ss ∧ ordered 0 ss = true ∧ ss.all (strokeOk ((w : Int) * 10) ((h : Int) * 10)) = true := by
  have := strokesGo_ok (t0Of (replayStrokes ts)) (w10 := (w : Int) * 10) (h10 := (h : Int) * 10) (by omega) (by omega)
    (replayStrokes ts) 0
  exact ⟨_, by simp [replay, hs], this⟩

/-! ## The session plan -/

/-- The page a pass is recorded on. -/
inductive Arm where
  | original | rewrite | v2 | look
  deriving DecidableEq, Repr

/-- The name written in the record. -/
def Arm.code : Arm → String
  | .original => "original" | .rewrite => "rewrite" | .v2 => "v2" | .look => "look"

/-- What the banner calls the arm. -/
def Arm.label : Arm → String
  | .original => "the ORIGINAL page"
  | .rewrite => "the faithful REWRITE"
  | .v2 => "the REWRITE with the v2-proved flags"
  | .look => "the REWRITE with the look-change flags"

/-- The original, the given rewrite arms in order, the original again (A/B/A: the first and last pass are the same page). -/
def planOf (mid : List Arm) : List Arm := .original :: (mid ++ [.original])

/-- The longest plan: original, rewrite, rewrite with v2-proved, look-change, original again. -/
def plan : List Arm := planOf [.rewrite, .v2, .look]

/-- Seconds of swiping per pass. -/
def recSeconds : Nat := 90

theorem plan_first : plan.head? = some .original := by decide

theorem plan_last : plan.getLast? = some .original := by decide

theorem plan_original_twice : plan.count .original = 2 := by decide

theorem plan_covers (a : Arm) : a ∈ plan := by cases a <;> decide

theorem plan_no_repeat : (plan.zip plan.tail).all (fun p => p.1 != p.2) = true := by decide

theorem plan_fits_block : plan.length * recSeconds ≤ 900 := by decide

/-! ## Arms that load the same page are one arm

A rewrite arm is named by the flags it resolves to (`part:variant` entries, in any order, defaults removed). When the preset of the
v2 arm resolves to no flags it is the faithful rewrite again; a pass of it would be a duplicate, so the plan drops it. -/

/-- Two flag sets are the same page: each entry of one is in the other. -/
def sameFlags (a b : List String) : Bool := a.all (fun x => decide (x ∈ b)) && b.all (fun x => decide (x ∈ a))

theorem sameFlags_comm (a b : List String) : sameFlags a b = sameFlags b a := by
  simp only [sameFlags]
  exact Bool.and_comm _ _

theorem sameFlags_refl (a : List String) : sameFlags a a = true := by
  simp [sameFlags]

/-- Keep an arm unless an arm kept before it (or in `seen`) loads the same page. -/
def dedupAux : List (List String) → List (Arm × List String) → List (Arm × List String)
  | _, [] => []
  | seen, x :: rest =>
    if seen.any (sameFlags x.2) then dedupAux seen rest else x :: dedupAux (x.2 :: seen) rest

/-- The arms of a list of (arm, resolved flags) that stay, in order. -/
def dedupArms (xs : List (Arm × List String)) : List Arm := (dedupAux [] xs).map (·.1)

theorem dedupAux_sub : ∀ (seen : List (List String)) (xs : List (Arm × List String)) {x}, x ∈ dedupAux seen xs → x ∈ xs
  | _, [], _, h => by simp [dedupAux] at h
  | seen, y :: rest, x, h => by
    unfold dedupAux at h
    split at h
    · exact List.mem_cons_of_mem _ (dedupAux_sub seen rest h)
    · rcases List.mem_cons.mp h with rfl | h
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ (dedupAux_sub _ rest h)

/-- A kept arm loads a page none of the earlier ones loads. -/
theorem dedupAux_fresh : ∀ (seen : List (List String)) (xs : List (Arm × List String)) {x},
    x ∈ dedupAux seen xs → seen.any (sameFlags x.2) = false
  | _, [], _, h => by simp [dedupAux] at h
  | seen, y :: rest, x, h => by
    unfold dedupAux at h
    split at h
    · exact dedupAux_fresh seen rest h
    · rcases List.mem_cons.mp h with rfl | h
      · simp_all
      · have := dedupAux_fresh _ rest h
        simp only [List.any_cons, Bool.or_eq_false_iff] at this
        exact this.2

/-- No two kept arms load the same page. -/
theorem dedupAux_pairwise : ∀ (seen : List (List String)) (xs : List (Arm × List String)),
    (dedupAux seen xs).Pairwise (fun p q => sameFlags p.2 q.2 = false)
  | _, [] => by simp [dedupAux]
  | seen, y :: rest => by
    unfold dedupAux
    split
    · exact dedupAux_pairwise seen rest
    · refine List.Pairwise.cons ?_ (dedupAux_pairwise _ rest)
      intro q hq
      have := dedupAux_fresh _ rest hq
      simp only [List.any_cons, Bool.or_eq_false_iff] at this
      rw [sameFlags_comm]; exact this.1

/-- Nothing is lost: every input arm loads a page that a kept arm (or an arm already in `seen`) loads. -/
theorem dedupAux_covered : ∀ (seen : List (List String)) (xs : List (Arm × List String)) {x}, x ∈ xs →
    (∃ s ∈ seen, sameFlags x.2 s = true) ∨ ∃ y ∈ dedupAux seen xs, sameFlags x.2 y.2 = true
  | _, [], _, h => by simp at h
  | seen, y :: rest, x, h => by
    unfold dedupAux
    split
    · rename_i hs
      rcases List.mem_cons.mp h with rfl | h
      · left
        obtain ⟨s, hs', hss⟩ := List.any_eq_true.mp hs
        exact ⟨s, hs', hss⟩
      · exact dedupAux_covered seen rest h
    · rcases List.mem_cons.mp h with rfl | h
      · right; exact ⟨x, List.mem_cons_self, sameFlags_refl _⟩
      · rcases dedupAux_covered (y.2 :: seen) rest h with ⟨s, hs, hss⟩ | ⟨z, hz, hzz⟩
        · rcases List.mem_cons.mp hs with rfl | hs
          · right; exact ⟨y, List.mem_cons_self, hss⟩
          · left; exact ⟨s, hs, hss⟩
        · right; exact ⟨z, List.mem_cons_of_mem _ hz, hzz⟩

/-- The first arm is always kept. -/
theorem dedupArms_head (a : Arm) (f : List String) (rest : List (Arm × List String)) :
    (dedupArms ((a, f) :: rest)).head? = some a := by
  simp [dedupArms, dedupAux]

theorem dedupArms_length_le (xs : List (Arm × List String)) : (dedupArms xs).length ≤ xs.length := by
  have : ∀ (seen : List (List String)) (xs : List (Arm × List String)), (dedupAux seen xs).length ≤ xs.length := by
    intro seen xs
    induction xs generalizing seen with
    | nil => simp [dedupAux]
    | cons y rest ih =>
      unfold dedupAux
      split
      · exact Nat.le_succ_of_le (ih seen)
      · simp only [List.length_cons]; exact Nat.succ_le_succ (ih _)
  simpa [dedupArms] using this [] xs

/-- Arms with pairwise different flags all stay: the v2 arm is dropped only when it is a duplicate. -/
theorem dedupArms_distinct (a b c : List String) (hab : sameFlags a b = false) (hac : sameFlags a c = false)
    (hbc : sameFlags b c = false) :
    dedupArms [(.rewrite, a), (.v2, b), (.look, c)] = [.rewrite, .v2, .look] := by
  have hba : sameFlags b a = false := by rw [sameFlags_comm]; exact hab
  have hca : sameFlags c a = false := by rw [sameFlags_comm]; exact hac
  have hcb : sameFlags c b = false := by rw [sameFlags_comm]; exact hbc
  simp [dedupArms, dedupAux, hba, hca, hcb]

/-- The v2 arm with no flags is the rewrite again and is dropped. -/
theorem dedupArms_v2_empty (c : List String) :
    (dedupArms [(.rewrite, []), (.v2, []), (.look, c)]).head? = some .rewrite ∧
    Arm.v2 ∉ dedupArms [(.rewrite, []), (.v2, []), (.look, c)] := by
  constructor
  · exact dedupArms_head _ _ _
  · by_cases h : sameFlags c [] = true <;> simp [dedupArms, dedupAux, sameFlags, List.all] at * <;> simp_all

/-- The plans the dedup can produce from the three rewrite arms. -/
def planSets : List (List Arm) := [[.rewrite], [.rewrite, .v2], [.rewrite, .look], [.rewrite, .v2, .look]]

theorem dedup_std (a b c : List String) : dedupArms [(.rewrite, a), (.v2, b), (.look, c)] ∈ planSets := by
  simp only [dedupArms, dedupAux, List.any_nil, List.any_cons, Bool.or_false, Bool.false_eq_true, ite_false]
  split <;> split <;> simp_all [planSets]

/-- A session plan the user can run: A/B/A, no adjacent repeat, original exactly twice, within the 15-minute block. -/
def planOk (p : List Arm) : Bool :=
  p.head? == some .original && p.getLast? == some .original && p.count .original == 2 &&
    (p.zip p.tail).all (fun q => q.1 != q.2) && decide (p.length * recSeconds ≤ 900)

theorem planOk_sets : ∀ mid ∈ planSets, planOk (planOf mid) = true := by decide

/-- The banner text of step `k` (counted from 0) of a plan of `n` steps. -/
def stepText (n k : Nat) (a : Arm) : String :=
  s!"Step {k + 1} of {n}: {a.label}. Swipe with your finger from the top of the page to the bottom and back at your normal reading speed for {recSeconds} s. When it feels laggy, tap 3 times quickly on an empty area (not on text, a link or a button)."

/-! ## One pass -/

/-- A recorded pass in integer units: times in hundredths of a ms, positions in tenth px, part values per mille. -/
structure Record where
  w : Nat
  h : Nat
  maxY10 : Int
  ts : List Int
  ys : List Int
  parts : List (String × List Int)
  touches : List Touch
  /-- The viewport height at every frame (tenth px); empty for a recording made before the field existed. -/
  vh : List Int := []

/-- The reduction of one pass. -/
structure Report where
  total : Stat
  zones : List (Zone × Stat)
  taps : Nat
  felt : List Felt
  parts : List (String × Int × Nat)
  replay : Option (List Stroke)

/-- The reduction of a pass. -/
def reducePass (r : Record) : Report :=
  let fs := r.ts.zip r.ys
  let rows := movingRows fs
  let vh10 : Int := (r.h : Int) * 10
  let tp := taps r.touches
  { total := stat rows
    zones := [Zone.hero, .finish, .rest].map fun z => (z, stat (inZone vh10 r.maxY10 z rows))
    taps := tp.length
    felt := (marksOf tp).map (feltOf vh10 r.maxY10 fs)
    parts := r.parts.map fun (n, vs) => (n, maxStep (r.ys.zip vs), stalls (partSeries r.ys vs))
    replay := replay r.touches r.w r.h }

theorem reducePass_zones_total (r : Record) :
    ((reducePass r).zones.map fun p => p.2.n).foldl (· + ·) 0 = (reducePass r).total.n := by
  have h := zone_counts_sum ((r.h : Int) * 10) r.maxY10 (movingRows (r.ts.zip r.ys))
  simp only [reducePass, stat, List.map_cons, List.map_nil, List.foldl_cons, List.foldl_nil]
  omega

/-! ## One pass by toolbar class -/

/-- Whether the record carries one viewport height per frame (recordings made before the field existed do not). -/
def Record.hasField (r : Record) : Bool := !r.vh.isEmpty && r.vh.length == r.ts.length

/-- The class of every frame; a record without the field has the toolbar still at every frame, as today's reduction treats it. -/
def classesOf (r : Record) : List Class :=
  if r.hasField then classes r.vh else List.replicate r.ts.length .still

theorem classesOf_length (r : Record) : (classesOf r).length = r.ts.length := by
  unfold classesOf
  split
  · rename_i h
    simp [Record.hasField] at h
    simp [classes_length, h.2]
  · simp

/-- A record without the field has every frame still. -/
theorem classesOf_noField {r : Record} (h : r.hasField = false) : ∀ c ∈ classesOf r, c = .still := by
  intro c hc
  simp [classesOf, h] at hc
  exact hc.2

/-- A record whose height never changes has every frame still. -/
theorem classesOf_const {r : Record} {h : Int} (hv : r.vh = List.replicate r.ts.length h) :
    ∀ c ∈ classesOf r, c = .still := by
  intro c hc
  unfold classesOf at hc
  split at hc
  · rw [hv, classes_const] at hc
    exact (List.mem_replicate.1 hc).2
  · exact (List.mem_replicate.1 hc).2

/-- The frames of a record: time, position and class. -/
def classFrames (r : Record) : List (Int × Int × Class) :=
  ((r.ts.zip r.ys).zip (classesOf r)).map fun (f, c) => (f.1, f.2, c)

theorem classFrames_map (r : Record) : (classFrames r).map (fun f => (f.1, f.2.1)) = r.ts.zip r.ys := by
  have hl : (r.ts.zip r.ys).length ≤ (classesOf r).length := by
    rw [classesOf_length, List.length_zip]; exact Nat.min_le_left _ _
  have := List.map_fst_zip hl
  simpa [classFrames, List.map_map, Function.comp_def] using this

/-- The counts of one class of a pass: the whole pass, each zone, and how many frames the class holds. -/
structure ClassReport where
  total : Stat
  zones : List (Zone × Stat)
  frames : Nat

/-- The reduction of the frames of one toolbar class. -/
def reduceClass (r : Record) (c : Class) : ClassReport :=
  let fs := classFrames r
  let vh10 : Int := (r.h : Int) * 10
  let rows := rowsOf c (movingRowsC fs)
  { total := stat rows
    zones := [Zone.hero, .finish, .rest].map fun z => (z, stat (inZone vh10 r.maxY10 z rows))
    frames := (fs.filter fun f => f.2.2 == c).length }

/-- The stat of a zone in a report's zone list. -/
def zoneStatOf (zs : List (Zone × Stat)) (z : Zone) : Stat := ((zs.find? fun p => p.1 == z).map (·.2)).getD (stat [])

/-- The moving and the still frames together are the frames of today's reduction, in total. -/
theorem reduceClass_total_split (r : Record) :
    (reduceClass r .moving).total.n + (reduceClass r .still).total.n = (reducePass r).total.n := by
  have h := rowsOf_split (movingRowsC (classFrames r))
  have hm := congrArg List.length (movingRowsC_map (classFrames r))
  rw [classFrames_map] at hm
  simp only [reduceClass, reducePass, stat, List.length_map] at h hm ⊢
  rw [← hm] at *
  simpa [movingRows] using h

/-- The moving and the still frames together are the frames of today's reduction, in every zone. -/
theorem reduceClass_zone_split (r : Record) (z : Zone) :
    (zoneStatOf (reduceClass r .moving).zones z).n + (zoneStatOf (reduceClass r .still).zones z).n =
      (zoneStatOf (reducePass r).zones z).n := by
  have h := inZone_rowsOf_split ((r.h : Int) * 10) r.maxY10 z (movingRowsC (classFrames r))
  have hm := movingRowsC_map (classFrames r)
  rw [classFrames_map] at hm
  rw [hm] at h
  cases z <;> simpa [zoneStatOf, reduceClass, reducePass, stat, hm] using h

/-- Every frame of one class or the other: the frame counts add up to the frames of the record. -/
theorem reduceClass_frames_split (r : Record) :
    (reduceClass r .moving).frames + (reduceClass r .still).frames = (r.ts.zip r.ys).length := by
  have key : ∀ l : List (Int × Int × Class), (l.filter fun f => f.2.2 == Class.moving).length +
      (l.filter fun f => f.2.2 == Class.still).length = l.length := by
    intro l
    induction l with
    | nil => simp
    | cons f t ih => obtain ⟨_, _, c⟩ := f; cases c <;> simp <;> omega
  have := key (classFrames r)
  have hl := congrArg List.length (classFrames_map r)
  simp only [List.length_map] at hl
  simp only [reduceClass]
  omega

/-- With every frame still, the still class is today's reduction, zone by zone, and the moving class is empty. -/
theorem reduceClass_allStill {r : Record} (h : ∀ c ∈ classesOf r, c = .still) :
    (reduceClass r .still).total = (reducePass r).total ∧ (reduceClass r .still).zones = (reducePass r).zones ∧
      (reduceClass r .moving).total.n = 0 ∧ (reduceClass r .moving).frames = 0 ∧
      (reduceClass r .still).frames = (r.ts.zip r.ys).length := by
  have hf : ∀ f ∈ classFrames r, f.2.2 = Class.still := by
    intro f hf
    simp only [classFrames, List.mem_map] at hf
    obtain ⟨⟨g, c⟩, hg, rfl⟩ := hf
    exact h c (List.of_mem_zip hg).2
  have hr := rowsOf_still (movingRowsC (classFrames r)) (movingRowsC_still _ hf)
  have hm := movingRowsC_map (classFrames r)
  rw [classFrames_map] at hm
  have hlen := congrArg List.length (classFrames_map r)
  simp only [List.length_map] at hlen
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · simp [reduceClass, reducePass, hr.1, hm]
  · simp [reduceClass, reducePass, hr.1, hm]
  · simp [reduceClass, hr.2, stat]
  · simp only [reduceClass]
    rw [List.filter_eq_nil_iff.2]
    · rfl
    · intro f hf'; simp [hf f hf']
  · simp only [reduceClass]
    rw [List.filter_eq_self.2]
    · exact hlen
    · intro f hf'; simp [hf f hf']

/-- A recording without the field is today's reduction (the still class), and the moving class holds nothing. -/
theorem reduceClass_noField {r : Record} (h : r.hasField = false) :
    (reduceClass r .still).total = (reducePass r).total ∧ (reduceClass r .still).zones = (reducePass r).zones ∧
      (reduceClass r .moving).total.n = 0 ∧ (reduceClass r .moving).frames = 0 :=
  have := reduceClass_allStill (classesOf_noField h)
  ⟨this.1, this.2.1, this.2.2.1, this.2.2.2.1⟩

/-- A recording whose height never changes is today's reduction too. -/
theorem reduceClass_const {r : Record} {h : Int} (hv : r.vh = List.replicate r.ts.length h) :
    (reduceClass r .still).total = (reducePass r).total ∧ (reduceClass r .still).zones = (reducePass r).zones ∧
      (reduceClass r .moving).total.n = 0 ∧ (reduceClass r .moving).frames = 0 :=
  have := reduceClass_allStill (classesOf_const hv)
  ⟨this.1, this.2.1, this.2.2.1, this.2.2.2.1⟩

/-! ## The comparison within one class -/

/-- The per-pass value of a class in a zone (`none`: the whole pass), in hundredths of a count per 100 intervals. A pass with no frame of the class has no value:
a class that was not present in a pass is not a good score. -/
def classVals (z : Option Zone) (rs : List ClassReport) : List Int :=
  rs.filterMap fun r =>
    if r.frames == 0 then none
    else some (((match z with | none => r.total | some z => zoneStatOf r.zones z).per50 : Nat) : Int)

/-- Today's per-pass value of a zone. -/
def passVal (z : Option Zone) (r : Record) : Int :=
  (((match z with | none => (reducePass r).total | some z => zoneStatOf (reducePass r).zones z).per50 : Nat) : Int)

/-- An arm against the original within one class: the same rule as today's, over the passes that hold the class. -/
def compareClass (z : Option Zone) (orig arm : List ClassReport) : Verdict :=
  verdict (classVals z orig) (classVals z arm)

/-- A pass with no frame of the class adds no value. -/
theorem classVals_empty (z : Option Zone) (r : ClassReport) (rs : List ClassReport) (h : r.frames = 0) :
    classVals z (r :: rs) = classVals z rs := by
  simp [classVals, h]

/-- A pass with frames of the class adds its value first. -/
theorem classVals_cons (z : Option Zone) (r : ClassReport) (rs : List ClassReport) (h : r.frames ≠ 0) :
    classVals z (r :: rs) =
      (((match z with | none => r.total | some z => zoneStatOf r.zones z).per50 : Nat) : Int) :: classVals z rs := by
  simp [classVals, h]

/-- Recordings without the field give, in the still class, today's per-pass values. -/
theorem classVals_noField (z : Option Zone) : ∀ rs : List Record,
    (∀ r ∈ rs, r.hasField = false ∧ r.ts ≠ [] ∧ r.ys ≠ []) →
    classVals z (rs.map fun r => reduceClass r .still) = rs.map (passVal z)
  | [], _ => by simp [classVals]
  | r :: rs, h => by
    have hr := h r (by simp)
    have ih := classVals_noField z rs (fun x hx => h x (by simp [hx]))
    have ha := reduceClass_allStill (classesOf_noField hr.1)
    have hpos : (reduceClass r .still).frames ≠ 0 := by
      rw [ha.2.2.2.2]
      have h1 : r.ts.length ≠ 0 := fun e => hr.2.1 (List.length_eq_zero_iff.1 e)
      have h2 : r.ys.length ≠ 0 := fun e => hr.2.2 (List.length_eq_zero_iff.1 e)
      rw [List.length_zip]
      have := Nat.lt_min.2 ⟨Nat.pos_of_ne_zero h1, Nat.pos_of_ne_zero h2⟩
      omega
    rw [List.map_cons, classVals_cons z _ _ hpos, ih, List.map_cons]
    cases z <;> simp [passVal, ha.1, ha.2.1]

/-- Recordings without the field keep today's verdict: the still class decides as the whole pass does. -/
theorem compareClass_noField (z : Option Zone) (orig arm : List Record)
    (ho : ∀ r ∈ orig, r.hasField = false ∧ r.ts ≠ [] ∧ r.ys ≠ [])
    (ha : ∀ r ∈ arm, r.hasField = false ∧ r.ts ≠ [] ∧ r.ys ≠ []) :
    compareClass z (orig.map fun r => reduceClass r .still) (arm.map fun r => reduceClass r .still) =
      verdict (orig.map (passVal z)) (arm.map (passVal z)) := by
  unfold compareClass
  rw [classVals_noField z orig ho, classVals_noField z arm ha]

/-! ## The golden -/

private def statJ (s : Stat) : Json :=
  Json.mkObj [("n", s.n), ("over34", s.over34), ("over50", s.over50), ("per34", s.per34), ("per50", s.per50),
    ("longest", s.longest), ("median", s.median)]

private def pairsJ (l : List (Int × Int)) : Json := Json.arr (l.map fun p => toJson [p.1, p.2]).toArray

private def touchJ (e : Touch) : Json := toJson [Json.num e.t, Json.str e.ph.code, Json.num e.x, Json.num e.y, Json.num e.n]

private def strokeJ (st : Stroke) : Json := Json.mkObj [("f0", st.f0), ("path", pairsJ st.path)]

private def feltJ (f : Felt) : Json :=
  Json.mkObj [("t", f.t), ("y", f.y), ("zone", f.zone.name), ("stat", statJ f.stat)]

private def reportJ (r : Report) : Json :=
  Json.mkObj [("total", statJ r.total), ("zones", Json.mkObj (r.zones.map fun p => (p.1.name, statJ p.2))),
    ("taps", r.taps), ("felt", Json.arr (r.felt.map feltJ).toArray),
    ("parts", Json.mkObj (r.parts.map fun (n, m, s) => (n, Json.mkObj [("maxStep", m), ("stalls", s)])))]

private def recordJ (r : Record) (arm : Arm) (pass : Nat) : Json :=
  Json.mkObj [("schema", "fw.phone.record.int/1"), ("arm", arm.code), ("pass", pass), ("w", r.w), ("h", r.h),
    ("maxY10", r.maxY10), ("t", toJson r.ts), ("y", toJson r.ys),
    ("p", Json.mkObj (r.parts.map fun (n, vs) => (n, toJson vs))), ("touches", Json.arr (r.touches.map touchJ).toArray)]

private def lcg (s : Nat) : Nat := (s * 1103515245 + 12345) % 2147483648

private def lcgs : Nat → Nat → List Nat
  | 0, _ => []
  | n + 1, s => lcg s :: lcgs n (lcg s)

private def cumsum : Int → List Int → List Int
  | _, [] => []
  | t, d :: ds => (t + d) :: cumsum (t + d) ds

private def synthN : Nat := 480

private def synthVh : Int := 932

private def synthMaxY10 : Int := 30000

private def synthSpecs : List (Nat × Int) := [(30, 0), (100, 6000), (170, 12000), (280, 18000), (360, 24000)]

private def synthTaps : List (Nat × Int × Int) :=
  [(240, 1000, 4000), (245, 2150, 4000), (251, 2180, 4000), (257, 2160, 4000), (445, 2000, 4200), (451, 2030, 4200),
    (457, 2010, 4200)]

private def synthDt (k : Nat) (r : Nat) : Int :=
  if k = 50 then 6200 else if k = 51 then 5400 else if k = 130 then 4100 else if k = 200 then 5800
  else if k = 210 then 4100 else if k = 395 then 9000 else if k = 400 then 3600
  else 1617 + ((r / 65536 : Nat) % 101 : Nat)

private def synthY (k : Nat) : Int :=
  match (synthSpecs.filter fun s => s.1 < k).getLast? with
  | some (ks, y0) => y0 + 100 * min 60 ((k : Int) - ks)
  | none => 0

private def clamp01 (v : Int) : Int := max 0 (min 1000 v)

private def synthFrac (y : Int) : Int := y * 1000 / (synthVh * 10)

/-- Frame `k` shows the value the page wrote in frame `k - 1` (the recorder's callback runs first), so each part is a function of `synthY (k - 1)`. -/
private def synthHero (k : Nat) : Int := 1000 - clamp01 (synthFrac (synthY (if 110 ≤ k - 1 ∧ k - 1 ≤ 113 then 109 else k - 1)))

private def synthPeople (k : Nat) : Int := clamp01 ((synthFrac (synthY (k - 1)) - 720) * 1000 / 280)

private def synthFade (k : Nat) : Int := clamp01 ((synthY (k - 1) - (synthMaxY10 - synthVh * 10)) * 1000 / (synthVh * 10))

private def synthTouches (ts : List Int) : List Touch :=
  let tm (k : Nat) : Int := ts.getD k 0 - 300
  let stroke (s : Nat × Int) : List (Nat × Touch) :=
    ⟨s.1, ⟨tm s.1, .start, 2150, 8800, 1⟩⟩ ::
      ((List.range 60).map fun j => (s.1 + j + 1, ⟨tm (s.1 + j + 1), .move, 2150 + 10 * ((j + 1 : Nat) % 3 : Nat), 8800 - 100 * ((j + 1 : Nat) : Int), 1⟩)) ++
      [(s.1 + 61, ⟨tm (s.1 + 61), .stop, 2150, 2800, 0⟩)]
  let tap (s : Nat × Int × Int) : List (Nat × Touch) :=
    [(s.1, ⟨tm s.1, .start, s.2.1, s.2.2, 1⟩), (s.1 + 2, ⟨tm (s.1 + 2), .stop, s.2.1, s.2.2, 0⟩)]
  let all := synthSpecs.flatMap stroke ++ synthTaps.flatMap tap
  (all.mergeSort fun a b => decide (a.1 ≤ b.1)).map (·.2)

private def synthRecord (_ : Unit) : Record :=
  let n := synthN
  let dts := (List.range n).zip (lcgs n 42) |>.map fun (k, r) => synthDt k r
  let ts := cumsum 100000 dts
  { w := 430, h := 932, maxY10 := synthMaxY10, ts := ts, ys := (List.range n).map synthY
    parts := [("hero", (List.range n).map synthHero), ("people", (List.range n).map synthPeople),
      ("fade", (List.range n).map synthFade)]
    touches := synthTouches ts }

/-- Frame of a time on the grid of the first replayed stroke. -/
private def markFrames (r : Record) : List Nat :=
  let t0 := t0Of (replayStrokes r.touches)
  (marksOf (taps r.touches)).map fun m => frameOf t0 m.t

private def replayJ (r : Record) : Json :=
  match (reducePass r).replay with
  | some ss => Json.mkObj [("strokes", Json.arr (ss.map strokeJ).toArray), ("marks", toJson (markFrames r)),
      ("ok", replayOk ((r.w : Int) * 10) ((r.h : Int) * 10) 2000 ss)]
  | none => Json.null

private def vh10c : Int := 9320

private def maxc : Int := 30000

private def zoneCases : List Int := [-5, 0, 18639, 18640, 18641, 20679, 20680, 29999, 30000]

private def statCases : List (List (Int × Int)) :=
  [[(0, 0), (1667, 0), (3334, 100), (5001, 200), (9001, 200), (10668, 300), (15668, 20000)],
   [(0, 0), (100, 5)], [(0, 0)], [], [(0, 0), (1700, 10), (3400, 20), (6900, 30), (11900, 40), (13600, 50)]]

private def verdictCases : List (List Int × List Int) :=
  [([100, 110], [50]), ([100, 110], [50, 105]), ([100, 110], [100]), ([100, 200], [10]), ([100, 110], [200]),
   ([100, 110], [125]), ([100, 110], [121]), ([100, 110], [119]), ([100], [10]), ([], [10]), ([100, 110], []),
   ([100, 100], [99]), ([100, 100], [100]), ([100, 100], [101]), ([300, 100, 200], [0, 50])]

private def partCases : List (List (Int × Int)) :=
  [[(0, 0), (10, 100), (20, 100), (30, 100), (40, 300), (50, 1000), (60, 1000)], [(0, 500), (0, 500), (10, 500)],
   [(0, 0), (10, 0), (20, 1000), (30, 1000)], [], [(5, 700)]]

/-- (positions, values): a value read in frame `i + 1` came from the position of frame `i`. -/
private def seriesCases : List (List Int × List Int) :=
  [([100, 100, 200, 300], [0, 500, 500, 600]), ([100, 200, 300, 400], [0, 500, 500, 500]), ([0, 0, 0], [500, 500, 500]),
   ([100, 200], [0, 1000]), ([], []), ([5], [700]), ([10, 20, 30], [0, 0, 0])]

private def dedupCases : List (List (Arm × List String)) :=
  [[(.rewrite, []), (.v2, []), (.look, ["engine.scroll:lean"])],
   [(.rewrite, []), (.v2, ["hero.exit:css"]), (.look, ["hero.exit:css"])],
   [(.rewrite, []), (.v2, ["hero.exit:css", "people.card:css"]), (.look, ["people.card:css", "hero.exit:css"])],
   [(.rewrite, []), (.v2, ["hero.exit:css"]), (.look, ["people.card:css"])],
   [(.rewrite, []), (.v2, []), (.look, [])],
   [(.rewrite, []), (.v2, ["hero.exit:css"]), (.look, [])],
   [(.rewrite, []), (.v2, ["hero.exit:css"]), (.look, ["hero.exit:css", "people.card:css"])]]

private def tp (t x y : Int) : Tap := ⟨t, x, y⟩

private def markCases : List (List Tap) :=
  [[tp 0 100 100, tp 30000 110 100, tp 60000 105 95], [tp 0 100 100, tp 60000 110 100, tp 70000 105 95, tp 80000 100 100],
   [tp 0 100 100, tp 30000 110 100, tp 60000 600 95], [tp 0 100 100, tp 30000 110 100], [],
   [tp 0 100 100, tp 30000 110 100, tp 60000 105 95, tp 90000 105 95, tp 100000 105 95, tp 110000 105 95],
   [tp 0 100 100, tp 30000 110 100, tp 60000 105 95, tp 90000 105 95, tp 100000 105 95]]

private def tc (t : Int) (ph : Phase) (x y : Int) (n : Nat := 1) : Touch := ⟨t, ph, x, y, n⟩

private def streamCases : List (List Touch) :=
  [[tc 0 .start 100 100, tc 10000 .stop 100 100],
   [tc 0 .start 100 100, tc 40000 .stop 100 100],
   [tc 0 .start 100 100, tc 10000 .move 100 300, tc 20000 .stop 100 300],
   [tc 0 .move 100 100, tc 1 .stop 100 100],
   [tc 0 .start 100 100, tc 10000 .cancel 100 100, tc 20000 .start 5 5, tc 30000 .stop 5 5],
   [tc 0 .start 100 100, tc 10000 .start 7 7, tc 12000 .stop 7 7],
   [tc 0 .start 100 100, tc 10000 .move 100 200],
   [tc 0 .start 1000 8000, tc 10000 .move 1000 7000, tc 30000 .move 1000 6000, tc 50000 .move 1000 5000, tc 60000 .stop 1000 5000, tc 70000 .start 1000 8000, tc 71000 .stop 1000 7000],
   [tc 0 .start 1000 8000, tc 10000 .move 1000 7000 2, tc 30000 .stop 1000 6000],
   [tc 0 .start 5000 8000, tc 10000 .move 5000 12000, tc 20000 .stop 5000 12000]]

private def loaderCases : List (Int × Int × Nat × List Stroke) :=
  [(4300, 9320, 100, [⟨0, [(10, 10), (20, 20)]⟩, ⟨5, [(10, 10), (20, 20), (30, 30)]⟩]),
   (4300, 9320, 100, []), (4300, 9320, 100, [⟨0, [(10, 10)]⟩]), (4300, 9320, 100, [⟨0, [(10, 10), (4301, 20)]⟩]),
   (4300, 9320, 100, [⟨0, [(10, 10), (20, -1)]⟩]), (4300, 9320, 100, [⟨0, [(10, 10), (20, 20)]⟩, ⟨1, [(10, 10), (20, 20)]⟩]),
   (4300, 9320, 100, [⟨0, [(10, 10), (20, 20)]⟩, ⟨2, [(10, 10), (20, 20)]⟩]),
   (4300, 9320, 3, [⟨0, [(10, 10), (20, 20)]⟩, ⟨2, [(10, 10), (20, 20)]⟩]),
   (4300, 9320, 4, [⟨0, [(10, 10), (20, 20)]⟩, ⟨2, [(10, 10), (20, 20)]⟩])]

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("slow", slow), ("bad", bad), ("lookback", lookback), ("tapMs", (30000 : Int)),
    ("tapTravel", (100 : Int)), ("gapMs", (50000 : Int)), ("nearPx", (400 : Int)), ("hz", (60 : Int)),
    ("zoneViewports", (2 : Int)), ("recSeconds", recSeconds), ("maxReplayFrames", replayCap)]).compress] ++
  (planSets.flatMap fun mid =>
    let p := planOf mid
    p.zipIdx.map fun (a, k) =>
      (Json.mkObj [("kind", "plan"), ("set", String.intercalate "+" (mid.map Arm.code)), ("step", toJson (k + 1)), ("arm", a.code),
        ("seconds", recSeconds), ("text", stepText p.length k a)]).compress) ++
  (dedupCases.map fun xs =>
    (Json.mkObj [("kind", "dedup"), ("arms", Json.arr (xs.map fun (a, f) => Json.arr #[a.code, toJson f]).toArray),
      ("kept", toJson ((dedupArms xs).map Arm.code))]).compress) ++
  (zoneCases.map fun (y : Int) =>
    (Json.mkObj [("kind", "zone"), ("vh10", vh10c), ("maxY10", maxc), ("y", y), ("zone", (zoneOf vh10c maxc y).name)]).compress) ++
  (statCases.map fun fs =>
    let rows := movingRows fs
    (Json.mkObj [("kind", "stat"), ("frames", pairsJ fs), ("vh10", vh10c), ("maxY10", maxc),
      ("rows", pairsJ (rows.map fun r => (r.dt, r.y))), ("total", statJ (stat rows)),
      ("zones", Json.mkObj ([Zone.hero, .finish, .rest].map fun z => (z.name, statJ (stat (inZone vh10c maxc z rows)))))]).compress) ++
  (verdictCases.map fun (o, a) =>
    (Json.mkObj [("kind", "verdict"), ("orig", toJson o), ("arm", toJson a), ("spread", spread o),
      ("verdict", (verdict o a).name)]).compress) ++
  (partCases.map fun sr =>
    (Json.mkObj [("kind", "part"), ("series", pairsJ sr), ("maxStep", maxStep sr), ("stalls", stalls sr)]).compress) ++
  (seriesCases.map fun (ys, vs) =>
    (Json.mkObj [("kind", "series"), ("ys", toJson ys), ("vs", toJson vs), ("series", pairsJ (partSeries ys vs)),
      ("maxStep", maxStep (ys.zip vs)), ("stalls", stalls (partSeries ys vs))]).compress) ++
  (markCases.map fun l =>
    (Json.mkObj [("kind", "marks"), ("taps", Json.arr (l.map fun t => toJson [t.t, t.x, t.y]).toArray),
      ("marks", Json.arr ((marksOf l).map fun t => toJson [t.t, t.x, t.y]).toArray)]).compress) ++
  (streamCases.map fun ts =>
    (Json.mkObj [("kind", "stream"), ("touches", Json.arr (ts.map touchJ).toArray),
      ("strokes", Json.arr ((strokes ts).map fun s => Json.arr (s.map touchJ).toArray).toArray),
      ("isTap", toJson ((strokes ts).map isTap)), ("taps", Json.arr ((taps ts).map fun t => toJson [t.t, t.x, t.y]).toArray),
      ("single", singleFinger ts),
      ("replay", match replay ts 430 932 with
        | some ss => Json.mkObj [("strokes", Json.arr (ss.map strokeJ).toArray), ("t0", t0Of (replayStrokes ts))]
        | none => Json.null)]).compress) ++
  (loaderCases.map fun (w, h, cap, ss) =>
    (Json.mkObj [("kind", "loader"), ("w10", w), ("h10", h), ("cap", cap), ("strokes", Json.arr (ss.map strokeJ).toArray),
      ("ok", replayOk w h cap ss)]).compress) ++
  (let r := synthRecord ()
   [(Json.mkObj [("kind", "session"), ("record", recordJ r .original 1), ("report", reportJ (reducePass r)),
     ("replay", replayJ r)]).compress])

/-- The bytes of `packages/contracts/golden/device/session.jsonl`. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-session golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-session golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.Session
