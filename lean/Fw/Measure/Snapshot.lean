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

/-- The fields of one layer that the census reads. -/
structure Layer where
  draws : Bool
  width : Int
  height : Int
  tilings : Nat
  invalidation : List Int
deriving Repr, DecidableEq

/-- The fields of one active tile that the census reads: solid colour, content width and height. -/
structure Tile where
  solid : Bool
  width : Int
  height : Int
deriving Repr, DecidableEq

/-- A snapshot: tile count of the tile manager, active layers, active tiles. -/
structure Snap where
  tileCount : Int
  layers : List Layer
  tiles : List Tile
deriving Repr, DecidableEq

/-- The (width, height) of each complete quad `x, y, w, h` of a flattened rect list; a trailing
incomplete quad is dropped.
-/
def rects : List Int → List (Int × Int)
  | _ :: _ :: w :: h :: rest => (w, h) :: rects rest
  | _ => []

/-- The summed area of the complete rects. -/
def rectArea (l : List Int) : Int := sumBy (fun p => p.1 * p.2) (rects l)

/-- The sum of a list of naturals. -/
def natSum (l : List Nat) : Nat := l.foldr (· + ·) 0

/-- The census of one snapshot. -/
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

/-- The value of one census entry (0 for an unknown name). -/
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

/-- The number of complete rects is the length divided by 4, rounded down. -/
theorem rects_length : ∀ l : List Int, (rects l).length = l.length / 4
  | [] => rfl
  | [_] => by simp [rects]
  | [_, _] => by simp [rects]
  | [_, _, _] => by simp [rects]
  | _ :: _ :: _ :: _ :: rest => by
    simp only [rects, List.length_cons, rects_length rest]
    omega

/-- The census names, in order, are the twelve fixed names (every snapshot reports every name). -/
theorem census_names (s : Snap) : (census s).map (·.1) =
    ["census.snapshots", "census.layers", "census.drawingLayers", "census.drawingAreaPx", "census.tilings",
     "census.tiles", "census.activeTiles", "census.solidTiles", "census.activeTileAreaPx",
     "raster.invalidatedLayers", "raster.invalidationRects", "raster.invalidationAreaPx"] := rfl

/-- Drawing layers and invalidated layers are among the layers; solid tiles among the active tiles. -/
theorem subsets_le (s : Snap) :
    (s.layers.filter (·.draws)).length ≤ s.layers.length ∧
    (s.layers.filter (fun l => !l.invalidation.isEmpty)).length ≤ s.layers.length ∧
    (s.tiles.filter (·.solid)).length ≤ s.tiles.length :=
  ⟨List.length_filter_le _ _, List.length_filter_le _ _, List.length_filter_le _ _⟩

/-- A layer contributes rects only if its invalidation is non-empty, so a positive rect count
implies an invalidated layer.
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

/-- A sum of non-negative terms is non-negative. -/
theorem sumBy_nonneg {α : Type} (g : α → Int) : ∀ l : List α, (∀ x ∈ l, 0 ≤ g x) → 0 ≤ sumBy g l
  | [], _ => by simp [sumBy]
  | a :: as, h => by
    simp only [sumBy]
    exact Int.add_nonneg (h a (by simp)) (sumBy_nonneg g as fun x hx => h x (by simp [hx]))

/-- The rect area is non-negative when every entry is. -/
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
