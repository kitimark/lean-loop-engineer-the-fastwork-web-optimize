import Fw.Measure.Classes
/-!
# The harness self-check classes (`packages/measure-chromium/src/classes.mjs`)

A harness self-check over `m ≥ 1` runs of the same profile and target, not a verdict. Unlike
`Fw.Measure.classify` (pairwise, absolute bounds `kMax`, `tMax`), every run is compared with the
**first** run, and the thresholds are relative to the frame count and the mean run total.

For one count type with series `r₀, …, r_{m−1}` (`n = |r₀|`, a missing frame counts 0):

* `maxDiff`: the largest number of frames `i < n` where `r_j` differs from `r₀`;
* `spread`: the largest minus the smallest run total; `S`: the sum of the run totals
  (the mean total is `S / m`).

| class | condition (checked in this order) |
|---|---|
| `quarantined` | the type is GC-bound and `maxDiff > 0` |
| `deterministic` | `maxDiff = 0` |
| `stable` | `maxDiff ≤ 2% · n` and `spread ≤ max(3, 0.2% · |S/m|)` |
| `shifting` | `spread ≤ max(3, 2% · |S/m|)` |
| `quarantined` | otherwise |

The thresholds are decided in exact integer arithmetic (`50 · maxDiff ≤ n`,
`spread ≤ 3 ∨ 500 · m · spread ≤ |S|`); the former JS code used binary floating point
(`0.02 * n`, `0.002 * Math.abs(mean)`), which can differ only when a product lands within one
rounding step of a threshold. Types are sorted by `String.<` (code points; the JS sort used UTF-16
code units, the same order for the ASCII names the lane emits).

Proved: `deterministic` is exactly `maxDiff = 0`, i.e. every run equals the first on every frame
(`classOf_det_iff`, `maxDiff_zero_iff`), and for runs no longer than the first this is
`Fw.Measure.Holds .deterministic` (`maxDiff_zero_iff_holds`); a GC-bound type is never `stable` or
`shifting` (`classOf_gc`); `stable` implies the `shifting` spread bound (`stable_spread_shift`);
the class rank never decreases when `maxDiff` or `spread` grows (`classOf_mono_maxDiff`,
`classOf_mono_spread`); `maxDiff` and `spread` bound every run (`diffVs_le_maxDiff`,
`gap_le_spread`).
-/
namespace Fw.Measure.SelfCheck
open Fw.Measure

/-- The self-check classes, strictest first. -/
inductive SClass where
  | deterministic
  | stable
  | shifting
  | quarantined
deriving Repr, DecidableEq

/-- The strictness rank of a class (0 = strictest). -/
def SClass.rank : SClass → Nat
  | .deterministic => 0 | .stable => 1 | .shifting => 2 | .quarantined => 3

/-- The class name on the wire and in the table. -/
def SClass.name : SClass → String
  | .deterministic => "deterministic" | .stable => "stable" | .shifting => "shifting"
  | .quarantined => "quarantined"

/-- The thresholds: a spread floor, the frame fraction `1/frameDen`, the total fractions
`1/stableDen` and `1/shiftDen` of the mean total, and the GC-bound types.
-/
structure Thresholds where
  floor : Nat
  frameDen : Nat
  stableDen : Nat
  shiftDen : Nat
  gcBound : List String

/-- The harness thresholds: floor 3, 2 % of the frames, 0.2 % and 2 % of the mean total; GC-bound
by nature (collection timing, not page work) are the DOM/resource gauges, `Layer.deleted` and the
GC events.
-/
def harness : Thresholds :=
  ⟨3, 50, 500, 50,
   ["metric.Nodes", "metric.LayoutObjects", "metric.Documents", "metric.Frames", "metric.Resources",
    "metric.JSEventListeners", "trace.Layer.deleted", "trace.MinorGC", "trace.MajorGC"]⟩

/-- The spread is within `max(floor, |S| / (d·m))` (cross-multiplied, so exact). -/
def spreadOk (floor d s m : Nat) (S : Int) : Bool := decide (s ≤ floor) || decide (d * m * s ≤ S.natAbs)

/-- The observations of one count type: frames of the first run, largest differing-frame count,
total spread, sum of the totals, number of runs.
-/
structure Obs where
  n : Nat
  maxDiff : Nat
  spread : Nat
  sum : Int
  runs : Nat
deriving Repr, DecidableEq

/-- The class of one count type (`gc`: the type is GC-bound).

(the first matching case, top to bottom)
-/
def classOf (θ : Thresholds) (gc : Bool) (o : Obs) : SClass :=
  if gc = true ∧ 0 < o.maxDiff then .quarantined
  else if o.maxDiff = 0 then .deterministic
  else if θ.frameDen * o.maxDiff ≤ o.n ∧ spreadOk θ.floor θ.stableDen o.spread o.runs o.sum = true then .stable
  else if spreadOk θ.floor θ.shiftDen o.spread o.runs o.sum = true then .shifting
  else .quarantined

-- the real rows of the 7-run set in packages/measure-chromium/README.md (385 frames)
#guard classOf harness false ⟨385, 1, 1, 2421, 7⟩ == .stable          -- hasDamage 346×6/345
#guard classOf harness false ⟨385, 4, 4, 1528, 4⟩ == .shifting        -- trace.Commit 381×3/385
#guard classOf harness false ⟨385, 4, 40, 1528, 4⟩ == .quarantined
#guard classOf harness true ⟨385, 1, 0, 100, 3⟩ == .quarantined
#guard classOf harness true ⟨385, 0, 0, 100, 3⟩ == .deterministic
#guard classOf harness false ⟨385, 8, 0, 0, 2⟩ == .shifting            -- 50·8 = 400 > 385
#guard classOf harness false ⟨400, 8, 0, 0, 2⟩ == .stable              -- 50·8 = 400 ≤ 400
#guard classOf harness false ⟨399, 8, 0, 0, 2⟩ == .shifting
#guard classOf harness false ⟨100, 1, 4, 2000, 1⟩ == .stable           -- 500·1·4 = 2000 ≤ 2000
#guard classOf harness false ⟨100, 1, 4, -1999, 1⟩ == .shifting

/-! ## Observations from the series -/

/-- The number of frames `i < n` where two series differ (padded with zeros). -/
def diffVs (n : Nat) (a b : Series) : Nat :=
  ((List.range n).filter fun i => valAt a i != valAt b i).length

/-- The largest number of frames in which a run differs from the first run (over the first run's
frames; 0 without runs).
-/
def maxDiff : List Series → Nat
  | [] => 0
  | r₀ :: rs => maxOf ((r₀ :: rs).map (diffVs r₀.length r₀))

/-- The largest of a non-empty list of integers, starting from `x`. -/
def hi (x : Int) (l : List Int) : Int := l.foldr max x

/-- The smallest of a non-empty list of integers, starting from `x`. -/
def lo (x : Int) (l : List Int) : Int := l.foldr min x

/-- The spread of the run totals: largest minus smallest (0 without runs). -/
def spreadOf : List Int → Nat
  | [] => 0
  | t :: ts => (hi t ts - lo t ts).toNat

/-- The observations of one count type over the runs. -/
def obs (rs : List Series) : Obs :=
  ⟨(rs.headD []).length, maxDiff rs, spreadOf (rs.map total), sumBy total rs, rs.length⟩

#guard obs [[1, 2, 3], [1, 3, 3], [1, 2]] == ⟨3, 1, 4, 16, 3⟩
#guard obs [[1, 2], [1, 2, 9]] == ⟨2, 0, 9, 15, 2⟩

/-- One row of the self-check table: type, class, `maxDiff`, spread and the run totals. -/
structure SRow where
  type : String
  cls : SClass
  maxDiff : Nat
  spread : Nat
  totals : List Int
deriving Repr, DecidableEq

/-- The self-check of every count type occurring in any frame of any run (sorted by name). -/
def check (θ : Thresholds) (runs : List (List Counts)) : List SRow :=
  (keysOf runs.flatten).map fun k =>
    let rs := runs.map (seriesOf k)
    let o := obs rs
    ⟨k, classOf θ (θ.gcBound.contains k) o, o.maxDiff, o.spread, rs.map total⟩

#guard check harness [[[("a", 1)], [("a", 0), ("b", 2)]], [[("a", 1)], [("b", 2)]]] ==
  [⟨"a", .deterministic, 0, 0, [1, 1]⟩, ⟨"b", .deterministic, 0, 0, [2, 2]⟩]
#guard (check harness [[[("trace.MinorGC", 1)]], [[("trace.MinorGC", 0)]]]).map (·.cls) == [.quarantined]

/-- Frame alignment: every run's frame keys (phase, scroll offset) equal the first run's, frame by
frame and in number.
-/
def aligned {α : Type} [DecidableEq α] (ks : List (List α)) : Bool := ks.all (· == ks.headD [])

#guard aligned [[(1 : Nat), 2], [1, 2], [1, 2]]
#guard !aligned [[(1 : Nat), 2], [1, 2, 3]]
#guard aligned ([] : List (List Nat))

/-! ## Theorems -/

/-- `deterministic` is exactly "no frame differs from the first run". -/
theorem classOf_det_iff (θ : Thresholds) (gc : Bool) (o : Obs) :
    classOf θ gc o = .deterministic ↔ o.maxDiff = 0 := by
  unfold classOf
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega

/-- A GC-bound type is `deterministic` or `quarantined`, never `stable` or `shifting`. -/
theorem classOf_gc (θ : Thresholds) (o : Obs) :
    classOf θ true o = .deterministic ∨ classOf θ true o = .quarantined := by
  unfold classOf
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega

/-- `stable` holds exactly under its row of the table. -/
theorem classOf_stable_iff (θ : Thresholds) (gc : Bool) (o : Obs) :
    classOf θ gc o = .stable ↔ gc = false ∧ 0 < o.maxDiff ∧ θ.frameDen * o.maxDiff ≤ o.n ∧
      spreadOk θ.floor θ.stableDen o.spread o.runs o.sum = true := by
  unfold classOf
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega

/-- `shifting` holds exactly under its row of the table (the earlier rows fail). -/
theorem classOf_shifting_iff (θ : Thresholds) (gc : Bool) (o : Obs) :
    classOf θ gc o = .shifting ↔ gc = false ∧ 0 < o.maxDiff ∧
      ¬(θ.frameDen * o.maxDiff ≤ o.n ∧ spreadOk θ.floor θ.stableDen o.spread o.runs o.sum = true) ∧
      spreadOk θ.floor θ.shiftDen o.spread o.runs o.sum = true := by
  unfold classOf
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega

/-- A larger denominator is a tighter spread bound. -/
theorem spreadOk_den {f d d' s m : Nat} {S : Int} (hd : d' ≤ d) (h : spreadOk f d s m S = true) :
    spreadOk f d' s m S = true := by
  simp only [spreadOk, Bool.or_eq_true, decide_eq_true_eq] at *
  rcases h with h | h
  · exact Or.inl h
  · exact Or.inr (Nat.le_trans (Nat.mul_le_mul_right s (Nat.mul_le_mul_right m hd)) h)

/-- A smaller spread stays within any bound the larger one met. -/
theorem spreadOk_anti {f d s s' m : Nat} {S : Int} (hs : s ≤ s') (h : spreadOk f d s' m S = true) :
    spreadOk f d s m S = true := by
  simp only [spreadOk, Bool.or_eq_true, decide_eq_true_eq] at *
  rcases h with h | h
  · exact Or.inl (Nat.le_trans hs h)
  · exact Or.inr (Nat.le_trans (Nat.mul_le_mul_left _ hs) h)

/-- Under the harness thresholds a `stable` type also meets the `shifting` spread bound
(0.2 % of the mean is below 2 %).
-/
theorem stable_spread_shift (gc : Bool) (o : Obs) (h : classOf harness gc o = .stable) :
    spreadOk 3 50 o.spread o.runs o.sum = true :=
  spreadOk_den (d := 500) (by decide) ((classOf_stable_iff harness gc o).mp h).2.2.2

/-- The rank of the class when some frame differs, as a nested case split.

(the first matching case, top to bottom)
-/
theorem rank_pos (θ : Thresholds) (gc : Bool) (o : Obs) (hp : 0 < o.maxDiff) :
    (classOf θ gc o).rank =
      if gc = true then 3
      else if θ.frameDen * o.maxDiff ≤ o.n ∧ spreadOk θ.floor θ.stableDen o.spread o.runs o.sum = true then 1
      else if spreadOk θ.floor θ.shiftDen o.spread o.runs o.sum = true then 2 else 3 := by
  have h0 : o.maxDiff ≠ 0 := Nat.pos_iff_ne_zero.mp hp
  unfold classOf
  cases gc
  · simp only [Bool.false_eq_true, false_and, h0, ↓reduceIte]
    by_cases a : θ.frameDen * o.maxDiff ≤ o.n ∧ spreadOk θ.floor θ.stableDen o.spread o.runs o.sum = true
    · rw [ite_eq_left a, ite_eq_left a]; rfl
    · rw [ite_eq_right a, ite_eq_right a]
      by_cases b : spreadOk θ.floor θ.shiftDen o.spread o.runs o.sum = true
      · rw [ite_eq_left b, ite_eq_left b]; rfl
      · rw [ite_eq_right b, ite_eq_right b]; rfl
  · simp only [true_and, hp, ↓reduceIte]; rfl

/-- More differing frames never give a stricter class. -/
theorem classOf_mono_maxDiff (θ : Thresholds) (gc : Bool) (n d d' s m : Nat) (S : Int) (hd : d ≤ d') :
    (classOf θ gc ⟨n, d, s, S, m⟩).rank ≤ (classOf θ gc ⟨n, d', s, S, m⟩).rank := by
  by_cases z : d = 0
  · subst z
    rw [(classOf_det_iff θ gc ⟨n, 0, s, S, m⟩).mpr rfl]; exact Nat.zero_le _
  have hp : 0 < d := Nat.pos_of_ne_zero z
  rw [rank_pos θ gc _ hp, rank_pos θ gc _ (Nat.lt_of_lt_of_le hp hd)]; dsimp only
  cases gc
  · simp only [Bool.false_eq_true, ↓reduceIte]
    by_cases a' : θ.frameDen * d' ≤ n ∧ spreadOk θ.floor θ.stableDen s m S = true
    · rw [ite_eq_left a', ite_eq_left ⟨Nat.le_trans (Nat.mul_le_mul_left _ hd) a'.1, a'.2⟩]; exact Nat.le_refl _
    · rw [ite_eq_right a']
      by_cases a : θ.frameDen * d ≤ n ∧ spreadOk θ.floor θ.stableDen s m S = true
      · rw [ite_eq_left a]; split <;> omega
      · rw [ite_eq_right a]; exact Nat.le_refl _
  · exact Nat.le_refl _

/-- A larger spread never gives a stricter class. -/
theorem classOf_mono_spread (θ : Thresholds) (gc : Bool) (n d s s' m : Nat) (S : Int) (hs : s ≤ s') :
    (classOf θ gc ⟨n, d, s, S, m⟩).rank ≤ (classOf θ gc ⟨n, d, s', S, m⟩).rank := by
  by_cases z : d = 0
  · subst z
    rw [(classOf_det_iff θ gc ⟨n, 0, s, S, m⟩).mpr rfl]; exact Nat.zero_le _
  have hp : 0 < d := Nat.pos_of_ne_zero z
  rw [rank_pos θ gc _ hp, rank_pos θ gc _ hp]; dsimp only
  cases gc
  · simp only [Bool.false_eq_true, ↓reduceIte]
    by_cases a' : θ.frameDen * d ≤ n ∧ spreadOk θ.floor θ.stableDen s' m S = true
    · rw [ite_eq_left a', ite_eq_left ⟨a'.1, spreadOk_anti hs a'.2⟩]; exact Nat.le_refl _
    · rw [ite_eq_right a']
      by_cases a : θ.frameDen * d ≤ n ∧ spreadOk θ.floor θ.stableDen s m S = true
      · rw [ite_eq_left a]; split <;> omega
      · rw [ite_eq_right a]
        by_cases b' : spreadOk θ.floor θ.shiftDen s' m S = true
        · rw [ite_eq_left b', ite_eq_left (spreadOk_anti hs b')]; exact Nat.le_refl _
        · rw [ite_eq_right b']; split <;> omega
  · exact Nat.le_refl _

/-- `diffVs` is zero exactly when the series agree on every frame below `n`. -/
theorem diffVs_zero_iff (n : Nat) (a b : Series) :
    diffVs n a b = 0 ↔ ∀ i < n, valAt a i = valAt b i := by
  simp [diffVs, List.filter_eq_nil_iff]

/-- `maxDiff` bounds the differing frames of every run against the first. -/
theorem diffVs_le_maxDiff {r₀ r : Series} {rs : List Series} (h : r ∈ r₀ :: rs) :
    diffVs r₀.length r₀ r ≤ maxDiff (r₀ :: rs) :=
  le_maxOf (List.mem_map.mpr ⟨r, h, rfl⟩)

/-- `maxDiff` is zero exactly when every run equals the first run on the first run's frames.

A run shorter than the first counts as zero on its missing frames, as in `diffVs`.
-/
theorem maxDiff_zero_iff (r₀ : Series) (rs : List Series) :
    maxDiff (r₀ :: rs) = 0 ↔ ∀ r ∈ r₀ :: rs, ∀ i < r₀.length, valAt r₀ i = valAt r i := by
  constructor
  · intro h r hr
    exact (diffVs_zero_iff _ _ _).mp (Nat.eq_zero_of_le_zero (h ▸ diffVs_le_maxDiff hr))
  · intro h
    apply Nat.eq_zero_of_le_zero
    apply maxOf_le
    intro x hx
    obtain ⟨r, hr, rfl⟩ := List.mem_map.mp hx
    exact Nat.le_of_eq ((diffVs_zero_iff _ _ _).mpr (h r hr))

/-- `valAt` past the end is zero. -/
theorem valAt_of_le {r : Series} {i : Nat} (h : r.length ≤ i) : valAt r i = 0 := by
  simp [valAt, List.getD_eq_getElem?_getD, List.getElem?_eq_none h]

/-- `diffFrames` is zero exactly when the padded series agree everywhere. -/
theorem diffFrames_zero_iff : ∀ a b : Series, diffFrames a b = 0 ↔ ∀ i, valAt a i = valAt b i
  | [], [] => by simp [diffFrames, valAt]
  | x :: xs, [] => by
    have ih := diffFrames_zero_iff xs []
    simp only [diffFrames, Nat.add_eq_zero_iff, ite_eq_left_iff, ih]
    constructor
    · intro ⟨h1, h2⟩ i
      cases i with
      | zero => simpa [valAt] using h1
      | succ i => simpa [valAt] using h2 i
    · intro h
      refine ⟨fun hx => absurd (by simpa [valAt] using h 0) hx, fun i => by simpa [valAt] using h (i + 1)⟩
  | [], y :: ys => by
    have ih := diffFrames_zero_iff [] ys
    simp only [diffFrames, Nat.add_eq_zero_iff, ite_eq_left_iff, ih]
    constructor
    · intro ⟨h1, h2⟩ i
      cases i with
      | zero => simpa [valAt] using h1
      | succ i => simpa [valAt] using h2 i
    · intro h
      refine ⟨fun hx => absurd (by simpa [valAt] using h 0) hx, fun i => by simpa [valAt] using h (i + 1)⟩
  | x :: xs, y :: ys => by
    have ih := diffFrames_zero_iff xs ys
    simp only [diffFrames, Nat.add_eq_zero_iff, ite_eq_left_iff, ih]
    constructor
    · intro ⟨h1, h2⟩ i
      cases i with
      | zero => simpa [valAt] using h1
      | succ i => simpa [valAt] using h2 i
    · intro h
      refine ⟨fun hx => absurd (by simpa [valAt] using h 0) hx, fun i => by simpa [valAt] using h (i + 1)⟩

/-- For runs no longer than the first, `maxDiff = 0` is the pairwise `deterministic` class of
`Fw.Measure` (every pair of runs agrees on every frame).
-/
theorem maxDiff_zero_iff_holds (r₀ : Series) (rs : List Series)
    (hlen : ∀ r ∈ r₀ :: rs, r.length ≤ r₀.length) :
    maxDiff (r₀ :: rs) = 0 ↔ Holds .deterministic (r₀ :: rs) := by
  rw [maxDiff_zero_iff]
  have full : ∀ r ∈ r₀ :: rs, (∀ i < r₀.length, valAt r₀ i = valAt r i) → ∀ i, valAt r₀ i = valAt r i := by
    intro r hr h i
    by_cases hi : i < r₀.length
    · exact h i hi
    · have h1 : r₀.length ≤ i := Nat.le_of_not_lt hi
      rw [valAt_of_le h1, valAt_of_le (Nat.le_trans (hlen r hr) h1)]
  constructor
  · intro h a ha b hb
    show diffFrames a b = 0
    rw [diffFrames_zero_iff]
    intro i
    rw [← full a ha (h a ha) i, full b hb (h b hb) i]
  · intro h r hr i _
    have := (diffFrames_zero_iff r₀ r).mp (h r₀ (List.mem_cons_self) r hr)
    exact this i

/-- `hi` is an upper bound. -/
theorem le_hi {x y : Int} : ∀ {l : List Int}, (y = x ∨ y ∈ l) → y ≤ hi x l
  | [], h => by simp at h; simp [hi, h]
  | z :: zs, h => by
    simp only [hi, List.foldr_cons] at *
    rcases h with h | h
    · exact Int.le_trans (le_hi (Or.inl h)) (Int.le_max_right _ _)
    · rcases List.mem_cons.mp h with h | h
      · subst h; exact Int.le_max_left _ _
      · exact Int.le_trans (le_hi (Or.inr h)) (Int.le_max_right _ _)

/-- `lo` is a lower bound. -/
theorem lo_le {x y : Int} : ∀ {l : List Int}, (y = x ∨ y ∈ l) → lo x l ≤ y
  | [], h => by simp at h; simp [lo, h]
  | z :: zs, h => by
    simp only [lo, List.foldr_cons] at *
    rcases h with h | h
    · exact Int.le_trans (Int.min_le_right _ _) (lo_le (Or.inl h))
    · rcases List.mem_cons.mp h with h | h
      · subst h; exact Int.min_le_left _ _
      · exact Int.le_trans (Int.min_le_right _ _) (lo_le (Or.inr h))

/-- The spread bounds the gap between any two run totals. -/
theorem gap_le_spread {a b : Int} : ∀ {ts : List Int}, a ∈ ts → b ∈ ts → (a - b).natAbs ≤ spreadOf ts
  | [], ha, _ => by simp at ha
  | t :: ts, ha, hb => by
    have ha' : a = t ∨ a ∈ ts := List.mem_cons.mp ha
    have hb' : b = t ∨ b ∈ ts := List.mem_cons.mp hb
    have h1 := le_hi ha'; have h2 := lo_le ha'; have h3 := le_hi hb'; have h4 := lo_le hb'
    simp only [spreadOf]
    omega

/-- Each row's class is the class of that type's observations (with its GC-bound flag), and its
`maxDiff`, spread and totals are those observations.
-/
theorem check_sound (θ : Thresholds) (runs : List (List Counts)) :
    ∀ row ∈ check θ runs, let rs := runs.map (seriesOf row.type)
      row.cls = classOf θ (θ.gcBound.contains row.type) (obs rs) ∧ row.maxDiff = maxDiff rs ∧
      row.spread = spreadOf row.totals ∧ row.totals = rs.map total := by
  intro row h
  simp only [check, List.mem_map] at h
  obtain ⟨k, _, rfl⟩ := h
  exact ⟨rfl, rfl, rfl, rfl⟩

/-- `aligned` holds exactly when all key lists are equal. -/
theorem aligned_iff {α : Type} [DecidableEq α] (ks : List (List α)) :
    aligned ks = true ↔ ∀ a ∈ ks, ∀ b ∈ ks, a = b := by
  cases ks with
  | nil => simp [aligned]
  | cons k ks =>
    simp only [aligned, List.headD_cons, List.all_eq_true, beq_iff_eq]
    constructor
    · intro h a ha b hb; rw [h a ha, h b hb]
    · intro h a ha; exact h a ha k List.mem_cons_self

end Fw.Measure.SelfCheck
