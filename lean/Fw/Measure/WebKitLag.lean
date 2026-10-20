import Lean.Data.Json
import Fw.Measure.WebKit
/-!
# Where the Simulator lag comes from (`packages/measure-webkit/src/lag/reduce.mjs`)
The pure reductions of the webkit-lag-probe: scroll regions, paint attribution to parts, counter excess and its ranking.
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

/-! ## Scroll regions -/

/-- The scroll regions of the probe. -/
inductive Region where
  | a | b | calm | other
  deriving DecidableEq, Repr

/-- The region name written in the output. -/
def Region.name : Region → String
  | .a => "A" | .b => "B" | .calm => "calm" | .other => "other"

/-- The region of a scroll position `y` on a page of viewport height `vh` and last scroll position `maxY`. -/
def regionOf (vh maxY y : Int) : Region :=
  if y ≤ vh then .a
  else if maxY - vh ≤ y then .b
  else if 2 * vh < y ∧ y < maxY - 2 * vh then .calm
  else .other

/-- The first viewport of the page is region A (the hero cards leaving). -/
theorem regionOf_a {vh maxY y : Int} (h : y ≤ vh) : regionOf vh maxY y = .a := by
  simp [regionOf, h]

/-- The last viewport of the page is region B (the end of the page), unless it is also region A. -/
theorem regionOf_b {vh maxY y : Int} (h1 : vh < y) (h2 : maxY - vh ≤ y) : regionOf vh maxY y = .b := by
  simp [regionOf, Int.not_le.mpr h1, h2]

/-- Between two viewports from either end is the calm baseline. -/
theorem regionOf_calm {vh maxY y : Int} (h1 : 2 * vh < y) (h2 : y < maxY - 2 * vh) (h3 : y < maxY - vh) (h4 : vh < y) :
    regionOf vh maxY y = .calm := by
  have : ¬ y ≤ vh := by omega
  have h5 : ¬ maxY - vh ≤ y := by omega
  simp [regionOf, this, h5, h1, h2]

/-- The two gaps between a region and the baseline are in no region. -/
theorem regionOf_other {vh maxY y : Int} (h1 : vh < y) (h2 : y < maxY - vh) (h3 : y ≤ 2 * vh ∨ maxY - 2 * vh ≤ y) :
    regionOf vh maxY y = .other := by
  have : ¬ y ≤ vh := by omega
  have h5 : ¬ maxY - vh ≤ y := by omega
  have h6 : ¬ (2 * vh < y ∧ y < maxY - 2 * vh) := by omega
  simp [regionOf, this, h5, h6]

/-! ## Per-step paint attribution -/

/-- One scroll step: its position, the part boxes at that position and the paint clips of the step. -/
structure Step where
  y : Int
  boxes : List Box
  clips : List Rect

/-- The area each paint of a step puts on its part, one entry per paint. -/
def stepArea (s : Step) : List (String × Int) := s.clips.map fun c => (ownerName s.boxes c, c.area)

/-- The paint count each paint of a step puts on its part, one entry per paint. -/
def stepCount (s : Step) : List (String × Int) := s.clips.map fun c => (ownerName s.boxes c, 1)

/-- The ledger of a region over its steps, per part. -/
def regionLedger (vh maxY : Int) (steps : List Step) (r : Region) (f : Step → List (String × Int)) :
    List (String × Int) :=
  byKey ((steps.filter fun s => regionOf vh maxY s.y == r).flatMap f)

/-- The area ledger of a region puts every painted pixel on a part or on `(none)`. -/
theorem regionLedger_area_total (vh maxY : Int) (steps : List Step) (r : Region) :
    total (regionLedger vh maxY steps r stepArea) =
      total ((steps.filter fun s => regionOf vh maxY s.y == r).flatMap stepArea) :=
  byKey_total _

/-- The paint area of one step: what its ledger adds up to is what its clips add up to. -/
theorem stepArea_total (s : Step) : total (stepArea s) = (s.clips.map Rect.area).sum := by
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

/-! ## Counter excess and its ranking -/

/-- The sum of column `j` over the rows. -/
def colSum (rows : List (List Int)) (j : Nat) : Int := (rows.map fun r => r.getD j 0).sum

/-- The rows of the steps in a region. -/
def windowOf (vh maxY : Int) (ys : List Int) (rows : List (List Int)) (r : Region) : List (List Int) :=
  ((ys.zip rows).filter fun p => regionOf vh maxY p.1 == r).map (·.2)

/-- Region sum minus calm sum, both scaled to the same step count (`nR * nC` steps). -/
def excess (nR nC sR sC : Int) : Int := sR * nC - sC * nR

/-- A positive excess is a larger sum per step in the region than in the baseline (cross-multiplied). -/
theorem excess_pos_iff {nR nC sR sC : Int} : 0 < excess nR nC sR sC ↔ sC * nR < sR * nC := by
  unfold excess; omega

/-- Entries sorted by excess, highest first, equal excess in column order. -/
def rankDesc (items : List (String × Int)) : List (String × Int) :=
  items.mergeSort fun a b => decide (b.2 ≤ a.2)

/-- Ranking only reorders. -/
theorem rankDesc_perm (items : List (String × Int)) : (rankDesc items).Perm items :=
  List.mergeSort_perm _ _

/-- Ranking puts the highest excess first. -/
theorem rankDesc_sorted (items : List (String × Int)) :
    (rankDesc items).Pairwise fun a b => b.2 ≤ a.2 := by
  have := List.pairwise_mergeSort (le := fun a b : String × Int => decide (b.2 ≤ a.2))
    (by intro a b c h1 h2; simp at *; omega) (by intro a b; simp; omega) items
  simpa [rankDesc] using this

/-- The counters of a region ranked by excess over the calm baseline (columns named `names`). -/
def rankRegion (vh maxY : Int) (ys : List Int) (rows : List (List Int)) (names : List String) (r : Region) :
    List (String × Int) :=
  let wr := windowOf vh maxY ys rows r
  let wc := windowOf vh maxY ys rows .calm
  rankDesc ((names.zip (List.range names.length)).map fun p =>
    (p.1, excess wr.length wc.length (colSum wr p.2) (colSum wc p.2)))

/-- A region ranking holds every named counter once. -/
theorem rankRegion_length (vh maxY : Int) (ys : List Int) (rows : List (List Int)) (names : List String) (r : Region) :
    (rankRegion vh maxY ys rows names r).length = names.length := by
  unfold rankRegion
  rw [(rankDesc_perm _).length_eq]
  simp

/-! ## The golden -/

private def rj (r : Rect) : Json := toJson [r.x0, r.y0, r.x1, r.y1]
private def bj (b : Box) : Json := Json.mkObj [("name", b.name), ("rect", rj b.r)]
private def lj (l : List (String × Int)) : Json := Json.arr (l.map fun p => Json.arr #[p.1, toJson p.2]).toArray
private def R (a b c d : Int) : Rect := ⟨a, b, c, d⟩
private def B (n : String) (a b c d : Int) : Box := ⟨n, R a b c d⟩

private def boxesA : List Box :=
  [B "hero" 0 0 1720 3100, B "hero-deck" 100 400 1620 2000, B "hero-accent" 200 400 900 600, B "nav" 0 0 1720 240]

private def ownerCases : List (List Box × Rect) :=
  [(boxesA, R 220 410 880 590), (boxesA, R 120 420 1600 1900), (boxesA, R 0 0 1720 3100), (boxesA, R 0 3200 100 3300),
   (boxesA, R 10 10 10 50), (boxesA, R 0 200 1720 600), ([], R 0 0 5 5),
   ([B "a" 0 0 100 100, B "b" 0 0 100 100], R 10 10 20 20)]

private def regionCases : List (Int × Int × Int) :=
  [(775, 9000, 0), (775, 9000, 775), (775, 9000, 776), (775, 9000, 1550), (775, 9000, 1551), (775, 9000, 7449),
   (775, 9000, 7450), (775, 9000, 8224), (775, 9000, 8225), (775, 9000, 9000), (775, 1000, 800), (775, 1400, 700)]

private def stepsA : List Step :=
  [⟨0, boxesA, [R 220 410 880 590, R 0 0 1720 3100]⟩, ⟨50, boxesA, [R 220 410 880 590, R 10 10 10 50]⟩,
   ⟨775, boxesA, [R 120 420 1600 1900]⟩, ⟨800, boxesA, [R 0 3200 100 3300]⟩, ⟨4000, boxesA, [R 0 0 1720 240]⟩]

private def rankYs : List Int := [0, 100, 800, 2500, 3000, 4000, 8500, 9000]
private def rankRows : List (List Int) :=
  [[3, 9, 1], [3, 7, 1], [1, 1, 1], [1, 2, 1], [1, 2, 1], [1, 3, 1], [2, 5, 1], [4, 5, 1]]

private def filterCases : List (Rect × List Filt) :=
  [(R 0 0 1290 2325, []), (R 0 0 1290 2325, [⟨24, R 0 0 1290 400⟩, ⟨8, R 0 2000 1290 3000⟩, ⟨30, R 0 3000 100 3100⟩]),
   (R 0 0 1290 2325, [⟨0, R (-100) (-100) 100 100⟩])]

private def goldenLines : List String :=
  (ownerCases.map fun (bs, c) =>
    (Json.mkObj [("kind", "owner"), ("boxes", Json.arr (bs.map bj).toArray), ("clip", rj c),
      ("owner", match owner bs c with | some n => toJson n | none => Json.null)]).compress) ++
  (regionCases.map fun (vh, m, y) =>
    (Json.mkObj [("kind", "region"), ("vh", vh), ("maxY", m), ("y", y), ("region", (regionOf vh m y).name)]).compress) ++
  [(Json.mkObj [("kind", "ledger"),
    ("steps", Json.arr (stepsA.map fun s => Json.mkObj [("y", s.y), ("boxes", Json.arr (s.boxes.map bj).toArray),
      ("clips", Json.arr (s.clips.map rj).toArray)]).toArray),
    ("vh", (775 : Int)), ("maxY", (9000 : Int)),
    ("regions", Json.arr (([Region.a, .b, .calm, .other].map fun r =>
      Json.mkObj [("region", r.name), ("area", lj (regionLedger 775 9000 stepsA r stepArea)),
        ("count", lj (regionLedger 775 9000 stepsA r stepCount)),
        ("areaRollup", lj (rollup (regionLedger 775 9000 stepsA r stepArea)))]).toArray))]).compress] ++
  [Region.a, .b, .calm, .other].map (fun r =>
    (Json.mkObj [("kind", "rank"), ("region", r.name), ("vh", (775 : Int)), ("maxY", (9000 : Int)), ("ys", toJson rankYs),
      ("rows", toJson rankRows), ("names", toJson ["Layout", "Paint", "Composite"]),
      ("nRegion", (windowOf 775 9000 rankYs rankRows r).length), ("nCalm", (windowOf 775 9000 rankYs rankRows .calm).length),
      ("ranked", lj (rankRegion 775 9000 rankYs rankRows ["Layout", "Paint", "Composite"] r))]).compress) ++
  (filterCases.map fun (vp, items) =>
    let (n, a, ar) := filterTotals vp items
    (Json.mkObj [("kind", "filter"), ("viewport", rj vp),
      ("items", Json.arr (items.map fun f => Json.mkObj [("radius", f.radius), ("rect", rj f.r)]).toArray),
      ("count", n), ("area", a), ("areaRadius", ar)]).compress)

/-- The bytes of `packages/contracts/golden/measure/webkit-lag.jsonl`. -/
def goldenText : String := String.intercalate "\n" goldenLines ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"webkit-lag golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"webkit-lag golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Measure.WebKitLag
