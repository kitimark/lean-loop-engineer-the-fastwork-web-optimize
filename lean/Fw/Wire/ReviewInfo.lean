import Fw.Ops.Wire
import Fw.Console.ReviewInfo
/-!
# JSON for the review information panel (`console.reviewInfo`)

| op | request | reply |
|---|---|---|
| `console.reviewInfo` | `flag` (`part:variant`) | `ok`; with `ok` false only `reason` (no table is written for the flag). Otherwise `flag`, `summary`, `gains` [{metric, engine, push, viewport, before?, after? ([low, high]), noise, unit, status {kind (measured, modelled, unknown), runs?, aa?, theorem?, golden?, why?}, shown {kind (gain, noSaving, inNoise, overlap, worse, unknown), n?, text}}], `excerpts` [{id, side, file, anchor, span, note}], `mechanism` [text], `sources` [{claim, status, cite}], `formulas` [{id, tex, says, decl, file, line, kind}] (`Fw.Console.ReviewInfo`) |
| `console.reviewExcerpt` | `flag`, `excerpt` (an excerpt id), `lines` [text] (the excerpt's file, split at newlines) | `ok`; with `ok` true `first`, `last` (1-based); with `ok` false `reason` (`Fw.Console.ReviewInfo.locate`) |
-/
namespace Fw.Wire.ReviewInfo
open Lean Fw.Wire.Ops Fw.Console.ReviewInfo

def rangeJson : Option (Nat × Nat) → Json
  | some (lo, hi) => .arr #[toJson lo, toJson hi]
  | none => .null

def statusJson : Status → Json
  | .measured runs aa => Json.mkObj [("kind", "measured"), ("runs", toJson runs), ("aa", toJson aa)]
  | .modelled t g => Json.mkObj [("kind", "modelled"), ("theorem", t), ("golden", g)]
  | .unknown w => Json.mkObj [("kind", "unknown"), ("why", w)]

def shownJson : Shown → Json
  | .gain n => Json.mkObj [("kind", "gain"), ("n", toJson n), ("text", s!"{n} fewer")]
  | .noSaving => Json.mkObj [("kind", "noSaving"), ("text", "no saving")]
  | .inNoise => Json.mkObj [("kind", "inNoise"), ("text", "not shown (inside A/A noise)")]
  | .overlap => Json.mkObj [("kind", "overlap"), ("text", "no difference shown (ranges overlap)")]
  | .worse n => Json.mkObj [("kind", "worse"), ("n", toJson n), ("text", s!"{n} more")]
  | .unknown => Json.mkObj [("kind", "unknown"), ("text", "unknown")]

def gainJson (g : Gain) : Json :=
  Json.mkObj [("metric", g.metric), ("engine", g.engine), ("push", g.push), ("viewport", g.viewport),
    ("before", rangeJson g.before), ("after", rangeJson g.after), ("noise", toJson g.noise), ("unit", g.unit),
    ("status", statusJson g.status), ("shown", shownJson g.shown)]

def excerptJson (e : Excerpt) : Json :=
  Json.mkObj [("id", e.id), ("side", e.side), ("file", e.file), ("anchor", e.anchor), ("span", toJson e.span), ("note", e.note)]

def sourceJson (s : Source) : Json := Json.mkObj [("claim", s.claim), ("status", s.status), ("cite", s.cite)]

def formulaJson (f : Formula) : Json :=
  Json.mkObj [("id", f.id), ("tex", f.tex), ("says", f.says), ("decl", f.decl), ("file", f.file), ("line", toJson f.line),
    ("kind", f.kind)]

def opReviewInfo (req : Json) : Except String Reply := do
  let flag ← str req "flag"
  match infoFor flag with
  | none => pure [("ok", .bool false), ("reason", .str s!"no information table is written for {flag}")]
  | some (gains, excerpts, mechanism, sources, formulas) =>
    pure [("ok", .bool true), ("flag", .str flag), ("summary", .str (earnSummary ())),
      ("gains", .arr (gains.map gainJson).toArray), ("excerpts", .arr (excerpts.map excerptJson).toArray),
      ("mechanism", toJson mechanism), ("sources", .arr (sources.map sourceJson).toArray),
      ("formulas", .arr (formulas.map formulaJson).toArray)]

def opReviewExcerpt (req : Json) : Except String Reply := do
  let flag ← str req "flag"
  let id ← str req "excerpt"
  let lines ← (← arr req "lines").toList.mapM (asStr "lines")
  let some (_, excerpts, _) := infoFor flag | pure [("ok", .bool false), ("reason", .str s!"no information table is written for {flag}")]
  let some e := excerpts.find? (·.id == id) | pure [("ok", .bool false), ("reason", .str s!"{flag} has no excerpt {id}")]
  match locate lines e.anchor e.span with
  | .at f l => pure [("ok", .bool true), ("first", toJson f), ("last", toJson l)]
  | loc => pure [("ok", .bool false), ("reason", .str ((loc.reason e.file e.anchor).getD ""))]

end Fw.Wire.ReviewInfo
