import Lean.Data.Json
import Fw.Measure.WebKit
import Fw.Measure.WebKitLagPhase
/-!
# Where the Simulator lag comes from (`packages/measure-webkit/src/lag/reduce.mjs`)
The pure reductions of the webkit-lag-probe: scroll regions (through the zones of `Fw.Measure.WebKit`), paint attribution
to parts, the ranking of counters by their window-to-baseline ratio (unit-free), the verdict on an arm difference from
per-pass ranges, and the top steps of a region.
-/
namespace Fw.Measure.WebKitLag
open Lean Fw.Measure.WebKit

/-! ## Rectangles -/

/-- An axis-aligned rectangle in integer units (the probe uses quarter CSS px). -/
structure Rect where
  x0 : Int
  y0 : Int
  x1 : Int
  y1 : Int
  deriving Repr, BEq, DecidableEq

/-- The area of a rectangle, 0 when it is empty or inverted. -/
def Rect.area (r : Rect) : Int := max 0 (r.x1 - r.x0) * max 0 (r.y1 - r.y0)

/-- The intersection of two rectangles (inverted when they are disjoint). -/
def Rect.inter (a b : Rect) : Rect := ⟨max a.x0 b.x0, max a.y0 b.y0, min a.x1 b.x1, min a.y1 b.y1⟩

/-- Areas are never negative. -/
theorem Rect.area_nonneg (r : Rect) : 0 ≤ r.area :=
  Int.mul_nonneg (by omega) (by omega)

/-- The overlap of two rectangles is no larger than the first. -/
theorem Rect.inter_area_le (a b : Rect) : (a.inter b).area ≤ a.area := by
  obtain ⟨a0, a1, a2, a3⟩ := a
  obtain ⟨b0, b1, b2, b3⟩ := b
  simp only [Rect.area, Rect.inter]
  apply Int.mul_le_mul <;> omega

/-! ## Which part a paint belongs to -/

/-- A named part box (a `data-fw` element, or a section of the original) in viewport coordinates. -/
structure Box where
  name : String
  r : Rect
  deriving Repr, BEq

/-- A box covers a paint when the paint is non-empty and at least half of it lies inside the box. -/
def covers (clip : Rect) (b : Box) : Bool :=
  decide (0 < clip.area) && decide (clip.area ≤ 2 * (clip.inter b.r).area)

/-- The smallest box of a list, the first of equal area. -/
def pick : List Box → Option Box
  | [] => none
  | b :: bs =>
    match pick bs with
    | none => some b
    | some c => if c.r.area < b.r.area then some c else some b

/-- The chosen box is one of the list. -/
theorem pick_mem : ∀ {l : List Box} {b : Box}, pick l = some b → b ∈ l
  | [], b, h => by simp [pick] at h
  | x :: xs, b, h => by
    unfold pick at h
    cases hp : pick xs with
    | none => rw [hp] at h; simp at h; simp [h]
    | some c =>
      rw [hp] at h
      have hc := pick_mem hp
      by_cases hl : c.r.area < x.r.area
      · simp [hl] at h; subst h; exact List.mem_cons_of_mem _ hc
      · simp [hl] at h; subst h; exact List.mem_cons_self

/-- No box of the list is smaller than the chosen one. -/
theorem pick_min : ∀ {l : List Box} {b : Box}, pick l = some b → ∀ c ∈ l, b.r.area ≤ c.r.area
  | [], b, h, c, hc => by simp at hc
  | x :: xs, b, h, c, hc => by
    unfold pick at h
    cases hp : pick xs with
    | none =>
      rw [hp] at h; simp at h; subst h
      have : xs = [] := by
        cases xs with
        | nil => rfl
        | cons y ys => simp [pick] at hp; cases hq : pick ys <;> simp [hq] at hp <;> split at hp <;> simp at hp
      subst this; simp at hc; subst hc; exact Int.le_refl _
    | some d =>
      rw [hp] at h
      have hd := pick_min hp
      by_cases hl : d.r.area < x.r.area
      · simp [hl] at h; subst h
        rcases List.mem_cons.mp hc with rfl | hc'
        · omega
        · exact hd c hc'
      · simp [hl] at h; subst h
        rcases List.mem_cons.mp hc with rfl | hc'
        · exact Int.le_refl _
        · have := hd c hc'; omega

/-- The part a paint is attributed to: the smallest covering box, `none` when no box covers it. -/
def owner (boxes : List Box) (clip : Rect) : Option String :=
  (pick (boxes.filter (covers clip))).map (·.name)

/-- The attributed part, or `(none)`. -/
def ownerName (boxes : List Box) (clip : Rect) : String := (owner boxes clip).getD "(none)"

/-- An attributed paint lies in a box that covers it. -/
theorem owner_covers {boxes : List Box} {clip : Rect} {n : String} (h : owner boxes clip = some n) :
    ∃ b ∈ boxes, b.name = n ∧ covers clip b = true := by
  unfold owner at h
  cases hp : pick (boxes.filter (covers clip)) with
  | none => simp [hp] at h
  | some b =>
    rw [hp] at h
    simp at h
    have hm := List.mem_filter.mp (pick_mem hp)
    exact ⟨b, hm.1, h, hm.2⟩

/-- An empty paint is attributed to no part. -/
theorem owner_empty (boxes : List Box) (clip : Rect) (h : clip.area = 0) : owner boxes clip = none := by
  have : (boxes.filter (covers clip)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro b _
    simp [covers, h]
  simp [owner, this, pick]

/-- No box means no part. -/
theorem owner_nil (clip : Rect) : owner [] clip = none := by simp [owner, pick]

/-- A paint is attributed to a part of the smallest area among the boxes that cover it. -/
theorem owner_smallest {boxes : List Box} {clip : Rect} {n : String} (h : owner boxes clip = some n) :
    ∃ b ∈ boxes, b.name = n ∧ ∀ c ∈ boxes, covers clip c = true → b.r.area ≤ c.r.area := by
  unfold owner at h
  cases hp : pick (boxes.filter (covers clip)) with
  | none => simp [hp] at h
  | some b =>
    rw [hp] at h
    simp at h
    have hm := List.mem_filter.mp (pick_mem hp)
    refine ⟨b, hm.1, h, fun c hc hcov => pick_min hp c (List.mem_filter.mpr ⟨hc, hcov⟩)⟩

/-! ## Ledgers: sums by key, in order of first appearance -/

/-- Add `v` under key `k`, appending the key when it is new. -/
def addTo (k : String) (v : Int) : List (String × Int) → List (String × Int)
  | [] => [(k, v)]
  | (k', v') :: t => if k' == k then (k', v' + v) :: t else (k', v') :: addTo k v t

/-- The sum of the values of a ledger. -/
def total (l : List (String × Int)) : Int := (l.map (·.2)).sum

/-- Adding to a ledger adds to its total. -/
theorem addTo_total (k : String) (v : Int) : ∀ l, total (addTo k v l) = total l + v
  | [] => by simp [addTo, total]
  | (k', v') :: t => by
    unfold addTo
    by_cases h : k' == k
    · simp [h, total]; omega
    · simp [h, total]; have := addTo_total k v t; simp [total] at this; omega

/-- The ledger of a list of entries: values summed by key. -/
def byKey (l : List (String × Int)) : List (String × Int) :=
  l.foldl (fun acc p => addTo p.1 p.2 acc) []

private theorem foldl_total (l : List (String × Int)) : ∀ acc : List (String × Int),
    total (l.foldl (fun a p => addTo p.1 p.2 a) acc) = total acc + total l := by
  induction l with
  | nil => intro acc; simp [total]
  | cons p t ih =>
    intro acc
    simp only [List.foldl_cons, ih, addTo_total]
    simp [total]; omega

/-- Nothing is lost or invented by summing by key. -/
theorem byKey_total (l : List (String × Int)) : total (byKey l) = total l := by
  have := foldl_total l []
  simpa [byKey, total] using this

/-- The part a leaf part belongs to: its name up to the first `-`. -/
def coarse (s : String) : String := (s.splitOn "-").headD s

/-- The ledger with leaf parts rolled up into their parent part. -/
def rollup (l : List (String × Int)) : List (String × Int) := byKey (l.map fun p => (coarse p.1, p.2))

/-- Rolling up keeps the total. -/
theorem rollup_total (l : List (String × Int)) : total (rollup l) = total l := by
  unfold rollup
  rw [byKey_total]
  simp [total, Function.comp_def]


/-! ## Scroll regions, through the zones of `Fw.Measure.WebKit` -/

/-- The scroll regions of the probe. -/
inductive Region where
  | a | b | calm | other
  deriving DecidableEq, Repr

/-- The region name written in the output. -/
def Region.name : Region → String
  | .a => "A" | .b => "B" | .calm => "calm" | .other => "other"

/-- The zone of scroll position `y` at zone height `vh`: `Fw.Measure.WebKit.zoneIx` of the position (0 below `y = 0`). -/
def zoneOf (vh : Nat) (y : Int) : Nat := zoneIx vh (y : Rat)

/-- Dividing by a positive whole number: `n ≤ y / h` exactly when `n * h ≤ y`. -/
theorem rat_le_div_iff {n y : Int} {h : Nat} (hh : 0 < h) :
    (n : Rat) ≤ (y : Rat) / (h : Rat) ↔ n * (h : Int) ≤ y := by
  have hpos : (0 : Rat) < (h : Rat) := Rat.natCast_pos.mpr hh
  have hne : (h : Rat) ≠ 0 := Rat.ne_of_gt hpos
  have hc : ((n * (h : Int) : Int) : Rat) = (n : Rat) * (h : Rat) := by
    rw [Rat.intCast_mul, Rat.intCast_natCast]
  rw [← Rat.intCast_le_intCast, hc]
  constructor
  · intro hle
    have := Rat.mul_le_mul_of_nonneg_right hle (Rat.le_of_lt hpos)
    rwa [Rat.div_mul_cancel hne] at this
  · intro hle
    apply Rat.le_of_mul_le_mul_right _ hpos
    rwa [Rat.div_mul_cancel hne]

/-- Zone `n` or higher starts at `n * vh`: a position is in zone `n` or above exactly when `n * vh ≤ y` (for `n ≥ 1`). -/
theorem zoneOf_ge_iff {vh : Nat} (hv : 0 < vh) {n : Nat} (hn : 0 < n) (y : Int) :
    n ≤ zoneOf vh y ↔ (n : Int) * vh ≤ y := by
  unfold zoneOf zoneIx
  have h1 : n ≤ (Rat.floor ((y : Rat) / (vh : Rat))).toNat ↔ (n : Int) ≤ Rat.floor ((y : Rat) / (vh : Rat)) := by
    omega
  rw [h1, Rat.le_floor_iff, Rat.intCast_natCast]
  have := rat_le_div_iff (n := (n : Int)) (y := y) (h := vh) hv
  rwa [Rat.intCast_natCast] at this

/-- Zone 0 is everything below one zone height (negative positions included). -/
theorem zoneOf_eq_zero_iff {vh : Nat} (hv : 0 < vh) (y : Int) : zoneOf vh y = 0 ↔ y < vh := by
  have := zoneOf_ge_iff hv (n := 1) (by omega) y
  have h1 : zoneOf vh y = 0 ↔ ¬ (1 ≤ zoneOf vh y) := by omega
  rw [h1, this]; omega

/-- The region of a scroll position `y` on a page whose last scroll position is `maxY`, at zone height `vh` (the viewport
height). Region A is zone 0 of the position (the first viewport, the hero cards leaving). Region B is zone 0 of the
distance to the end `maxY - y` (the last viewport). The baseline `calm` is zone 2 or above from both ends; zone 1 from
either end is in no region. A page shorter than a viewport is all A. -/
def regionOf (vh : Nat) (maxY y : Int) : Region :=
  if zoneOf vh y = 0 then .a
  else if zoneOf vh (maxY - y) = 0 then .b
  else if 2 ≤ zoneOf vh y ∧ 2 ≤ zoneOf vh (maxY - y) then .calm
  else .other

/-- The first viewport of the page is region A (the hero cards leaving). -/
theorem regionOf_a {vh : Nat} (hv : 0 < vh) {maxY y : Int} (h : y < vh) : regionOf vh maxY y = .a := by
  have := (zoneOf_eq_zero_iff hv y).mpr h
  simp [regionOf, this]

/-- Region A is exactly zone 0 of `Fw.Measure.WebKit.zoneIx` at the viewport height. -/
theorem regionOf_a_iff_zone {vh : Nat} {maxY : Int} (y : Int) :
    regionOf vh maxY y = .a ↔ zoneIx vh (y : Rat) = 0 := by
  show regionOf vh maxY y = .a ↔ zoneOf vh y = 0
  unfold regionOf
  by_cases h : zoneOf vh y = 0
  · simp [h]
  · by_cases h2 : zoneOf vh (maxY - y) = 0
    · simp [h, h2]
    · by_cases h3 : 2 ≤ zoneOf vh y ∧ 2 ≤ zoneOf vh (maxY - y) <;> simp [h, h2, h3]

/-- The last viewport of the page is region B (the end of the page), unless it is also region A. -/
theorem regionOf_b {vh : Nat} (hv : 0 < vh) {maxY y : Int} (h1 : vh ≤ y) (h2 : maxY - y < vh) :
    regionOf vh maxY y = .b := by
  have ha : ¬ zoneOf vh y = 0 := by rw [zoneOf_eq_zero_iff hv]; omega
  have hb := (zoneOf_eq_zero_iff hv (maxY - y)).mpr h2
  simp [regionOf, ha, hb]

/-- Region B is zone 0 of the distance to the end `maxY - y`, for a position outside zone 0. -/
theorem regionOf_b_iff_zone {vh : Nat} {maxY : Int} (y : Int) :
    regionOf vh maxY y = .b ↔ zoneOf vh y ≠ 0 ∧ zoneIx vh ((maxY - y : Int) : Rat) = 0 := by
  show regionOf vh maxY y = .b ↔ zoneOf vh y ≠ 0 ∧ zoneOf vh (maxY - y) = 0
  unfold regionOf
  by_cases h : zoneOf vh y = 0
  · simp [h]
  · by_cases h2 : zoneOf vh (maxY - y) = 0
    · simp [h, h2]
    · by_cases h3 : 2 ≤ zoneOf vh y ∧ 2 ≤ zoneOf vh (maxY - y) <;> simp [h, h2, h3]

/-- Two zones from either end is the calm baseline. -/
theorem regionOf_calm {vh : Nat} (hv : 0 < vh) {maxY y : Int} (h1 : 2 * (vh : Int) ≤ y) (h2 : 2 * (vh : Int) ≤ maxY - y) :
    regionOf vh maxY y = .calm := by
  have e1 := zoneOf_ge_iff hv (n := 2) (by omega) y
  have e2 := zoneOf_ge_iff hv (n := 2) (by omega) (maxY - y)
  have a1 : 2 ≤ zoneOf vh y := e1.mpr (by simpa using h1)
  have a2 : 2 ≤ zoneOf vh (maxY - y) := e2.mpr (by simpa using h2)
  have ha : ¬ zoneOf vh y = 0 := by omega
  have hb : ¬ zoneOf vh (maxY - y) = 0 := by omega
  simp [regionOf, ha, hb, a1, a2]

/-- The zone next to either end is in no region. -/
theorem regionOf_other {vh : Nat} (hv : 0 < vh) {maxY y : Int} (h1 : vh ≤ y) (h2 : vh ≤ maxY - y)
    (h3 : y < 2 * (vh : Int) ∨ maxY - y < 2 * (vh : Int)) : regionOf vh maxY y = .other := by
  have e1 := zoneOf_ge_iff hv (n := 2) (by omega) y
  have ha : ¬ zoneOf vh y = 0 := by rw [zoneOf_eq_zero_iff hv]; omega
  have hb : ¬ zoneOf vh (maxY - y) = 0 := by rw [zoneOf_eq_zero_iff hv]; omega
  have e2 := zoneOf_ge_iff hv (n := 2) (by omega) (maxY - y)
  have hc : ¬ (2 ≤ zoneOf vh y ∧ 2 ≤ zoneOf vh (maxY - y)) := by
    intro ⟨c1, c2⟩
    have := e1.mp c1; have := e2.mp c2; simp at *; omega
  simp [regionOf, ha, hb, hc]

/-- The steps of region A at integral positions are the steps `Fw.Measure.WebKit.zoneSteps` puts in zone 0. -/
theorem zoneSteps_zero_iff {vh : Nat} {maxY : Int} (steps : List Fw.Measure.WebKit.Step)
    (s : Fw.Measure.WebKit.Step) (n : Int) (hy : s.y = (n : Rat)) :
    s ∈ zoneSteps vh steps 0 ↔ s ∈ steps ∧ regionOf vh maxY n = .a := by
  unfold zoneSteps
  rw [List.mem_filter, regionOf_a_iff_zone, ← hy]
  simp

/-! ## Per-step paint attribution -/

/-- One scroll step: its position, the part boxes at that position and the paint clips of the step. -/
structure PaintStep where
  y : Int
  boxes : List Box
  clips : List Rect

/-- The area each paint of a step puts on its part, one entry per paint. -/
def stepArea (s : PaintStep) : List (String × Int) := s.clips.map fun c => (ownerName s.boxes c, c.area)

/-- The paint count each paint of a step puts on its part, one entry per paint. -/
def stepCount (s : PaintStep) : List (String × Int) := s.clips.map fun c => (ownerName s.boxes c, 1)

/-- The ledger of a region over its steps, per part. -/
def regionLedger (vh : Nat) (maxY : Int) (steps : List PaintStep) (r : Region) (f : PaintStep → List (String × Int)) :
    List (String × Int) :=
  byKey ((steps.filter fun s => regionOf vh maxY s.y == r).flatMap f)

/-- The area ledger of a region puts every painted pixel on a part or on `(none)`. -/
theorem regionLedger_area_total (vh : Nat) (maxY : Int) (steps : List PaintStep) (r : Region) :
    total (regionLedger vh maxY steps r stepArea) =
      total ((steps.filter fun s => regionOf vh maxY s.y == r).flatMap stepArea) :=
  byKey_total _

/-- The paint area of one step: what its ledger adds up to is what its clips add up to. -/
theorem stepArea_total (s : PaintStep) : total (stepArea s) = (s.clips.map Rect.area).sum := by
  simp [stepArea, total, Function.comp_def]

/-! ## Filter layers -/

/-- A filter or backdrop-filter element of a step: its blur radius and its box, in viewport coordinates. -/
structure Filt where
  radius : Int
  r : Rect

/-- Visible filter layers of a step in a viewport: how many, their visible area, and area times radius. -/
def filterTotals (vp : Rect) (items : List Filt) : Int × Int × Int :=
  let vis := items.filter fun f => decide (0 < (f.r.inter vp).area)
  (vis.length, (vis.map fun f => (f.r.inter vp).area).sum, (vis.map fun f => (f.r.inter vp).area * f.radius).sum)

/-- Nothing visible means zero totals. -/
theorem filterTotals_nil (vp : Rect) : filterTotals vp [] = (0, 0, 0) := by
  simp [filterTotals]

/-! ## Counter ranking by a unit-free statistic -/

/-- The sum of column `j` over the rows. -/
def colSum (rows : List (List Int)) (j : Nat) : Int := (rows.map fun r => r.getD j 0).sum

/-- The rows of the steps in a region. -/
def windowOf (vh : Nat) (maxY : Int) (ys : List Int) (rows : List (List Int)) (r : Region) : List (List Int) :=
  ((ys.zip rows).filter fun p => regionOf vh maxY p.1 == r).map (·.2)

/-- Raw excess: region sum minus baseline sum, both scaled to the same step count (`nR * nC` steps). It carries the unit of
its column, so it cannot rank columns of different units (`excess_scale`, `excess_flips`); the probe ranks by `ratio`. -/
def excess (nR nC sR sC : Int) : Int := sR * nC - sC * nR

/-- A positive excess is a larger sum per step in the region than in the baseline (cross-multiplied). -/
theorem excess_pos_iff {nR nC sR sC : Int} : 0 < excess nR nC sR sC ↔ sC * nR < sR * nC := by
  unfold excess; omega

/-- Counting a column in other units (every value times `k`) multiplies its excess by `k`. -/
theorem excess_scale (nR nC sR sC k : Int) : excess nR nC (k * sR) (k * sC) = k * excess nR nC sR sC := by
  simp [excess, Int.mul_sub, Int.mul_assoc, Int.mul_left_comm]

/-- Why raw excess cannot rank across columns: the same two columns swap places when one is counted in other units. -/
theorem excess_flips : excess 1 1 30 10 > excess 1 1 20 10 ∧ excess 1 1 30 10 < excess 1 1 (10 * 20) (10 * 10) := by
  decide

/-- The window-to-baseline ratio of a counter, `(sR / nR) / (sC / nC)`: the mean per frame in the window over the mean per
frame in the baseline, where `nR` and `nC` are the frames of the two windows and `sR`, `sC` their column sums. -/
def ratio (nR nC sR sC : Int) : Rat := Rat.divInt (sR * nC) (sC * nR)

/-- **Unit-free.** Counting the column in other units (`k > 0` times every value) leaves its ratio unchanged. -/
theorem ratio_scale {nR nC sR sC k : Int} (hk : 0 < k) : ratio nR nC (k * sR) (k * sC) = ratio nR nC sR sC := by
  unfold ratio
  have hk0 : k ≠ 0 := by omega
  rw [Int.mul_assoc, Int.mul_assoc]
  exact Rat.divInt_mul_left hk0

/-- A counter is ranked when both windows have frames and the baseline sum is positive (its ratio is defined). -/
def rankable (nR nC sC : Int) : Bool := decide (0 < nR) && decide (0 < nC) && decide (0 < sC)

/-- Entries sorted by value, highest first, equal values in column order. -/
def rankDesc (items : List (String × Int)) : List (String × Int) :=
  items.mergeSort fun a b => decide (b.2 ≤ a.2)

/-- Ranking only reorders. -/
theorem rankDesc_perm (items : List (String × Int)) : (rankDesc items).Perm items :=
  List.mergeSort_perm _ _

/-- Ranking puts the highest value first. -/
theorem rankDesc_sorted (items : List (String × Int)) :
    (rankDesc items).Pairwise fun a b => b.2 ≤ a.2 := by
  have := List.pairwise_mergeSort (le := fun a b : String × Int => decide (b.2 ≤ a.2))
    (by intro a b c h1 h2; simp at *; omega) (by intro a b; simp; omega) items
  simpa [rankDesc] using this

/-- Entries with a ratio value, highest first, equal values in column order. -/
def rankDescQ (items : List (String × Rat)) : List (String × Rat) :=
  items.mergeSort fun a b => decide (b.2 ≤ a.2)

/-- Ranking only reorders. -/
theorem rankDescQ_perm (items : List (String × Rat)) : (rankDescQ items).Perm items :=
  List.mergeSort_perm _ _

/-- Ranking puts the highest ratio first. -/
theorem rankDescQ_sorted (items : List (String × Rat)) :
    (rankDescQ items).Pairwise fun a b => b.2 ≤ a.2 := by
  have := List.pairwise_mergeSort (le := fun a b : String × Rat => decide (b.2 ≤ a.2))
    (by intro a b c h1 h2; simp at *; exact Rat.le_trans h2 h1)
    (by intro a b; simp; exact Rat.le_total) items
  simpa [rankDescQ] using this

/-- The ratio of column `j` of a window against a baseline window, with `fR` and `fC` frames per row. -/
def colRatio (fR fC : Int) (wr wc : List (List Int)) (j : Nat) : Rat :=
  ratio (fR * wr.length) (fC * wc.length) (colSum wr j) (colSum wc j)

/-- Whether column `j` has a ratio. -/
def colRankable (fR fC : Int) (wr wc : List (List Int)) (j : Nat) : Bool :=
  rankable (fR * wr.length) (fC * wc.length) (colSum wc j)

/-- The counters (columns named `names`) of a window of step rows ranked by their ratio to a baseline window, highest first.
`fR` and `fC` are the frames per row of the two windows. A counter with no baseline (sum 0) is not ranked
(`unranked`). -/
def rankWindows (fR fC : Int) (wr wc : List (List Int)) (names : List String) : List (String × Rat) :=
  rankDescQ (((names.zip (List.range names.length)).filter fun p => colRankable fR fC wr wc p.2).map fun p =>
    (p.1, colRatio fR fC wr wc p.2))

/-- The counters with no ratio: the baseline has no frames or sums to 0. -/
def unranked (fR fC : Int) (wr wc : List (List Int)) (names : List String) : List String :=
  ((names.zip (List.range names.length)).filter fun p => !colRankable fR fC wr wc p.2).map (·.1)

/-- The counters of a region ranked by ratio to the calm baseline. -/
def rankRegion (vh : Nat) (maxY : Int) (ys : List Int) (rows : List (List Int)) (names : List String) (r : Region) :
    List (String × Rat) :=
  rankWindows 1 1 (windowOf vh maxY ys rows r) (windowOf vh maxY ys rows .calm) names

/-- A list splits into the entries a test keeps and the entries it drops. -/
theorem length_filter_add_not {α : Type} (p : α → Bool) :
    ∀ l : List α, (l.filter p).length + (l.filter fun x => !p x).length = l.length
  | [] => rfl
  | x :: xs => by
    have := length_filter_add_not p xs
    cases h : p x <;> simp [h] <;> omega

/-- Every named counter is ranked or unranked, once. -/
theorem rankWindows_length (fR fC : Int) (wr wc : List (List Int)) (names : List String) :
    (rankWindows fR fC wr wc names).length + (unranked fR fC wr wc names).length = names.length := by
  unfold rankWindows unranked
  rw [(rankDescQ_perm _).length_eq]
  simp only [List.length_map]
  have := length_filter_add_not (fun p : String × Nat => colRankable fR fC wr wc p.2) (names.zip (List.range names.length))
  simpa using this

/-! ### Rescaling one column's unit -/

/-- The rows with column `j` counted in other units: every value of that column times `k`. -/
def scaleCol (j : Nat) (k : Int) (rows : List (List Int)) : List (List Int) :=
  rows.map fun r => r.mapIdx fun i v => if i = j then k * v else v

private theorem getD_scaleRow (r : List Int) (j : Nat) (k : Int) (i : Nat) :
    (r.mapIdx fun i v => if i = j then k * v else v).getD i 0 = if i = j then k * r.getD i 0 else r.getD i 0 := by
  simp only [List.getD_eq_getElem?_getD, List.getElem?_mapIdx]
  cases h : r[i]? with
  | none => simp
  | some v => by_cases hij : i = j <;> simp [hij]

/-- Scaling column `j` scales its sum and changes no other. -/
theorem colSum_scaleCol (rows : List (List Int)) (j : Nat) (k : Int) (i : Nat) :
    colSum (scaleCol j k rows) i = if i = j then k * colSum rows i else colSum rows i := by
  unfold colSum scaleCol
  induction rows with
  | nil => simp
  | cons r rs ih =>
    by_cases h : i = j
    · simp only [List.map_cons, List.sum_cons, h, ite_true, getD_scaleRow] at ih ⊢
      rw [ih]; simp [Int.mul_add]
    · simp only [List.map_cons, List.sum_cons, h, ite_false, getD_scaleRow] at ih ⊢
      rw [ih]

/-- Scaling a column keeps the number of rows. -/
theorem scaleCol_length (j : Nat) (k : Int) (rows : List (List Int)) : (scaleCol j k rows).length = rows.length := by
  simp [scaleCol]

/-- Every column's ratio is the same after one column is counted in other units (`k > 0`). -/
theorem colRatio_scaleCol {fR fC : Int} {wr wc : List (List Int)} {k : Int} (hk : 0 < k) (j i : Nat) :
    colRatio fR fC (scaleCol j k wr) (scaleCol j k wc) i = colRatio fR fC wr wc i := by
  unfold colRatio
  rw [scaleCol_length, scaleCol_length, colSum_scaleCol, colSum_scaleCol]
  by_cases h : i = j
  · simp only [h, ite_true]; exact ratio_scale hk
  · simp only [h, ite_false]

/-- Which counters have a ratio is the same after one column is counted in other units (`k > 0`). -/
theorem colRankable_scaleCol {fR fC : Int} {wr wc : List (List Int)} {k : Int} (hk : 0 < k) (j i : Nat) :
    colRankable fR fC (scaleCol j k wr) (scaleCol j k wc) i = colRankable fR fC wr wc i := by
  unfold colRankable rankable
  rw [scaleCol_length, scaleCol_length, colSum_scaleCol]
  by_cases h : i = j
  · simp only [h, ite_true]
    have : (0 < k * colSum wc j) ↔ 0 < colSum wc j := by
      constructor
      · intro h2; exact Int.pos_of_mul_pos_right h2 hk
      · intro h2; exact Int.mul_pos hk h2
    simp [this]
  · simp only [h, ite_false]

/-- **The ranking is invariant to the unit of one column.** Counting any one counter in other units (`k > 0` times each of
its values, in the window and in the baseline) gives the same ranking, the same ratios and the same unranked counters. -/
theorem rankWindows_scaleCol {fR fC : Int} {wr wc : List (List Int)} {k : Int} (hk : 0 < k) (names : List String) (j : Nat) :
    rankWindows fR fC (scaleCol j k wr) (scaleCol j k wc) names = rankWindows fR fC wr wc names := by
  unfold rankWindows
  congr 1
  rw [List.filter_congr (fun p _ => by rw [colRankable_scaleCol hk]), List.map_congr_left]
  intro p _
  rw [colRatio_scaleCol hk]

/-- The same for the counters left unranked. -/
theorem unranked_scaleCol {fR fC : Int} {wr wc : List (List Int)} {k : Int} (hk : 0 < k) (names : List String) (j : Nat) :
    unranked fR fC (scaleCol j k wr) (scaleCol j k wc) names = unranked fR fC wr wc names := by
  unfold unranked
  rw [List.filter_congr (fun p _ => by rw [colRankable_scaleCol hk])]

/-! ## Arm differences: separated or overlapping per-pass ranges -/

/-- Every value of `lo` is below every value of `hi`: the two ranges (min to max) do not touch. -/
def sepBelow (lo hi : List Rat) : Bool := lo.all fun x => hi.all fun y => decide (x < y)

/-- What the per-pass values of the faithful arm say against the original arm. -/
inductive Verdict where
  | lower     -- every faithful pass is below every original pass
  | higher    -- every faithful pass is above every original pass
  | overlap   -- the ranges overlap, or an arm has no pass: no difference is shown
  | rareBaseline -- a baseline is too sparse: no ratio verdict is issued
  deriving DecidableEq, Repr

/-- The word written in the output. -/
def Verdict.name : Verdict → String
  | .lower => "lower" | .higher => "higher" | .overlap => "overlap" | .rareBaseline => "rareBaseline"

/-- The verdict from the per-pass values of the original arm and of the faithful arm. An arm difference is stated only when
the ranges are separated. -/
def verdict (orig faith : List Rat) : Verdict :=
  if orig.isEmpty || faith.isEmpty then .overlap
  else if sepBelow faith orig then .lower
  else if sepBelow orig faith then .higher
  else .overlap

/-- A range cannot be below another that is below it: two passes in each arm separate in at most one direction. -/
theorem sepBelow_antisymm {a b : List Rat} (ha : a ≠ []) (hb : b ≠ []) (h : sepBelow a b = true) :
    sepBelow b a = false := by
  cases hh : sepBelow b a
  · rfl
  · exfalso
    obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil a ha
    obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil b hb
    simp only [sepBelow, List.all_eq_true, decide_eq_true_eq] at h hh
    have h1 := h x hx y hy
    have h2 := hh y hy x hx
    exact Std.not_gt_of_lt h1 h2

/-- **Lower.** Every faithful pass below every original pass is the verdict `lower`. -/
theorem verdict_lower {o f : List Rat} (ho : o ≠ []) (hf : f ≠ []) (h : sepBelow f o = true) : verdict o f = .lower := by
  have e1 : o.isEmpty = false := by cases o <;> simp_all
  have e2 : f.isEmpty = false := by cases f <;> simp_all
  simp [verdict, e1, e2, h]

/-- **Higher.** Every faithful pass above every original pass is the verdict `higher`. -/
theorem verdict_higher {o f : List Rat} (ho : o ≠ []) (hf : f ≠ []) (h : sepBelow o f = true) : verdict o f = .higher := by
  have e1 : o.isEmpty = false := by cases o <;> simp_all
  have e2 : f.isEmpty = false := by cases f <;> simp_all
  have := sepBelow_antisymm ho hf h
  simp [verdict, e1, e2, this, h]

/-- **Overlap.** Ranges that are not separated give `overlap`: no difference is shown. -/
theorem verdict_overlap {o f : List Rat} (h1 : sepBelow f o = false) (h2 : sepBelow o f = false) : verdict o f = .overlap := by
  simp [verdict, h1, h2]

/-- **No pass, no claim.** An arm with no pass gives `overlap`. -/
theorem verdict_empty_left (f : List Rat) : verdict [] f = .overlap := by simp [verdict]

/-- **No pass, no claim.** An arm with no pass gives `overlap`. -/
theorem verdict_empty_right (o : List Rat) : verdict o [] = .overlap := by simp [verdict]

/-- Comparing an arm with itself never shows a difference. -/
theorem verdict_self {o : List Rat} (ho : o ≠ []) : verdict o o = .overlap := by
  have : sepBelow o o = false := by
    cases h : sepBelow o o
    · rfl
    · exfalso
      obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil o ho
      simp only [sepBelow, List.all_eq_true, decide_eq_true_eq] at h
      exact Rat.lt_irrefl (h x hx x hx)
  exact verdict_overlap this this

/-- Swapping the arms swaps `lower` and `higher`. -/
theorem verdict_swap_lower {o f : List Rat} (h : verdict o f = .lower) : verdict f o = .higher := by
  unfold verdict at h
  by_cases e1 : o.isEmpty || f.isEmpty
  · simp [e1] at h
  · have e2 : (f.isEmpty || o.isEmpty) = false := by simp_all [Bool.or_comm]
    have e1' : (o.isEmpty || f.isEmpty) = false := by simpa using e1
    simp only [e1', Bool.false_eq_true, ↓reduceIte] at h
    split at h
    · rename_i hs
      have ho : o ≠ [] := by intro h0; simp [h0] at e1'
      have hf : f ≠ [] := by intro h0; simp [h0] at e1'
      exact verdict_higher hf ho hs
    · split at h <;> simp at h

/-! ## Rare baselines: a ratio over a handful of events is not decided -/

/-- A baseline with fewer events than this in one pass is rare. -/
def rareMin : Int := 10

/-- The allowlist of columns the rare rule applies to: the lane's `COUNT_TYPES` and its three extra event counts. -/
def countColumns : List String :=
  ["RecalculateStyles", "Layout", "Paint", "Composite", "RenderingFrame", "FireAnimationFrame", "TimerFire",
   "ObserverCallback", "EventDispatch", "FunctionCall", "ScheduleStyleRecalculation", "InvalidateLayout",
   "RequestAnimationFrame", "TimerInstall", "TimerRemove"]

/-- The baseline of one arm is rare when one of its passes has fewer than `rareMin` events (`passSums`: events per pass). -/
def rareBase (passSums : List Int) : Bool := passSums.any fun s => decide (s < rareMin)

/-- The flag of one cell: a counted column whose per-pass baseline sums are rare. The same in every table. -/
def flagged (name : String) (passSums : List Int) : Bool := countColumns.contains name && rareBase passSums

/-- **Rare, by one pass.** A pass below `rareMin` makes the baseline rare. -/
theorem rareBase_of_lt {s : Int} {l : List Int} (hm : s ∈ l) (h : s < rareMin) : rareBase l = true := by
  simp only [rareBase, List.any_eq_true, decide_eq_true_eq]
  exact ⟨s, hm, h⟩

/-- **Not rare.** Every pass at or above `rareMin` is not rare. -/
theorem rareBase_false_of_ge {l : List Int} (h : ∀ s ∈ l, rareMin ≤ s) : rareBase l = false := by
  cases hb : rareBase l
  · rfl
  · exfalso
    simp only [rareBase, List.any_eq_true, decide_eq_true_eq] at hb
    obtain ⟨s, hs, hlt⟩ := hb
    exact Int.not_le.mpr hlt (h s hs)

/-- No pass, no rare baseline. -/
theorem rareBase_nil : rareBase [] = false := rfl

/-- **Allowlist.** A column outside `countColumns` is never flagged. -/
theorem flagged_of_not_mem {name : String} (h : name ∉ countColumns) (l : List Int) : flagged name l = false := by
  simp [flagged, h]

/-- **Counted and rare.** A counted column with a rare baseline is flagged. -/
theorem flagged_of_rare {name : String} (h : name ∈ countColumns) {l : List Int} (hr : rareBase l = true) :
    flagged name l = true := by
  simp [flagged, h, hr]

/-- **Counted and not rare.** A counted column with a baseline that is not rare is not flagged. -/
theorem flagged_of_not_rare {name : String} {l : List Int} (hr : rareBase l = false) : flagged name l = false := by
  simp [flagged, hr]

/-- Durations and the paint area are not in the allowlist. -/
theorem flagged_duration (l : List Int) :
    ["RecalculateStylesUs", "LayoutUs", "PaintUs", "CompositeUs", "FunctionCallUs", "paintArea"].all
      (fun n => flagged n l == false) = true := by
  simp [flagged, countColumns]

/-- The verdict on the ratio of one counter: none when either arm’s baseline is rare, else `verdict`. -/
def ratioVerdict (rareO rareF : Bool) (orig faith : List Rat) : Verdict :=
  if rareO || rareF then .rareBaseline else verdict orig faith

/-- **Original rare.** A rare original baseline gives `rareBaseline`, whatever the ranges. -/
theorem ratioVerdict_rare_orig (rareF : Bool) (o f : List Rat) : ratioVerdict true rareF o f = .rareBaseline := by
  simp [ratioVerdict]

/-- **Faithful rare.** A rare faithful baseline gives `rareBaseline`, whatever the ranges. -/
theorem ratioVerdict_rare_faith (rareO : Bool) (o f : List Rat) : ratioVerdict rareO true o f = .rareBaseline := by
  simp [ratioVerdict]

/-- **Both calm.** With no rare baseline the ratio verdict is `verdict`. -/
theorem ratioVerdict_calm (o f : List Rat) : ratioVerdict false false o f = verdict o f := by
  simp [ratioVerdict]

/-- The range verdict never says `rareBaseline`; only `ratioVerdict` does. -/
theorem verdict_ne_rareBaseline (o f : List Rat) : verdict o f ≠ .rareBaseline := by
  unfold verdict
  split
  · simp
  · split
    · simp
    · split <;> simp

/-- The verdict of each job from that job's own per-run values `(a, b)` of the two cells compared; no run is shared across jobs. -/
def jobVerdicts (jobs : List (List Rat × List Rat)) : List Verdict := jobs.map fun j => verdict j.1 j.2

/-- How many jobs said `lower`, `higher` and `overlap`. -/
def tally (vs : List Verdict) : Nat × Nat × Nat := (vs.count .lower, vs.count .higher, vs.count .overlap)

theorem jobVerdicts_length (jobs : List (List Rat × List Rat)) : (jobVerdicts jobs).length = jobs.length := by
  simp [jobVerdicts]

theorem jobVerdicts_get (jobs : List (List Rat × List Rat)) (i : Nat) :
    (jobVerdicts jobs)[i]? = (jobs[i]?).map fun j => verdict j.1 j.2 := by
  simp [jobVerdicts]

theorem jobVerdicts_congr {jobs jobs' : List (List Rat × List Rat)} {i : Nat} (h : jobs[i]? = jobs'[i]?) :
    (jobVerdicts jobs)[i]? = (jobVerdicts jobs')[i]? := by
  rw [jobVerdicts_get, jobVerdicts_get, h]

theorem verdict_lower_sep {o f : List Rat} (h : verdict o f = .lower) : sepBelow f o = true := by
  unfold verdict at h
  split at h
  · cases h
  · split at h
    · assumption
    · split at h <;> cases h

theorem verdict_higher_sep {o f : List Rat} (h : verdict o f = .higher) : sepBelow o f = true := by
  unfold verdict at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · assumption
      · cases h

theorem jobVerdicts_overlap {o f : List Rat} (h1 : sepBelow f o = false) (h2 : sepBelow o f = false) :
    jobVerdicts [(o, f)] = [.overlap] := by
  simp [jobVerdicts, verdict_overlap h1 h2]

theorem tally_total (jobs : List (List Rat × List Rat)) :
    (tally (jobVerdicts jobs)).1 + (tally (jobVerdicts jobs)).2.1 + (tally (jobVerdicts jobs)).2.2 = jobs.length := by
  induction jobs with
  | nil => simp [tally, jobVerdicts]
  | cons j js ih =>
    have hne := verdict_ne_rareBaseline j.1 j.2
    simp only [tally, jobVerdicts, List.map_cons, List.count_cons, List.length_cons] at ih ⊢
    cases hv : verdict j.1 j.2 <;> simp_all <;> omega

theorem pooled_lower {o1 f1 o2 f2 : List Rat} (h1 : o1 ≠ []) (h2 : f1 ≠ []) (h3 : o2 ≠ []) (h4 : f2 ≠ [])
    (h : verdict (o1 ++ o2) (f1 ++ f2) = .lower) : verdict o1 f1 = .lower ∧ verdict o2 f2 = .lower := by
  have hs := verdict_lower_sep h
  simp only [sepBelow, List.all_append, Bool.and_eq_true] at hs
  exact ⟨verdict_lower h1 h2 (by simp only [sepBelow]; simp_all), verdict_lower h3 h4 (by simp only [sepBelow]; simp_all)⟩

theorem pooling_hides :
    jobVerdicts [([10], [5]), ([3], [1])] = [.lower, .lower] ∧ verdict ([10] ++ [3]) ([5] ++ [1]) = .overlap := by
  decide

theorem sorted_head_max {α : Type} (key : α → Int) {l : List α} {h : α} {t : List α}
    (e : l = h :: t) (hs : l.Pairwise fun a b => key b ≤ key a) : ∀ p ∈ l, key p ≤ key h := by
  subst e
  intro p hp
  rcases List.mem_cons.mp hp with rfl | hp
  · exact Int.le_refl _
  · exact (List.pairwise_cons.mp hs).1 p hp

/-- The head of a ranked list has the largest value. -/
theorem rankDesc_head_max {l t : List (String × Int)} {h : String × Int} (e : rankDesc l = h :: t) :
    ∀ p ∈ l, p.2 ≤ h.2 := by
  intro p hp
  have hp' : p ∈ rankDesc l := (rankDesc_perm l).mem_iff.mpr hp
  exact sorted_head_max (fun a : String × Int => a.2) e (rankDesc_sorted l) p hp'

/-- The part that owns the most paint area at a step (`(none)` for a step with no paint, or paint with no part). -/
def topPart (s : PaintStep) : String :=
  match rankDesc (byKey (stepArea s)) with
  | [] => "(none)"
  | h :: _ => h.1

/-- A step with no paint has no owning part. -/
theorem topPart_nil (y : Int) (b : List Box) : topPart ⟨y, b, []⟩ = "(none)" := by
  simp [topPart, stepArea, byKey, rankDesc]

/-- The steps with the largest key: `(y, key)` pairs, highest key first (equal keys in input order), at most `k`. -/
def topK (k : Nat) (items : List (Int × Int)) : List (Int × Int) :=
  (items.mergeSort fun a b => decide (b.2 ≤ a.2)).take k

/-- At most `k` steps are listed. -/
theorem topK_length_le (k : Nat) (items : List (Int × Int)) : (topK k items).length ≤ k := by
  exact List.length_take_le k _

/-- Every listed step is a step of the input. -/
theorem topK_mem {k : Nat} {items : List (Int × Int)} {p : Int × Int} (h : p ∈ topK k items) : p ∈ items := by
  unfold topK at h
  exact (List.mergeSort_perm _ _).mem_iff.mp (List.mem_of_mem_take h)

/-- The list is sorted by key, highest first. -/
theorem topK_sorted (k : Nat) (items : List (Int × Int)) : (topK k items).Pairwise fun a b => b.2 ≤ a.2 := by
  have := List.pairwise_mergeSort (le := fun a b : Int × Int => decide (b.2 ≤ a.2))
    (by intro a b c h1 h2; simp at *; omega) (by intro a b; simp; omega) items
  simp only [decide_eq_true_eq] at this
  exact this.sublist (List.take_sublist _ _)

/-- The first listed step has the largest key of all steps. -/
theorem topK_head_max {k : Nat} {items : List (Int × Int)} {h : Int × Int} {t : List (Int × Int)}
    (e : topK (k + 1) items = h :: t) : ∀ p ∈ items, p.2 ≤ h.2 := by
  intro p hp
  have hs := List.pairwise_mergeSort (le := fun a b : Int × Int => decide (b.2 ≤ a.2))
    (by intro a b c h1 h2; simp at *; omega) (by intro a b; simp; omega) items
  simp only [decide_eq_true_eq] at hs
  generalize hm : items.mergeSort (fun a b : Int × Int => decide (b.2 ≤ a.2)) = m at hs
  have hperm : m.Perm items := hm ▸ List.mergeSort_perm _ _
  unfold topK at e
  rw [hm] at e
  cases m with
  | nil => simp at e
  | cons m0 ms =>
    simp only [List.take_succ_cons, List.cons.injEq] at e
    obtain ⟨rfl, _⟩ := e
    exact sorted_head_max (fun a : Int × Int => a.2) rfl hs p (hperm.mem_iff.mpr hp)

/-! ## The golden -/

private def rj (r : Rect) : Json := toJson [r.x0, r.y0, r.x1, r.y1]
private def bj (b : Box) : Json := Json.mkObj [("name", b.name), ("rect", rj b.r)]
private def lj (l : List (String × Int)) : Json := Json.arr (l.map fun p => Json.arr #[p.1, toJson p.2]).toArray
private def qj (q : Rat) : Json := toJson [q.num, (q.den : Int)]
private def qlj (l : List (String × Rat)) : Json := Json.arr (l.map fun p => Json.arr #[p.1, qj p.2]).toArray
private def R (a b c d : Int) : Rect := ⟨a, b, c, d⟩
private def B (n : String) (a b c d : Int) : Box := ⟨n, R a b c d⟩
private def Q (n d : Int) : Rat := Rat.divInt n d

private def boxesA : List Box :=
  [B "hero" 0 0 1720 3100, B "hero-deck" 100 400 1620 2000, B "hero-accent" 200 400 900 600, B "nav" 0 0 1720 240]

private def ownerCases : List (List Box × Rect) :=
  [(boxesA, R 220 410 880 590), (boxesA, R 120 420 1600 1900), (boxesA, R 0 0 1720 3100), (boxesA, R 0 3200 100 3300),
   (boxesA, R 10 10 10 50), (boxesA, R 0 200 1720 600), ([], R 0 0 5 5),
   ([B "a" 0 0 100 100, B "b" 0 0 100 100], R 10 10 20 20)]

/-- (viewport height, last scroll position, scroll position). -/
private def regionCases : List (Nat × Int × Int) :=
  [(775, 9000, -5), (775, 9000, 0), (775, 9000, 774), (775, 9000, 775), (775, 9000, 1549), (775, 9000, 1550),
   (775, 9000, 1551), (775, 9000, 7449), (775, 9000, 7450), (775, 9000, 7451), (775, 9000, 8225), (775, 9000, 8226),
   (775, 9000, 9000), (775, 1000, 800), (775, 1400, 700), (775, 775, 775), (100, 450, 350), (100, 450, 250)]

private def stepsA : List PaintStep :=
  [⟨0, boxesA, [R 220 410 880 590, R 0 0 1720 3100]⟩, ⟨50, boxesA, [R 220 410 880 590, R 10 10 10 50]⟩,
   ⟨775, boxesA, [R 120 420 1600 1900]⟩, ⟨800, boxesA, [R 0 3200 100 3300]⟩, ⟨4000, boxesA, [R 0 0 1720 240]⟩,
   ⟨8500, boxesA, []⟩]

private def rankYs : List Int := [0, 100, 800, 2500, 3000, 4000, 8500, 9000]
private def rankRows : List (List Int) :=
  [[3, 9, 1, 0], [3, 7, 1, 0], [1, 1, 1, 0], [1, 2, 1, 0], [1, 2, 1, 0], [1, 3, 1, 0], [2, 5, 1, 0], [4, 5, 1, 7]]
private def rankNames : List String := ["Layout", "Paint", "Composite", "Idle"]

private def filterCases : List (Rect × List Filt) :=
  [(R 0 0 1290 2325, []), (R 0 0 1290 2325, [⟨24, R 0 0 1290 400⟩, ⟨8, R 0 2000 1290 3000⟩, ⟨30, R 0 3000 100 3100⟩]),
   (R 0 0 1290 2325, [⟨0, R (-100) (-100) 100 100⟩])]

/-- (frames per window row, frames per baseline row, window rows, baseline rows). -/
private def windowCases : List (Int × Int × List (List Int) × List (List Int)) :=
  [(1, 1, [[5, 9, 2, 0], [4, 9, 2, 0], [3, 9, 2, 0]], [[1, 1, 1, 0], [1, 2, 1, 0]]),
   (1, 2, [[5, 9, 2, 3], [4, 9, 2, 3], [3, 9, 2, 3]], [[1, 1, 1, 1], [1, 2, 1, 1]]),
   (1, 1, [[5, 9, 2, 0]], []),
   (2, 1, [[100, 4000, 2, 5]], [[10, 400, 1, 5], [10, 400, 1, 5]])]

private def verdictCases : List (List Rat × List Rat) :=
  [([Q 3 2, Q 5 3, Q 7 4], [Q 1 1, Q 5 4, Q 4 3]), ([Q 1 1, Q 5 4], [Q 3 2, Q 5 3]), ([Q 1 1, Q 3 2], [Q 5 4, Q 5 3]),
   ([Q 3 2], [Q 3 2]), ([], [Q 1 1]), ([Q 1 1], []), ([Q 1 1, Q 2 1], [Q 2 1, Q 3 1])]

/-- (table, counter, original per-pass baseline sums, faithful per-pass baseline sums, original ratios, faithful ratios). -/
private def rareCases : List (String × String × List Int × List Int × List Rat × List Rat) :=
  [("scroll", "TimerInstall", [40, 52], [3, 9], [Q 1 1, Q 3 2], [Q 4 1, Q 6 1]),
   ("morph", "TimerInstall", [40, 52], [3, 9], [Q 1 1, Q 3 2], [Q 4 1, Q 6 1]),
   ("scroll", "Layout", [10, 10], [10, 25], [Q 1 1, Q 3 2], [Q 4 1, Q 6 1]),
   ("scroll", "Layout", [9, 10], [10, 25], [Q 1 1, Q 3 2], [Q 4 1, Q 6 1]),
   ("morph", "Layout", [30, 40], [30, 40], [Q 2 1, Q 3 1], [Q 1 1, Q 5 4]),
   ("idle", "Paint", [36, 35], [38, 36], [Q 1 1, Q 3 2], [Q 4 1, Q 6 1]),
   ("idle", "Paint", [4, 12], [36, 38], [Q 1 1, Q 3 2], [Q 4 1, Q 6 1]),
   ("scroll", "PaintUs", [0, 1], [2, 3], [Q 1 1, Q 3 2], [Q 4 1, Q 6 1]),
   ("scroll", "paintArea", [0], [0], [Q 1 1], [Q 1 1]),
   ("scroll", "Layout", [], [], [], [])]

private def jobCases : List (List (List Rat × List Rat)) :=
  [[([Q 5 1, Q 6 1], [Q 1 1, Q 2 1]), ([Q 5 1, Q 7 1], [Q 1 1, Q 3 1]), ([Q 4 1], [Q 1 1])],
   [([Q 1 1, Q 2 1], [Q 5 1, Q 6 1]), ([Q 1 1, Q 4 1], [Q 3 1, Q 6 1]), ([Q 3 2], [Q 3 2])],
   [([Q 10 1], [Q 5 1]), ([Q 3 1], [Q 1 1])],
   [([], [Q 1 1]), ([Q 1 1], [])],
   []]

private def topCases : List (Nat × List (Int × Int)) :=
  [(3, [(0, 5), (50, 9), (100, 9), (150, 1), (200, 7)]), (2, [(10, 4)]), (0, [(10, 4)]), (4, [])]

private def goldenLines (_ : Unit) : List String :=
  (ownerCases.map fun (bs, c) =>
    (Json.mkObj [("kind", "owner"), ("boxes", Json.arr (bs.map bj).toArray), ("clip", rj c),
      ("owner", match owner bs c with | some n => toJson n | none => Json.null)]).compress) ++
  (regionCases.map fun (vh, m, y) =>
    (Json.mkObj [("kind", "region"), ("vh", vh), ("maxY", m), ("y", y), ("region", (regionOf vh m y).name),
      ("zone", zoneOf vh y)]).compress) ++
  [(Json.mkObj [("kind", "ledger"),
    ("steps", Json.arr (stepsA.map fun s => Json.mkObj [("y", s.y), ("boxes", Json.arr (s.boxes.map bj).toArray),
      ("clips", Json.arr (s.clips.map rj).toArray), ("topPart", topPart s)]).toArray),
    ("vh", (775 : Int)), ("maxY", (9000 : Int)),
    ("regions", Json.arr (([Region.a, .b, .calm, .other].map fun r =>
      Json.mkObj [("region", r.name), ("area", lj (regionLedger 775 9000 stepsA r stepArea)),
        ("count", lj (regionLedger 775 9000 stepsA r stepCount)),
        ("areaRollup", lj (rollup (regionLedger 775 9000 stepsA r stepArea)))]).toArray))]).compress] ++
  [Region.a, .b, .calm, .other].map (fun r =>
    (Json.mkObj [("kind", "rank"), ("region", r.name), ("vh", (775 : Int)), ("maxY", (9000 : Int)), ("ys", toJson rankYs),
      ("rows", toJson rankRows), ("names", toJson rankNames),
      ("nRegion", (windowOf 775 9000 rankYs rankRows r).length), ("nCalm", (windowOf 775 9000 rankYs rankRows .calm).length),
      ("ranked", qlj (rankRegion 775 9000 rankYs rankRows rankNames r)),
      ("unranked", toJson (unranked 1 1 (windowOf 775 9000 rankYs rankRows r) (windowOf 775 9000 rankYs rankRows .calm) rankNames))]).compress) ++
  (windowCases.map fun (fR, fC, wr, wc) =>
    (Json.mkObj [("kind", "rankWindows"), ("names", toJson rankNames), ("fR", fR), ("fC", fC), ("window", toJson wr),
      ("baseline", toJson wc), ("ranked", qlj (rankWindows fR fC wr wc rankNames)),
      ("unranked", toJson (unranked fR fC wr wc rankNames))]).compress) ++
  -- the same window and baseline with column 1 counted in other units: the output is the same
  [(Json.mkObj [("kind", "rankScaled"), ("names", toJson rankNames), ("fR", (1 : Int)), ("fC", (1 : Int)), ("col", (1 : Nat)),
      ("k", (1000 : Int)), ("window", toJson (scaleCol 1 1000 [[5, 9, 2, 0], [4, 9, 2, 0], [3, 9, 2, 0]])),
      ("baseline", toJson (scaleCol 1 1000 [[1, 1, 1, 0], [1, 2, 1, 0]])),
      ("ranked", qlj (rankWindows 1 1 (scaleCol 1 1000 [[5, 9, 2, 0], [4, 9, 2, 0], [3, 9, 2, 0]])
        (scaleCol 1 1000 [[1, 1, 1, 0], [1, 2, 1, 0]]) rankNames))]).compress] ++
  (verdictCases.map fun (o, f) =>
    (Json.mkObj [("kind", "verdict"), ("orig", Json.arr (o.map qj).toArray), ("faith", Json.arr (f.map qj).toArray),
      ("verdict", (verdict o f).name)]).compress) ++
  (jobCases.map fun js =>
    let vs := jobVerdicts js
    let (lo, hi, ov) := tally vs
    (Json.mkObj [("kind", "jobVerdicts"),
      ("jobs", Json.arr (js.map fun (o, f) => Json.mkObj [("a", Json.arr (o.map qj).toArray), ("b", Json.arr (f.map qj).toArray)]).toArray),
      ("verdicts", toJson (vs.map Verdict.name)), ("lower", lo), ("higher", hi), ("overlap", ov)]).compress) ++
  [(Json.mkObj [("kind", "rareConst"), ("rareMin", rareMin), ("countColumns", toJson countColumns)]).compress] ++
  (rareCases.map fun (ctx, name, so, sf, ro, rf) =>
    (Json.mkObj [("kind", "rareCell"), ("ctx", ctx), ("name", name), ("origSums", toJson so), ("faithSums", toJson sf),
      ("orig", Json.arr (ro.map qj).toArray), ("faith", Json.arr (rf.map qj).toArray),
      ("rareO", flagged name so), ("rareF", flagged name sf),
      ("verdict", (ratioVerdict (flagged name so) (flagged name sf) ro rf).name)]).compress) ++
  (topCases.map fun (k, items) =>
    (Json.mkObj [("kind", "topK"), ("k", k), ("items", toJson (items.map fun p => [p.1, p.2])),
      ("top", toJson ((topK k items).map fun p => [p.1, p.2]))]).compress) ++
  (filterCases.map fun (vp, items) =>
    let (n, a, ar) := filterTotals vp items
    (Json.mkObj [("kind", "filter"), ("viewport", rj vp),
      ("items", Json.arr (items.map fun f => Json.mkObj [("radius", f.radius), ("rect", rj f.r)]).toArray),
      ("count", n), ("area", a), ("areaRadius", ar)]).compress) ++
  Fw.Measure.WebKitLagPhase.phaseGoldenLines ()

/-- The bytes of `packages/contracts/golden/measure/webkit-lag.jsonl`. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"webkit-lag golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"webkit-lag golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Measure.WebKitLag
