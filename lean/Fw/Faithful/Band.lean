import Fw.Measure.Freeze
import Fw.Measure.Tolerance
/-!
# PL5 bands for one count cell (task faithful-checks)

PLAN §6.6 PL5 compares the rewrite R with the original A per count family: rAF callbacks, layers and the
compositor/main split **exact**; style and layout passes and elements within `max(2, 5 %)`; paint and raster
within `max(2, 10 %)`; sheet mutations `0`. Only deterministic and stable types take part, a stable type as a
total with margin `2t` (V-i, `Fw.Measure.marginOf`). This module is the verdict of **one cell** (a zone and a type):

* `bandTable` is an allowlist from a type to its family; every type not in it is `unbanded` (reported, never gated).
* The band of a cell is the interval `[lo_A - s - m, hi_A + s + m]` around A's observed envelope
  over its shards, where `s` is the family slack at A's median and `m` the stable margin; R's median must lie in it.
  For a deterministic type `lo_A = hi_A`, so the band is the plain `|R - A| ≤ s`.
* A cell is `skipped` unless A's frozen class table lists the type as deterministic or stable.
* Forced layouts (PLAN §6.6 asks for them exact) have no count type in `bandTable` and are not gated.

Proved: the verdict is exactly the interval test (`status_pass_iff`); a deterministic exact-family cell passes
exactly when R equals A (`exact_det_pass_iff`); every observed A value lies in its own band (`aa_in_band`); the
band never shrinks when the margin grows (`inBand_mono`); quarantined and unlisted types are never
gated (`skipped_of_quar`, `skipped_of_unlisted`); unbanded types never fail (`unbanded_not_fail`).
-/
namespace Fw.Faithful
open Fw.Measure

/-! ## Families -/

/-- The PL5 band families. -/
inductive Family where
  | exact
  | zero
  | pct5
  | pct10
  | unbanded
deriving Repr, DecidableEq

/-- The allowlist from a Chromium count type to its family. -/
def bandTable : List (String × Family) :=
  [ ("trace.FireAnimationFrame", .exact), ("trace.RequestAnimationFrame", .exact),
    ("census.layers", .exact), ("census.drawingLayers", .exact), ("trace.Layer.created", .exact),
    ("trace.Layer.deleted", .exact), ("hasDamage", .exact), ("trace.Animation.begin", .exact),
    ("trace.Animation.instant", .exact), ("trace.Animation.compositeFailedBits", .exact),
    ("trace.Commit", .exact), ("trace.Layerize", .exact), ("trace.ScrollLayer", .exact),
    ("trace.cc.Activate", .exact), ("trace.cc.Commit", .exact), ("trace.cc.Draw", .exact),
    ("trace.cc.SynchronizeTrees", .exact),
    ("n0.cssom", .zero), ("n0.events", .zero), ("n0.sheetNode", .zero),
    ("trace.N1.fontUpdateInvalidation", .zero), ("trace.N1.scheduleInvalidationsForRuleSets", .zero),
    ("trace.N1.svgImageDocument", .zero), ("trace.N1.updateActiveStyleSheets", .zero),
    ("metric.LayoutCount", .pct5), ("metric.RecalcStyleCount", .pct5), ("metric.LayoutObjects", .pct5),
    ("metric.Nodes", .pct5), ("trace.InvalidateLayout", .pct5), ("trace.Layout", .pct5),
    ("trace.Layout.dirtyObjects", .pct5), ("trace.Layout.partial", .pct5), ("trace.Layout.totalObjects", .pct5),
    ("trace.ScheduleStyleRecalculation", .pct5), ("trace.UpdateLayoutTree", .pct5),
    ("trace.UpdateLayoutTree.elementCount", .pct5),
    ("census.activeTileAreaPx", .pct10), ("census.activeTiles", .pct10), ("census.drawingAreaPx", .pct10),
    ("census.solidTiles", .pct10), ("census.tiles", .pct10), ("census.tilings", .pct10),
    ("raster.invalidatedLayers", .pct10), ("raster.invalidationAreaPx", .pct10),
    ("raster.invalidationRects", .pct10), ("trace.CullRectUpdate", .pct10), ("trace.DecodeImage", .pct10),
    ("trace.DisplayItemListRaster", .pct10), ("trace.ImageDecodeTask", .pct10), ("trace.Paint", .pct10),
    ("trace.PaintImage", .pct10), ("trace.PrePaint", .pct10), ("trace.RasterTask", .pct10),
    ("trace.UpdateLayer", .pct10) ]

/-- The family of a type: its row of `bandTable`, `unbanded` when it has none. -/
def familyOf (ty : String) : Family := ((bandTable.find? (·.1 == ty)).map (·.2)).getD .unbanded

#guard familyOf "trace.FireAnimationFrame" == .exact
#guard familyOf "n0.events" == .zero
#guard familyOf "trace.Layout" == .pct5
#guard familyOf "trace.Paint" == .pct10
#guard familyOf "trace.FunctionCall" == .unbanded
#guard familyOf "no.such.type" == .unbanded

/-! ## The band of a cell -/

/-- The family slack at A's median `a`, in hundredths of a count: `0` for the exact, zero and unbanded families,
`max(200, 5|a|)` for pct5 and `max(200, 10|a|)` for pct10 (that is `100 max(2, p %·|a|)`).
-/
def slack100 : Family → Int → Int
  | .pct5, a => max 200 (5 * (a.natAbs : Int))
  | .pct10, a => max 200 (10 * (a.natAbs : Int))
  | _, _ => 0

/-- The stable margin of a table entry in counts: `2t` for a stable entry with `k ≥ 1` (`Fw.Measure.marginOf`),
`0` for a deterministic one.
-/
def margin (e : Freeze.Entry) : Int := if e.cls = .stable then marginOf e.k e.t else 0

/-- One cell as measured: A's envelope `lo_A ≤ hi_A` and median `a` over its shards, and R's median `r`. -/
structure Obs where
  lo : Int
  hi : Int
  a : Int
  r : Int
deriving Repr, DecidableEq

/-- The verdict of a cell. -/
inductive Status where
  | pass
  | fail
  | skipped
  | unbanded
deriving Repr, DecidableEq

/-- Whether R's median is inside the band, in hundredths of a count. For the zero family the band is `[-m, m]` (no
envelope, no slack); otherwise it is `[lo_A - w/100, hi_A + w/100]` with `w = slack(f, a) + 100 m`.
-/
def inBand (f : Family) (m : Int) (o : Obs) : Prop :=
  match f with
  | .zero => 100 * (o.r.natAbs : Int) ≤ 100 * m
  | _ => 100 * o.lo - (slack100 f o.a + 100 * m) ≤ 100 * o.r ∧ 100 * o.r ≤ 100 * o.hi + (slack100 f o.a + 100 * m)

instance (f : Family) (m : Int) (o : Obs) : Decidable (inBand f m o) := by
  unfold inBand; cases f <;> infer_instance

/-- The verdict of a cell: `skipped` unless A's entry is deterministic or stable; `unbanded` for a type with no
band; else `pass` exactly when R's median is in the band.
-/
def status (e : Option Freeze.Entry) (ty : String) (o : Obs) : Status :=
  match e with
  | none => .skipped
  | some e =>
    if e.cls = .quar then .skipped
    else if familyOf ty = .unbanded then .unbanded
    else if inBand (familyOf ty) (margin e) o then .pass else .fail

/-- The deterministic table entry. -/
def detEntry : Freeze.Entry := { cls := .det, k := 0, t := 0, tBound := none }

#guard status (some detEntry) "trace.cc.Draw" ⟨50, 50, 50, 50⟩ == .pass
#guard status (some detEntry) "trace.cc.Draw" ⟨50, 50, 50, 51⟩ == .fail
#guard status (some detEntry) "trace.Layout" ⟨100, 100, 100, 105⟩ == .pass
#guard status (some detEntry) "trace.Layout" ⟨100, 100, 100, 106⟩ == .fail
#guard status (some detEntry) "trace.Layout" ⟨1, 1, 1, 3⟩ == .pass
#guard status (some detEntry) "trace.Layout" ⟨1, 1, 1, 4⟩ == .fail
#guard status (some detEntry) "trace.Paint" ⟨1000, 1000, 1000, 1100⟩ == .pass
#guard status (some detEntry) "trace.Paint" ⟨1000, 1000, 1000, 1101⟩ == .fail
#guard status (some detEntry) "n0.events" ⟨0, 0, 0, 0⟩ == .pass
#guard status (some detEntry) "n0.events" ⟨0, 0, 0, 1⟩ == .fail
#guard status (some detEntry) "trace.FunctionCall" ⟨5, 5, 5, 9⟩ == .unbanded
#guard status (some { detEntry with cls := .quar }) "trace.Layout" ⟨5, 5, 5, 9⟩ == .skipped
#guard status none "trace.Layout" ⟨5, 5, 5, 9⟩ == .skipped
#guard status (some { detEntry with cls := .stable, k := 2, t := 3 }) "trace.cc.Draw" ⟨10, 12, 11, 18⟩ == .pass
#guard status (some { detEntry with cls := .stable, k := 2, t := 3 }) "trace.cc.Draw" ⟨10, 12, 11, 19⟩ == .fail

/-! ## Theorems -/

/-- **The verdict is the interval test.** For a gated, banded type the cell passes exactly when R's median is in the
band.
-/
theorem status_pass_iff {e : Freeze.Entry} {ty : String} {o : Obs} (hq : e.cls ≠ .quar)
    (hb : familyOf ty ≠ .unbanded) :
    status (some e) ty o = .pass ↔ inBand (familyOf ty) (margin e) o := by
  by_cases h : inBand (familyOf ty) (margin e) o <;> simp [status, hq, hb, h]

/-- A deterministic cell of the exact family passes exactly when R equals A (no envelope, no slack, no margin). -/
theorem exact_det_pass_iff {ty : String} {a r : Int} (hf : familyOf ty = .exact) :
    status (some detEntry) ty ⟨a, a, a, r⟩ = .pass ↔ r = a := by
  have hq : detEntry.cls ≠ .quar := by decide
  have hb : familyOf ty ≠ .unbanded := by rw [hf]; decide
  rw [status_pass_iff hq hb]
  simp only [hf, inBand, slack100, margin, detEntry]
  simp
  omega

/-- **A/A.** Every value `x` observed in A's own shards, `lo_A ≤ x ≤ hi_A`, lies in the band
(for any family but zero, any margin `m ≥ 0`), so a rewrite that behaves exactly like one of A's own runs passes.
-/
theorem aa_in_band {f : Family} {m lo hi a x : Int} (hf : f ≠ .zero) (hm : 0 ≤ m) (h1 : lo ≤ x) (h2 : x ≤ hi) :
    inBand f m ⟨lo, hi, a, x⟩ := by
  have hs : 0 ≤ slack100 f a := by
    cases f <;> simp [slack100] <;> omega
  cases f <;> simp_all [inBand] <;> omega

/-- A larger margin keeps every passing value passing. -/
theorem inBand_mono {f : Family} {m m' : Int} {o : Obs} (h : m ≤ m') (hb : inBand f m o) : inBand f m' o := by
  cases f <;> simp only [inBand] at hb ⊢ <;> omega

/-- A quarantined entry is never gated. -/
theorem skipped_of_quar {e : Freeze.Entry} {ty : String} {o : Obs} (h : e.cls = .quar) :
    status (some e) ty o = .skipped := by simp [status, h]

/-- An unlisted type is never gated. -/
theorem skipped_of_unlisted (ty : String) (o : Obs) : status none ty o = .skipped := rfl

/-- A type with no band never fails. -/
theorem unbanded_not_fail (e : Option Freeze.Entry) {ty : String} (o : Obs) (h : familyOf ty = .unbanded) :
    status e ty o ≠ .fail := by
  cases e with
  | none => simp [status]
  | some e => by_cases hq : e.cls = .quar <;> simp [status, hq, h]

end Fw.Faithful
