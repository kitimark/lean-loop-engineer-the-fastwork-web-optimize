import Lean.Data.Json
import Fw.Measure.WebKitLag
/-!
# WebKit cost counters (`packages/measure-webkit/src/lag/cost.mjs`)
The counted predicates of the lag cost pass and their per-zone sums. Times are integer microseconds.
-/
namespace Fw.Measure.WkCost
open Lean Fw.Measure.WebKitLag

/-! ## Constants the page and the reducer share -/

/-- The morph tween length in microseconds (`apps/site/src/parts/morph.tween/logic.ts` `DURATION_MS`). -/
def tweenUs : Int := 680000

/-- The early window after a morph ends, in microseconds. -/
def earlyUs : Int := 500000

/-- The late window after the early one, in microseconds. -/
def lateUs : Int := 500000

/-- Upper edges of the interval histogram bins in microseconds; a seventh bin holds the rest. -/
def histEdges : List Int := [12000, 20000, 25000, 34000, 50000, 100000]

/-! ## Frame cadence -/

/-- The display slot of an offset from the first frame: the offset over 50000/3 microseconds, rounded half up. -/
def slotOf (d : Int) : Int := (6 * d + 50000) / 100000

/-- A rendered frame: the rAF timestamp and the zone of the step or phase it belongs to. -/
structure Frame where
  t : Int
  zone : String
  deriving Repr, BEq

/-- The interval to the previous frame and the slots skipped since it, kept with the zone of the later frame. -/
structure Delta where
  zone : String
  d : Int
  g : Int
  deriving Repr, BEq

/-- The delta between two consecutive frames, slots counted from the first frame `t0`. -/
def deltaOf (t0 : Int) (a b : Frame) : Delta := ⟨b.zone, b.t - a.t, slotOf (b.t - t0) - slotOf (a.t - t0)⟩

/-- The deltas of consecutive frames, slots counted from `t0`. -/
def deltasFrom (t0 : Int) : List Frame → List Delta
  | a :: b :: rest => deltaOf t0 a b :: deltasFrom t0 (b :: rest)
  | _ => []

/-- The deltas of a frame list, slots counted from its first frame. -/
def deltas : List Frame → List Delta
  | [] => []
  | f :: fs => deltasFrom f.t (f :: fs)

/-- Intervals in the zone longer than `th` microseconds. -/
def nOver (th : Int) (z : String) : List Delta → Nat
  | [] => 0
  | x :: xs => (if x.zone == z ∧ th < x.d then 1 else 0) + nOver th z xs

/-- Intervals in the zone that jump more than one display slot. -/
def nSkip (z : String) : List Delta → Nat
  | [] => 0
  | x :: xs => (if x.zone == z ∧ 1 < x.g then 1 else 0) + nSkip z xs

/-- Slots skipped in the zone: the sum of the slot jumps beyond one. -/
def nSlots (z : String) : List Delta → Nat
  | [] => 0
  | x :: xs => (if x.zone == z then (x.g - 1).toNat else 0) + nSlots z xs

/-- Frames in the zone. -/
def nFrames (z : String) (fs : List Frame) : Nat := (fs.filter fun f => f.zone == z).length

/-- The histogram bin of an interval: 0 up to the first edge, then one bin per edge, 6 beyond the last. -/
def histBin (d : Int) : Nat :=
  if d ≤ 12000 then 0 else if d ≤ 20000 then 1 else if d ≤ 25000 then 2 else if d ≤ 34000 then 3
  else if d ≤ 50000 then 4 else if d ≤ 100000 then 5 else 6

/-- Intervals of the zone in bin `b`. -/
def nBin (z : String) (b : Nat) : List Delta → Nat
  | [] => 0
  | x :: xs => (if x.zone == z ∧ histBin x.d = b then 1 else 0) + nBin z b xs

/-- The seven bin counts of a zone. -/
def hist (z : String) (ds : List Delta) : List Nat := [0, 1, 2, 3, 4, 5, 6].map fun b => nBin z b ds

/-- Intervals of the zone. -/
def nIv (z : String) : List Delta → Nat
  | [] => 0
  | x :: xs => (if x.zone == z then 1 else 0) + nIv z xs

/-- A longer threshold counts no more intervals. -/
theorem nOver_anti (z : String) {a b : Int} (h : a ≤ b) : ∀ ds : List Delta, nOver b z ds ≤ nOver a z ds
  | [] => by simp [nOver]
  | x :: xs => by
    have ih := nOver_anti z h xs
    unfold nOver
    by_cases hz : (x.zone == z) = true
    · simp only [hz, true_and]
      split <;> split <;> omega
    · simp [hz]
      omega

/-- Over 50 ms is over 34 ms is over 25 ms. -/
theorem over_chain (z : String) (ds : List Delta) :
    nOver 50000 z ds ≤ nOver 34000 z ds ∧ nOver 34000 z ds ≤ nOver 25000 z ds :=
  ⟨nOver_anti z (by omega) ds, nOver_anti z (by omega) ds⟩

/-- An offset gap of two slots and a bit always moves the slot by two or more. -/
theorem slot_gap_of_long (x y : Int) (h : 33334 ≤ y - x) : 2 ≤ slotOf y - slotOf x := by
  unfold slotOf; omega

/-- Every interval over two display slots is a skipped slot (the converse fails: 25.5 ms can fall in one slot). -/
theorem nOver_le_nSkip_from (z : String) (t0 : Int) : ∀ fs : List Frame,
    nOver 33333 z (deltasFrom t0 fs) ≤ nSkip z (deltasFrom t0 fs)
  | [] => by simp [deltasFrom, nOver, nSkip]
  | [_] => by simp [deltasFrom, nOver, nSkip]
  | a :: b :: rest => by
    have ih := nOver_le_nSkip_from z t0 (b :: rest)
    unfold deltasFrom nOver nSkip
    simp only [deltaOf]
    by_cases hz : b.zone == z
    · by_cases hl : 33333 < b.t - a.t
      · have hs := slot_gap_of_long (a.t - t0) (b.t - t0) (by omega)
        have hs' : 1 < slotOf (b.t - t0) - slotOf (a.t - t0) := by omega
        simp [hz, hl, hs']
        omega
      · by_cases hk : 1 < slotOf (b.t - t0) - slotOf (a.t - t0) <;> simp [hz, hl, hk] <;> omega
    · simp [hz]
      omega

/-- Every interval over two display slots is a skipped slot, for the zone of a frame list. -/
theorem nOver_le_nSkip (z : String) (fs : List Frame) : nOver 33333 z (deltas fs) ≤ nSkip z (deltas fs) := by
  cases fs with
  | nil => simp [deltas, nOver, nSkip]
  | cons f fs => exact nOver_le_nSkip_from z f.t (f :: fs)

/-- A skipped-slot event skips at least one slot, so the slot total is no smaller than the event count. -/
theorem nSkip_le_nSlots (z : String) : ∀ ds : List Delta, nSkip z ds ≤ nSlots z ds
  | [] => by simp [nSkip, nSlots]
  | x :: xs => by
    have ih := nSkip_le_nSlots z xs
    unfold nSkip nSlots
    by_cases hz : x.zone == z
    · by_cases hk : 1 < x.g <;> simp [hz, hk] <;> omega
    · simp [hz]
      omega

/-- Bin 0: an interval of 12 ms or less. -/
theorem histBin_0 {d : Int} (h : d ≤ 12000) : histBin d = 0 := by simp [histBin, h]

/-- Bin 1: over 12 ms up to 20 ms. -/
theorem histBin_1 {d : Int} (h1 : 12000 < d) (h2 : d ≤ 20000) : histBin d = 1 := by
  unfold histBin; repeat' split
  all_goals omega

/-- Bin 2: over 20 ms up to 25 ms. -/
theorem histBin_2 {d : Int} (h1 : 20000 < d) (h2 : d ≤ 25000) : histBin d = 2 := by
  unfold histBin; repeat' split
  all_goals omega

/-- Bin 3: over 25 ms up to 34 ms. -/
theorem histBin_3 {d : Int} (h1 : 25000 < d) (h2 : d ≤ 34000) : histBin d = 3 := by
  unfold histBin; repeat' split
  all_goals omega

/-- Bin 4: over 34 ms up to 50 ms. -/
theorem histBin_4 {d : Int} (h1 : 34000 < d) (h2 : d ≤ 50000) : histBin d = 4 := by
  unfold histBin; repeat' split
  all_goals omega

/-- Bin 5: over 50 ms up to 100 ms. -/
theorem histBin_5 {d : Int} (h1 : 50000 < d) (h2 : d ≤ 100000) : histBin d = 5 := by
  unfold histBin; repeat' split
  all_goals omega

/-- Bin 6: over 100 ms. -/
theorem histBin_6 {d : Int} (h : 100000 < d) : histBin d = 6 := by
  unfold histBin; repeat' split
  all_goals omega

/-- Every interval has a bin below seven. -/
theorem histBin_lt (d : Int) : histBin d < 7 := by
  unfold histBin; repeat' split
  all_goals omega

/-- The bin counts of a zone add up to its intervals. -/
theorem hist_sum (z : String) (ds : List Delta) : (hist z ds).sum = nIv z ds := by
  unfold hist
  simp only [List.map_cons, List.map_nil, List.sum_cons, List.sum_nil]
  induction ds with
  | nil => simp [nBin, nIv]
  | cons x xs ih =>
    have hb := histBin_lt x.d
    simp only [nBin, nIv]
    have hk : histBin x.d = 0 ∨ histBin x.d = 1 ∨ histBin x.d = 2 ∨ histBin x.d = 3 ∨ histBin x.d = 4 ∨
        histBin x.d = 5 ∨ histBin x.d = 6 := by omega
    by_cases hz : x.zone == z
    · rcases hk with h | h | h | h | h | h | h <;> simp [hz, h] <;> omega
    · simp [hz]
      omega

/-! ## Composite against Paint -/

/-- One frame's Paint and Composite durations in the zone. -/
structure Cost where
  zone : String
  paintUs : Int
  compUs : Int
  deriving Repr, BEq

/-- A frame is composite-bound when its Composite time exceeds its Paint time. -/
def compositeBound (c : Cost) : Bool := decide (c.paintUs < c.compUs)

/-- Frames, Paint time, Composite time and composite-bound frames of a zone. -/
structure Sums where
  frames : Nat
  paintUs : Int
  compUs : Int
  bound : Nat
  deriving Repr, BEq

/-- The sums of the frames of a zone. -/
def sumsOf (z : String) (cs : List Cost) : Sums :=
  let zs := cs.filter fun c => c.zone == z
  ⟨zs.length, (zs.map (·.paintUs)).sum, (zs.map (·.compUs)).sum, (zs.filter compositeBound).length⟩

/-- Composite-bound: the Composite time is the larger. -/
theorem compositeBound_true {c : Cost} (h : c.paintUs < c.compUs) : compositeBound c = true := by
  simp [compositeBound, h]

/-- Not composite-bound: the Paint time is at least the Composite time. -/
theorem compositeBound_false {c : Cost} (h : c.compUs ≤ c.paintUs) : compositeBound c = false := by
  simp [compositeBound]; omega

/-- No zone has more composite-bound frames than frames. -/
theorem bound_le_frames (z : String) (cs : List Cost) : (sumsOf z cs).bound ≤ (sumsOf z cs).frames := by
  unfold sumsOf
  exact List.length_filter_le _ _

/-- Sums of two runs of frames add. -/
theorem sumsOf_append (z : String) (a b : List Cost) :
    sumsOf z (a ++ b) = ⟨(sumsOf z a).frames + (sumsOf z b).frames, (sumsOf z a).paintUs + (sumsOf z b).paintUs,
      (sumsOf z a).compUs + (sumsOf z b).compUs, (sumsOf z a).bound + (sumsOf z b).bound⟩ := by
  simp [sumsOf, List.filter_append, List.map_append, List.sum_append, List.length_append]

/-! ## Layers between two reads of the layer tree -/

/-- A composited layer: the inspector id and the size of its composited bounds. -/
structure Layer where
  id : String
  w : Int
  h : Int
  deriving Repr, BEq

/-- A layer is new when no layer of the earlier read has its id. -/
def isNew (prev : List Layer) (l : Layer) : Bool := !(prev.any fun p => p.id == l.id)

/-- A layer is resized when the earlier read has its id with another width or height. -/
def isResized (prev : List Layer) (l : Layer) : Bool := prev.any fun p => p.id == l.id && (p.w != l.w || p.h != l.h)

/-- Layers of the later read that the earlier read did not have. -/
def newLayers (prev cur : List Layer) : Nat := (cur.filter (isNew prev)).length

/-- Layers of the later read whose size differs from the earlier read. -/
def resizedLayers (prev cur : List Layer) : Nat := (cur.filter (isResized prev)).length

/-- No layer is new against its own read. -/
theorem newLayers_self (l : List Layer) : newLayers l l = 0 := by
  unfold newLayers
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro x hx
  simp only [isNew, Bool.not_eq_true', Bool.not_eq_false]
  exact List.any_eq_true.mpr ⟨x, hx, by simp⟩

/-- Against an empty read every layer is new. -/
theorem newLayers_nil (cur : List Layer) : newLayers [] cur = cur.length := by
  simp [newLayers, isNew]

/-- Against an empty read no layer is resized. -/
theorem resizedLayers_nil (cur : List Layer) : resizedLayers [] cur = 0 := by
  simp [resizedLayers, isResized]

/-- A new layer is not resized. -/
theorem isResized_of_isNew {prev : List Layer} {l : Layer} (h : isNew prev l = true) : isResized prev l = false := by
  simp only [isNew, Bool.not_eq_true'] at h
  simp only [isResized, Bool.eq_false_iff, ne_eq, List.any_eq_true, not_exists, not_and]
  intro p hp hc
  have := List.any_eq_false.mp h p hp
  simp_all

/-- New and resized layers are disjoint, so together they are no more than the later read. -/
theorem new_add_resized_le (prev cur : List Layer) : newLayers prev cur + resizedLayers prev cur ≤ cur.length := by
  unfold newLayers resizedLayers
  induction cur with
  | nil => simp
  | cons x xs ih =>
    by_cases hn : isNew prev x = true
    · have := isResized_of_isNew hn
      simp [hn, this]
      omega
    · by_cases hr : isResized prev x = true
      · simp [hn, hr]
        omega
      · simp [hn, hr]
        omega

/-- A layer-tree read and the zone of the step or phase it was taken in. -/
structure Snap where
  zone : String
  layers : List Layer
  deriving Repr, BEq

/-- The counts between two reads, kept with the zone of the later one. -/
structure LayerDelta where
  zone : String
  fresh : Nat
  resized : Nat
  deriving Repr, BEq

/-- The layer deltas of consecutive reads. -/
def layerDeltas : List Snap → List LayerDelta
  | a :: b :: rest => ⟨b.zone, newLayers a.layers b.layers, resizedLayers a.layers b.layers⟩ :: layerDeltas (b :: rest)
  | _ => []

/-- Reads in the zone after the first, new layers, and resized layers. -/
def layerSums (z : String) (ss : List Snap) : Nat × Nat × Nat :=
  let ds := (layerDeltas ss).filter fun x => x.zone == z
  (ds.length, (ds.map (·.fresh)).sum, (ds.map (·.resized)).sum)

/-! ## Paints after a morph ends -/

/-- Records strictly after `lo` and up to `hi`. -/
def nIn (lo hi : Int) : List Int → Nat
  | [] => 0
  | t :: ts => (if lo < t ∧ t ≤ hi then 1 else 0) + nIn lo hi ts

/-- The paint start times in the early window after a morph that ends at `e`. -/
def early (e : Int) (ts : List Int) : Nat := nIn e (e + earlyUs) ts

/-- The paint start times in the late window after the early one. -/
def late (e : Int) (ts : List Int) : Nat := nIn (e + earlyUs) (e + earlyUs + lateUs) ts

/-- The end of a morph that was pushed at `p`. -/
def morphEnd (p : Int) : Int := p + tweenUs

/-- The early and late windows are disjoint and together cover the span to the end of the late window. -/
theorem early_add_late (e : Int) : ∀ ts : List Int, early e ts + late e ts = nIn e (e + earlyUs + lateUs) ts := by
  unfold early late earlyUs lateUs
  intro ts
  induction ts with
  | nil => simp [nIn]
  | cons t ts ih =>
    simp only [nIn]
    split <;> split <;> split <;> omega

/-- A paint at the end instant itself is in neither window. -/
theorem nIn_nil (lo hi : Int) : nIn lo hi [] = 0 := by simp [nIn]

/-! ## Morph phases -/

/-- The zone of a morph frame at time `t`, with the two pushes at `po` and `pc`: before the first push idle, within a tween
the direction, otherwise rest. -/
def morphZone (po pc t : Int) : String :=
  if t < po then "idle"
  else if t ≤ morphEnd po then "open"
  else if t < pc then "rest"
  else if t ≤ morphEnd pc then "close"
  else "rest"

/-- Before the open push the page is idle. -/
theorem morphZone_idle {po pc t : Int} (h : t < po) : morphZone po pc t = "idle" := by simp [morphZone, h]

/-- Within the open tween the zone is `open`. -/
theorem morphZone_open {po pc t : Int} (h1 : po ≤ t) (h2 : t ≤ morphEnd po) : morphZone po pc t = "open" := by
  unfold morphZone morphEnd tweenUs at *
  repeat' split
  all_goals first | rfl | (exfalso; omega)

/-- Between the open tween and the close push the zone is `rest`. -/
theorem morphZone_rest_between {po pc t : Int} (h1 : morphEnd po < t) (h2 : t < pc) : morphZone po pc t = "rest" := by
  unfold morphZone morphEnd tweenUs at *
  repeat' split
  all_goals first | rfl | (exfalso; omega)

/-- From the close push to its end the zone is `close`. -/
theorem morphZone_close {po pc t : Int} (h1 : pc ≤ t) (h2 : t ≤ morphEnd pc) (h3 : morphEnd po < pc) :
    morphZone po pc t = "close" := by
  unfold morphZone morphEnd tweenUs at *
  repeat' split
  all_goals first | rfl | (exfalso; omega)

/-- After the close tween the zone is `rest`. -/
theorem morphZone_rest_after {po pc t : Int} (h : morphEnd pc < t) (h0 : morphEnd po < pc) : morphZone po pc t = "rest" := by
  unfold morphZone morphEnd tweenUs at *
  repeat' split
  all_goals first | rfl | (exfalso; omega)

/-! ## Scroll zones -/

/-- The zone of a scroll step: its `Fw.Measure.WebKitLag` region at zone height `vh`. -/
def scrollZone (vh : Nat) (maxY y : Int) : String := "scroll-" ++ (regionOf vh maxY y).name

/-! ## Golden vectors -/

private def fj (f : Frame) : Json := Json.arr #[toJson f.t, toJson f.zone]
private def dj (d : Delta) : Json := Json.arr #[toJson d.zone, toJson d.d, toJson d.g]
private def cj (c : Cost) : Json := Json.arr #[toJson c.zone, toJson c.paintUs, toJson c.compUs]
private def sj (x : Snap) : Json :=
  Json.arr #[toJson x.zone, Json.arr (x.layers.map fun l => Json.arr #[toJson l.id, toJson l.w, toJson l.h]).toArray]

private def mkF (zt : List (String × Int)) : List Frame := zt.map fun (z, t) => ⟨t, z⟩

private def frameCases : List (List String × List Frame) :=
  [(["s"], []),
   (["s"], mkF [("s", 0), ("s", 16667), ("s", 33333), ("s", 50000)]),
   (["scroll-A", "scroll-B"], mkF [("scroll-A", 0), ("scroll-A", 16700), ("scroll-A", 52000), ("scroll-B", 68700),
     ("scroll-B", 135000), ("scroll-B", 151700)]),
   (["s"], mkF [("s", 0), ("s", 10000), ("s", 36000)]),
   (["open", "close"], mkF [("open", 5000), ("open", 21000), ("open", 120000), ("close", 137000), ("close", 187500),
     ("close", 304000), ("close", 321000)])]

private def costCases : List (String × List Cost) :=
  [("s", []), ("s", [⟨"s", 100, 50⟩, ⟨"s", 50, 100⟩, ⟨"s", 70, 70⟩, ⟨"t", 1, 9⟩, ⟨"s", 0, 3⟩]),
   ("morph", [⟨"morph", 4000, 9000⟩, ⟨"morph", 12000, 2000⟩, ⟨"scroll-A", 1, 2⟩])]

private def L (id : String) (w h : Int) : Layer := ⟨id, w, h⟩

private def snapCases : List (List String × List Snap) :=
  [(["s"], []),
   (["s"], [⟨"s", [L "1" 10 10]⟩]),
   (["scroll-A", "scroll-B"], [⟨"scroll-A", [L "1" 10 10, L "2" 20 20]⟩, ⟨"scroll-A", [L "1" 10 10, L "2" 20 30]⟩,
     ⟨"scroll-B", [L "1" 10 10, L "2" 20 30, L "3" 5 5]⟩, ⟨"scroll-B", [L "2" 20 30, L "4" 6 6, L "5" 7 7]⟩,
     ⟨"scroll-B", [L "2" 20 30, L "4" 6 6, L "5" 7 7]⟩])]

private def postCases : List (Int × List Int) :=
  [(0, []), (0, [100000, 680000, 680001, 900000, 1180000, 1180001, 1500000, 1680000, 1680001]),
   (1000000, [1000000, 1680000, 2000000, 2180000, 2180001, 2680000, 2680001])]

private def morphCases : List (Int × Int × Int) :=
  [(100000, 1500000, 0), (100000, 1500000, 99999), (100000, 1500000, 100000), (100000, 1500000, 780000),
   (100000, 1500000, 780001), (100000, 1500000, 1499999), (100000, 1500000, 1500000), (100000, 1500000, 2180000),
   (100000, 1500000, 2180001)]

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "const"), ("tweenUs", tweenUs), ("earlyUs", earlyUs), ("lateUs", lateUs),
    ("histEdges", toJson histEdges)]).compress] ++
  (([0, 1, 8333, 8334, 25000, 25001, 33333, 33334, 50000, 100000, 200000] : List Int).map fun (d : Int) =>
    (Json.mkObj [("kind", "slot"), ("d", d), ("slot", slotOf d)]).compress) ++
  (([0, 12000, 12001, 20000, 20001, 25000, 25001, 34000, 34001, 50000, 50001, 100000, 100001] : List Int).map fun (d : Int) =>
    (Json.mkObj [("kind", "bin"), ("d", d), ("bin", histBin d)]).compress) ++
  (frameCases.map fun (zs, fs) =>
    (Json.mkObj [("kind", "frames"), ("frames", Json.arr (fs.map fj).toArray),
      ("deltas", Json.arr ((deltas fs).map dj).toArray),
      ("zones", Json.arr (zs.map fun (z : String) => Json.mkObj [("zone", z), ("frames", nFrames z fs),
        ("over25", nOver 25000 z (deltas fs)), ("over34", nOver 34000 z (deltas fs)), ("over50", nOver 50000 z (deltas fs)),
        ("skipped", nSkip z (deltas fs)), ("slots", nSlots z (deltas fs)), ("hist", toJson (hist z (deltas fs)))]).toArray)]).compress) ++
  (costCases.map fun (z, cs) =>
    let r := sumsOf z cs
    (Json.mkObj [("kind", "cost"), ("costs", Json.arr (cs.map cj).toArray), ("zone", z), ("frames", r.frames),
      ("paintUs", r.paintUs), ("compUs", r.compUs), ("bound", r.bound)]).compress) ++
  (snapCases.map fun (zs, ss) =>
    (Json.mkObj [("kind", "layers"), ("snaps", Json.arr (ss.map sj).toArray),
      ("zones", Json.arr (zs.map fun (z : String) =>
        let (n, a, b) := layerSums z ss
        Json.mkObj [("zone", z), ("reads", n), ("fresh", a), ("resized", b)]).toArray)]).compress) ++
  (postCases.map fun (p, ts) =>
    (Json.mkObj [("kind", "post"), ("push", p), ("ts", toJson ts), ("end", morphEnd p), ("early", early (morphEnd p) ts),
      ("late", late (morphEnd p) ts)]).compress) ++
  (morphCases.map fun (po, pc, t) =>
    (Json.mkObj [("kind", "morphZone"), ("po", po), ("pc", pc), ("t", t), ("zone", morphZone po pc t)]).compress) ++
  (([(775, 9000, 0), (775, 9000, 774), (775, 9000, 775), (775, 9000, 4000), (775, 9000, 7450), (775, 9000, 8300)] : List (Nat × Int × Int)).map
    fun (vh, m, y) => (Json.mkObj [("kind", "scrollZone"), ("vh", vh), ("maxY", m), ("y", y),
      ("zone", scrollZone vh m y)]).compress)

/-- The bytes of `packages/contracts/golden/measure/wkcost.jsonl`. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"wkcost golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"wkcost golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Measure.WkCost
