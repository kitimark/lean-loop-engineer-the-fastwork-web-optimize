import Fw.Ops.Wire
import Fw.Console.ReviewInfo
/-!
# JSON for the review information panel (`console.reviewInfo`)

| op | request | reply |
|---|---|---|
| `console.reviewInfo` | `flag` (`part:variant`) | `ok`; with `ok` false only `reason` (no table is written for the flag). Otherwise `flag`, `summary`, `gains` [{metric, engine, push, viewport, before?, after? ([low, high]), noise, unit, status {kind (measured, modelled, unknown), runs?, aa?, theorem?, golden?, why?}, shown {kind (gain, noSaving, inNoise, worse, unknown), n?, text}}], `excerpts` [{id, side, file, first, last, anchor, note}], `mechanism` [text], `sources` [{claim, status, cite}], `formulas` [{id, tex, says, decl, file, line, kind}] (`Fw.Console.ReviewInfo`) |
-/
namespace Fw.Wire.ReviewInfo
open Lean Fw.Wire.Ops Fw.Console.ReviewInfo

/-- A range as JSON. -/
def rangeJson : Option (Nat × Nat) → Json
  | some (lo, hi) => .arr #[toJson lo, toJson hi]
  | none => .null

/-- The status of a row as JSON. -/
def statusJson : Status → Json
  | .measured runs aa => Json.mkObj [("kind", "measured"), ("runs", toJson runs), ("aa", toJson aa)]
  | .modelled t g => Json.mkObj [("kind", "modelled"), ("theorem", t), ("golden", g)]
  | .unknown w => Json.mkObj [("kind", "unknown"), ("why", w)]

/-- What a row shows, as JSON: the kind, the count and the words the panel prints. -/
def shownJson : Shown → Json
  | .gain n => Json.mkObj [("kind", "gain"), ("n", toJson n), ("text", s!"{n} fewer")]
  | .noSaving => Json.mkObj [("kind", "noSaving"), ("text", "no saving")]
  | .inNoise => Json.mkObj [("kind", "inNoise"), ("text", "not shown (inside A/A noise)")]
  | .worse n => Json.mkObj [("kind", "worse"), ("n", toJson n), ("text", s!"{n} more")]
  | .unknown => Json.mkObj [("kind", "unknown"), ("text", "unknown")]

/-- A gain row as JSON. -/
def gainJson (g : Gain) : Json :=
  Json.mkObj [("metric", g.metric), ("engine", g.engine), ("push", g.push), ("viewport", g.viewport),
    ("before", rangeJson g.before), ("after", rangeJson g.after), ("noise", toJson g.noise), ("unit", g.unit),
    ("status", statusJson g.status), ("shown", shownJson (shownOf g.noise g.delta))]

/-- An excerpt as JSON. -/
def excerptJson (e : Excerpt) : Json :=
  Json.mkObj [("id", e.id), ("side", e.side), ("file", e.file), ("first", toJson e.first), ("last", toJson e.last),
    ("anchor", e.anchor), ("note", e.note)]

/-- A source as JSON. -/
def sourceJson (s : Source) : Json := Json.mkObj [("claim", s.claim), ("status", s.status), ("cite", s.cite)]

/-- A formula as JSON. -/
def formulaJson (f : Formula) : Json :=
  Json.mkObj [("id", f.id), ("tex", f.tex), ("says", f.says), ("decl", f.decl), ("file", f.file), ("line", toJson f.line),
    ("kind", f.kind)]

/-- `console.reviewInfo` (`Fw.Console.ReviewInfo.infoFor`). -/
def opReviewInfo (req : Json) : Except String Reply := do
  let flag ← str req "flag"
  match infoFor flag with
  | none => pure [("ok", .bool false), ("reason", .str s!"no information table is written for {flag}")]
  | some (gains, excerpts, mechanism, sources, formulas) =>
    pure [("ok", .bool true), ("flag", .str flag), ("summary", .str (earnSummary ())),
      ("gains", .arr (gains.map gainJson).toArray), ("excerpts", .arr (excerpts.map excerptJson).toArray),
      ("mechanism", toJson mechanism), ("sources", .arr (sources.map sourceJson).toArray),
      ("formulas", .arr (formulas.map formulaJson).toArray)]

end Fw.Wire.ReviewInfo
