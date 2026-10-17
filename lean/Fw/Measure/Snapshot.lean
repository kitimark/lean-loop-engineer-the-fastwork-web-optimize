import Fw.Measure.Zones
/-!
# Layer census and raster invalidation of one compositor snapshot (`trace.mjs` `snapshotCounts`)

One `LayerTreeHostImpl:snapshot` trace event per BeginImplFrame carries the active layer tree and
its tiles (`args.snapshot`). The Chromium lane counts, per snapshot:

| name | value |
|---|---|
| `census.snapshots` | 1 |
| `census.layers` | layers of the active tree |
| `census.drawingLayers` | layers with `draws_content` |
| `census.drawingAreaPx` | Σ width · height of the drawing layers' bounds |
| `census.tilings` | Σ number of tilings per layer |
| `census.tiles` | `tile_manager_basic_state.tile_count` (0 when absent) |
| `census.activeTiles` | active tiles |
| `census.solidTiles` | active tiles drawn as a solid colour |
| `census.activeTileAreaPx` | Σ width · height of the tiles' `content_rect` |
| `raster.invalidatedLayers` | layers with a non-empty `invalidation` |
| `raster.invalidationRects` | Σ ⌊\|invalidation\| / 4⌋ (`cc::Region::AsValueInto`: x, y, width, height per rect) |
| `raster.invalidationAreaPx` | Σ width · height of those rects |

The container computes this in JS (it has no Lean); `packages/measure-chromium/test/fwcore.test.mjs`
checks the JS against the golden vectors generated from this file (op `measure.snapshotCounts`).
An incomplete trailing quad of `invalidation` still marks the layer invalidated but adds no rect.
-/
namespace Fw.Measure.Snapshot
open Fw.Measure

/-- The fields of one layer that the census reads.

$$\mathrm{Layer} = \mathbb{B} \times \mathbb{Z}^{2} \times \mathbb{N} \times \mathbb{Z}^{*}\quad(\text{draws}, w, h, \text{tilings}, \text{invalidation})$$
-/
structure Layer where
  draws : Bool
  width : Int
  height : Int
  tilings : Nat
  invalidation : List Int
deriving Repr, DecidableEq

/-- The fields of one active tile that the census reads: solid colour, content width and height.

$$\mathrm{Tile} = \mathbb{B} \times \mathbb{Z}^{2}$$
-/
structure Tile where
  solid : Bool
  width : Int
  height : Int
deriving Repr, DecidableEq

/-- A snapshot: tile count of the tile manager, active layers, active tiles.

$$\mathrm{Snap} = \mathbb{Z} \times \mathrm{Layer}^{*} \times \mathrm{Tile}^{*}$$
-/
structure Snap where
  tileCount : Int
  layers : List Layer
  tiles : List Tile
deriving Repr, DecidableEq

/-- The (width, height) of each complete quad `x, y, w, h` of a flattened rect list; a trailing
incomplete quad is dropped.

$$\operatorname{rects}([x, y, w, h] \mathbin{+\!\!+} L) = (w, h) :: \operatorname{rects}(L),\qquad \operatorname{rects}(L) = [\,] \text{ for } |L| < 4$$
-/
def rects : List Int → List (Int × Int)
  | _ :: _ :: w :: h :: rest => (w, h) :: rects rest
  | _ => []

/-- The summed area of the complete rects.

$$\operatorname{area}(L) = \sum_{(w, h) \in \operatorname{rects}(L)} w \cdot h$$
-/
def rectArea (l : List Int) : Int := sumBy (fun p => p.1 * p.2) (rects l)

/-- The sum of a list of naturals.

$$\operatorname{natSum}(L) = \sum_{x \in L} x$$
-/
def natSum (l : List Nat) : Nat := l.foldr (· + ·) 0

/-- The census of one snapshot.

$$\begin{aligned} \operatorname{census}(s) = \big(&1,\ |L|,\ |\{l \in L \mid l.\mathrm{draws}\}|,\ \textstyle\sum_{l \in L,\ l.\mathrm{draws}} l.w \cdot l.h,\ \sum_{l \in L} l.\mathrm{tilings},\ s.\mathrm{tileCount},\ |T|,\ |\{t \in T \mid t.\mathrm{solid}\}|,\ \sum_{t \in T} t.w \cdot t.h, \\ &|\{l \in L \mid l.\mathrm{inv} \ne [\,]\}|,\ \textstyle\sum_{l \in L} \lfloor |l.\mathrm{inv}| / 4 \rfloor,\ \sum_{l \in L} \operatorname{area}(l.\mathrm{inv})\big),\quad L = s.\mathrm{layers},\ T = s.\mathrm{tiles} \end{aligned}$$
(the second-to-last entry is computed as $\sum_l |\operatorname{rects}(l.\mathrm{inv})|$, equal by `rects_length`)
-/
def census (s : Snap) : List (String × Int) :=
  [("census.snapshots", 1),
   ("census.layers", s.layers.length),
   ("census.drawingLayers", (s.layers.filter (·.draws)).length),
   ("census.drawingAreaPx", sumBy (fun l => if l.draws then l.width * l.height else 0) s.layers),
   ("census.tilings", natSum (s.layers.map (·.tilings))),
   ("census.tiles", s.tileCount),
   ("census.activeTiles", s.tiles.length),
   ("census.solidTiles", (s.tiles.filter (·.solid)).length),
   ("census.activeTileAreaPx", sumBy (fun t => t.width * t.height) s.tiles),
   ("raster.invalidatedLayers", (s.layers.filter (fun l => !l.invalidation.isEmpty)).length),
   ("raster.invalidationRects", natSum (s.layers.map fun l => (rects l.invalidation).length)),
   ("raster.invalidationAreaPx", sumBy (fun l => rectArea l.invalidation) s.layers)]

/-- The value of one census entry (0 for an unknown name).

$$\operatorname{at}(s, k) = \operatorname{countIn}(\operatorname{census}(s), k)$$
-/
def at? (s : Snap) (k : String) : Int := countIn (census s) k

#guard census ⟨0, [], []⟩ ==
  [("census.snapshots", 1), ("census.layers", 0), ("census.drawingLayers", 0), ("census.drawingAreaPx", 0),
   ("census.tilings", 0), ("census.tiles", 0), ("census.activeTiles", 0), ("census.solidTiles", 0),
   ("census.activeTileAreaPx", 0), ("raster.invalidatedLayers", 0), ("raster.invalidationRects", 0),
   ("raster.invalidationAreaPx", 0)]
#guard rects [0, 0, 3, 4, 1, 1, 5, 6, 9] == [(3, 4), (5, 6)]
#guard rectArea [0, 0, 3, 4, 1, 1, 5, 6, 9] == 42
#guard at? ⟨7, [⟨true, 10, 20, 2, [0, 0, 1, 1]⟩, ⟨false, 5, 5, 1, [1, 2, 3]⟩], [⟨true, 256, 256⟩, ⟨false, 256, 100⟩]⟩
  "raster.invalidatedLayers" == 2
#guard at? ⟨7, [⟨true, 10, 20, 2, [0, 0, 1, 1]⟩, ⟨false, 5, 5, 1, [1, 2, 3]⟩], [⟨true, 256, 256⟩, ⟨false, 256, 100⟩]⟩
  "raster.invalidationRects" == 1
#guard at? ⟨7, [⟨true, 10, 20, 2, [0, 0, 1, 1]⟩, ⟨false, 5, 5, 1, []⟩], [⟨true, 256, 256⟩, ⟨false, 256, 100⟩]⟩
  "census.activeTileAreaPx" == 91136

/-! ## Theorems -/

/-- The number of complete rects is the length divided by 4, rounded down.

$$\forall L:\ |\operatorname{rects}(L)| = \lfloor |L| / 4 \rfloor$$
-/
theorem rects_length : ∀ l : List Int, (rects l).length = l.length / 4
  | [] => rfl
  | [_] => by simp [rects]
  | [_, _] => by simp [rects]
  | [_, _, _] => by simp [rects]
  | _ :: _ :: _ :: _ :: rest => by
    simp only [rects, List.length_cons, rects_length rest]
    omega

/-- The census names, in order, are the twelve fixed names (every snapshot reports every name).

$$\forall s \in \mathrm{Snap}:\ \operatorname{names}(\operatorname{census}(s)) = [\texttt{census.snapshots}, \dots, \texttt{raster.invalidationAreaPx}]\ (12\ \text{names, independent of } s)$$
-/
theorem census_names (s : Snap) : (census s).map (·.1) =
    ["census.snapshots", "census.layers", "census.drawingLayers", "census.drawingAreaPx", "census.tilings",
     "census.tiles", "census.activeTiles", "census.solidTiles", "census.activeTileAreaPx",
     "raster.invalidatedLayers", "raster.invalidationRects", "raster.invalidationAreaPx"] := rfl

/-- Drawing layers and invalidated layers are among the layers; solid tiles among the active tiles.

$$\forall s = (c, L, T) \in \mathrm{Snap}:\ |\{l \in L \mid l.\mathrm{draws}\}| \le |L| \ \land\ |\{l \in L \mid l.\mathrm{inv} \ne [\,]\}| \le |L| \ \land\ |\{t \in T \mid t.\mathrm{solid}\}| \le |T|$$
-/
theorem subsets_le (s : Snap) :
    (s.layers.filter (·.draws)).length ≤ s.layers.length ∧
    (s.layers.filter (fun l => !l.invalidation.isEmpty)).length ≤ s.layers.length ∧
    (s.tiles.filter (·.solid)).length ≤ s.tiles.length :=
  ⟨List.length_filter_le _ _, List.length_filter_le _ _, List.length_filter_le _ _⟩

/-- A layer contributes rects only if its invalidation is non-empty, so a positive rect count
implies an invalidated layer.

$$\sum_{l \in L} |\operatorname{rects}(l.\mathrm{inv})| > 0 \implies |\{l \in L \mid l.\mathrm{inv} \ne [\,]\}| > 0$$
-/
theorem invalidated_of_rects : ∀ ls : List Layer,
    0 < natSum (ls.map fun l => (rects l.invalidation).length) →
    0 < (ls.filter (fun l => !l.invalidation.isEmpty)).length
  | [], h => by simp [natSum] at h
  | l :: ls, h => by
    cases hl : l.invalidation with
    | nil =>
      have : 0 < natSum (ls.map fun l => (rects l.invalidation).length) := by
        simpa [natSum, hl, rects] using h
      simpa [List.filter_cons, hl] using invalidated_of_rects ls this
    | cons x xs => simp [hl]

/-- A sum of non-negative terms is non-negative.

$$\forall g,\ L:\ (\forall x \in L:\ g(x) \ge 0) \implies \operatorname{sumBy}(g, L) \ge 0$$
-/
theorem sumBy_nonneg {α : Type} (g : α → Int) : ∀ l : List α, (∀ x ∈ l, 0 ≤ g x) → 0 ≤ sumBy g l
  | [], _ => by simp [sumBy]
  | a :: as, h => by
    simp only [sumBy]
    exact Int.add_nonneg (h a (by simp)) (sumBy_nonneg g as fun x hx => h x (by simp [hx]))

/-- The rect area is non-negative when every entry is.

$$(\forall x \in L:\ x \ge 0) \implies \operatorname{area}(L) \ge 0$$
-/
theorem rectArea_nonneg : ∀ l : List Int, (∀ x ∈ l, 0 ≤ x) → 0 ≤ rectArea l
  | [], _ => by simp [rectArea, rects, sumBy]
  | [_], _ => by simp [rectArea, rects, sumBy]
  | [_, _], _ => by simp [rectArea, rects, sumBy]
  | [_, _, _], _ => by simp [rectArea, rects, sumBy]
  | a :: b :: w :: h :: rest, hn => by
    have ih := rectArea_nonneg rest fun x hx => hn x (by simp [hx])
    simp only [rectArea, rects, sumBy] at ih ⊢
    exact Int.add_nonneg (Int.mul_nonneg (hn w (by simp)) (hn h (by simp))) ih

/-- The census is additive over the layers: the layer entries of a snapshot whose layers are
`L₁ ++ L₂` are the sums of the entries for `L₁` and `L₂` (shown for the drawing area, rect count
and invalidation area; the counts are filter lengths, additive by `List.filter_append`).

$$\forall L_1, L_2:\ \Sigma^{\mathrm{draw}}(L_1 \mathbin{+\!\!+} L_2) = \Sigma^{\mathrm{draw}}(L_1) + \Sigma^{\mathrm{draw}}(L_2) \ \land\ \Sigma^{\mathrm{area}}(L_1 \mathbin{+\!\!+} L_2) = \Sigma^{\mathrm{area}}(L_1) + \Sigma^{\mathrm{area}}(L_2) \ \land\ \Sigma^{\mathrm{rects}}(L_1 \mathbin{+\!\!+} L_2) = \Sigma^{\mathrm{rects}}(L_1) + \Sigma^{\mathrm{rects}}(L_2)$$
-/
theorem layers_additive (l₁ l₂ : List Layer) :
    sumBy (fun l => if l.draws then l.width * l.height else 0) (l₁ ++ l₂) =
      sumBy (fun l => if l.draws then l.width * l.height else 0) l₁ +
      sumBy (fun l => if l.draws then l.width * l.height else 0) l₂ ∧
    sumBy (fun l => rectArea l.invalidation) (l₁ ++ l₂) =
      sumBy (fun l => rectArea l.invalidation) l₁ + sumBy (fun l => rectArea l.invalidation) l₂ ∧
    natSum ((l₁ ++ l₂).map fun l => (rects l.invalidation).length) =
      natSum (l₁.map fun l => (rects l.invalidation).length) +
      natSum (l₂.map fun l => (rects l.invalidation).length) := by
  have hs : ∀ (g : Layer → Int) (a b : List Layer), sumBy g (a ++ b) = sumBy g a + sumBy g b := by
    intro g a b
    induction a with
    | nil => simp [sumBy]
    | cons x xs ih => simp only [List.cons_append, sumBy, ih]; omega
  have hn : ∀ (a b : List Nat), natSum (a ++ b) = natSum a + natSum b := by
    intro a b
    induction a with
    | nil => simp [natSum]
    | cons x xs ih => simp only [natSum, List.cons_append, List.foldr_cons] at ih ⊢; omega
  exact ⟨hs _ _ _, hs _ _ _, by rw [List.map_append, hn]⟩

end Fw.Measure.Snapshot
