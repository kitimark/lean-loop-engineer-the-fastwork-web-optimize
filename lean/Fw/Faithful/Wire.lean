import Lean.Data.Json
import Fw.Faithful.Zone
import Fw.Faithful.Comparable
import Fw.Measure.Wire
/-!
# The op `faithful.verdict` (task faithful-checks)

JSON glue for `Fw.Faithful.zoneVerdict` (namespace `Fw.Wire.Faithful`, so the math view treats it as wire code).

| op | request | reply |
|---|---|---|
| `faithful.comparable` | `a`, `r` (each `{profile, preset, browser, zoneHeightPx, viewport: {width, height, dpr, mobile, touch}, observed?: {width, height}}`) | `comparable` (`Fw.Faithful.comparable a r = none`), `field` (the first failing field, else `null`) |
| `faithful.verdict` | `classes` (A's frozen class table `{type: {class, k, t, tBound?}}`), `a` and `r` (zone lists as in the `zones` of a `measure.zoneBaseline` reply or a stored baseline file: `{id, frames, scrolledPx, types: {type: {lo, hi, base}}}`), `zones`? (ids to judge, default the region `y04000`, `y04500`, `tail`) | `pass`, `failedZones`, `zones` `[{id, present, shape, pass, framesA, framesR, pxA, pxR, failed, tally, cells}]`, `cells` `{type: {family, status, lo, hi, a, r}}` |

`a` supplies the envelope `lo`, `hi` and the median `base`; `r` supplies the median `base` only (its `lo`, `hi` are
reported by the caller). A zone absent from `a` or `r` is `present: false`.
-/
namespace Fw.Wire.Faithful
open Lean Fw.Faithful Fw.Wire.Measure

/-- Decode one zone `{id, frames, scrolledPx, types}` of a baseline. -/
def zbaseOf (j : Json) : Except String ZBase := do
  let cells ← match opt j "types" with
    | some (.obj kvs) => kvs.toArray.toList.mapM fun ⟨ty, v⟩ => do
        pure ({ type := ty, lo := ← asInt s!"types.{ty}.lo" (← field v "lo"), hi := ← asInt s!"types.{ty}.hi" (← field v "hi"),
                base := ← asInt s!"types.{ty}.base" (← field v "base") } : ZCell)
    | _ => throw "field types: expected an object"
  pure { id := ← str j "id", frames := ← nat j "frames", scrolledPx := ← asInt "scrolledPx" (← field j "scrolledPx"), cells := cells }

/-- The wire name of a family. -/
def familyName : Family → String
  | .exact => "exact" | .zero => "zero" | .pct5 => "pct5" | .pct10 => "pct10" | .unbanded => "unbanded"

/-- The wire name of a status. -/
def statusName : Status → String
  | .pass => "pass" | .fail => "fail" | .skipped => "skipped" | .unbanded => "unbanded"

/-- The reply fields of one zone verdict. -/
def zoneJson (a r : List ZBase) (v : ZoneVerdict) : Json :=
  let za := findZ a v.id
  let zr := findZ r v.id
  let cnt (s : Status) : Json := toJson (v.cells.filter (·.status == s)).length
  Json.mkObj [("id", .str v.id), ("present", .bool v.present), ("shape", .bool v.shape), ("pass", .bool v.pass),
    ("framesA", toJson (za.map (·.frames))), ("framesR", toJson (zr.map (·.frames))),
    ("pxA", toJson (za.map (·.scrolledPx))), ("pxR", toJson (zr.map (·.scrolledPx))),
    ("failed", strArr v.failed),
    ("tally", Json.mkObj [("pass", cnt .pass), ("fail", cnt .fail), ("skipped", cnt .skipped), ("unbanded", cnt .unbanded)]),
    ("cells", objOf (v.cells.map fun c =>
      (c.type, Json.mkObj [("family", .str (familyName c.family)), ("status", .str (statusName c.status)),
        ("lo", toJson c.obs.lo), ("hi", toJson c.obs.hi), ("a", toJson c.obs.a), ("r", toJson c.obs.r)])))]

/-- `faithful.verdict`: see the table above. -/
def opVerdict (req : Json) : Except String Reply := do
  let tb ← tableOf "classes" (← field req "classes")
  let a ← (← arr req "a").toList.mapM zbaseOf
  let r ← (← arr req "r").toList.mapM zbaseOf
  let zs ← match opt req "zones" with
    | none => pure regionZones
    | some j => (← asArr "zones" j).toList.mapM (asStr "zones")
  let vs := zs.map (zoneVerdict tb a r)
  pure [("pass", .bool (vs.all (·.pass))), ("failedZones", strArr ((vs.filter (!·.pass)).map (·.id))),
        ("zones", .arr (vs.toArray.map (zoneJson a r)))]

/-- Decode the `Meta` of a baseline: `viewport` is the profile viewport, `observed` (optional) what the page reported. -/
def metaOf (j : Json) : Except String Meta := do
  let vp ← field j "viewport"
  let bool (k : String) : Except String Bool := do
    match (← field vp k).getBool? with
    | .ok b => pure b
    | .error _ => throw s!"field viewport.{k}: expected a boolean"
  let obs : Option Fw.Measure.Viewport.Size ← match opt j "observed" with
    | none => pure none
    | some o => pure (some ⟨← nat o "width", ← nat o "height"⟩)
  pure { profile := ← str j "profile", preset := ← str j "preset", browser := ← str j "browser",
         zoneHeightPx := ← nat j "zoneHeightPx", width := ← nat vp "width", height := ← nat vp "height",
         dpr := ← asRat "viewport.dpr" (← field vp "dpr"), mobile := ← bool "mobile", touch := ← bool "touch", observed := obs }

/-- `faithful.comparable`: see the table above. -/
def opComparable (req : Json) : Except String Reply := do
  let a ← metaOf (← field req "a")
  let r ← metaOf (← field req "r")
  let c := comparable a r
  pure [("comparable", .bool c.isNone), ("field", match c with | some f => .str f | none => .null)]

/-- The ops of this module. -/
def ops : List String := ["faithful.verdict", "faithful.comparable"]

/-- Dispatch a `faithful.*` op (`none` when it is not one). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "faithful.verdict" => some (opVerdict req)
  | "faithful.comparable" => some (opComparable req)
  | _ => none

end Fw.Wire.Faithful
