import Fw.Ops.Wire
import Fw.Console.Report
import Fw.Wire.Review
/-!
# JSON for the experiment reports (`console.report`)

| op | request | reply |
|---|---|---|
| `console.report` | `reports` [report], `steps` [{id, answer?, open}] (the board steps, as `console.review`), `answer`? {id, word, comment?} | `items` [{id, step, title, body, state (unposted, open, approve, hold, reject, closed), post}] for the reports Lean shows, `invalid` [{index, id?, reason}] for the others, `options` (approve, hold, reject), `answer` (null, or {ok, reason?, step?, word?, feedback? ({flag, text})}) (`Fw.Console.Report`) |

A report is `{id, proposal, title, arms [{name, search}], lanes [{name, rows [{metric, unit, cells [{arm, value (number or text), tag}]}], layers? [{layer, verdict, tag}]}], strips?, recommendation {word, why}}`
and a tag is `{kind: "measured", run}` or `{kind: "inferred", why}`; a missing tag is read as no tag and refused.
-/
namespace Fw.Wire.Report
open Lean Fw.Wire.Ops Fw.Console.Report

/-- A tag; a missing or null tag is `none`, a tag of another kind is an error. -/
def tagOf (j : Json) : Except String (Option Tag) :=
  match opt j "tag" with
  | none => pure none
  | some t => do
    match ← str t "kind" with
    | "measured" => pure (some (.measured (← strD t "run" "")))
    | "inferred" => pure (some (.inferred (← strD t "why" "")))
    | k => throw s!"a tag is measured or inferred, not {k}"

/-- A value: a JSON number or a string. -/
def valueOf (j : Json) : Except String String :=
  match opt j "value" with
  | some (.num n) => pure n.toString
  | some (.str s) => pure s
  | _ => throw "field value: expected a number or a string"

/-- One cell. -/
def cellOf (j : Json) : Except String Cell := do
  pure { arm := ← str j "arm", value := ← valueOf j, tag := ← tagOf j }

/-- One row. -/
def rowOf (j : Json) : Except String Row := do
  pure { metric := ← str j "metric", unit := ← strD j "unit" "", cells := ← (← arrD j "cells").mapM cellOf }

/-- One layer verdict. -/
def layerOf (j : Json) : Except String LayerVerdict := do
  pure { layer := ← str j "layer", verdict := ← str j "verdict", tag := ← tagOf j }

/-- One lane. -/
def laneOf (j : Json) : Except String Lane := do
  pure { name := ← str j "name", rows := ← (← arrD j "rows").mapM rowOf, layers := ← (← arrD j "layers").mapM layerOf }

/-- One arm. -/
def armOf (j : Json) : Except String Arm := do
  pure { name := ← str j "name", search := ← strD j "search" "" }

/-- A report. -/
def reportOf (j : Json) : Except String Report := do
  let rec_ ← field j "recommendation"
  pure { id := ← str j "id", proposal := ← str j "proposal", title := ← str j "title",
         arms := ← (← arrD j "arms").mapM armOf, lanes := ← (← arrD j "lanes").mapM laneOf,
         strips := (match opt j "strips" with | some (.str s) => some s | _ => none),
         recommendation := { word := ← str rec_ "word", why := ← str rec_ "why" } }

/-- An item of a shown report. -/
def itemJson (rs : List Fw.Console.Review.Rec) (r : Report) : Json :=
  Json.mkObj [("id", .str r.id), ("step", .str (stepId r.id)), ("title", .str (title r)), ("body", .str (body r)),
    ("state", .str (stateOf rs r.id).word), ("post", .bool (needsPost rs r.id))]

/-- `console.report` (`Fw.Console.Report.refusal`, `accept`). -/
def opReport (req : Json) : Except String Reply := do
  let js ← arrD req "reports"
  let rs ← Fw.Wire.Review.recs req
  let parsed := js.map fun j => reportOf j
  let shown : List Report := parsed.filterMap fun p => match p with
    | .ok r => if (refusal r).isNone then some r else none
    | .error _ => none
  let invalid : List Json := ((parsed.zip js).zipIdx).filterMap fun ((p, j), i) =>
    let idj := (match opt j "id" with | some (.str s) => [("id", Json.str s)] | _ => [])
    match p with
    | .error e => some (Json.mkObj ([("index", toJson i), ("reason", .str e)] ++ idj))
    | .ok r => (refusal r).map fun e => Json.mkObj ([("index", toJson i), ("reason", .str e)] ++ idj)
  let ans ← (match opt req "answer" with
    | none => pure Json.null
    | some a => do
      let id ← str a "id"
      let w ← str a "word"
      let c ← strD a "comment" ""
      pure (if !(shown.any (·.id == id)) then Json.mkObj [("ok", .bool false), ("reason", .str "no such report")]
        else match accept rs id w c with
          | .ok p => Json.mkObj ([("ok", .bool true), ("step", .str p.step), ("word", .str p.answer.word)] ++
              (match p.feedback with
                | some (f, t) => [("feedback", Json.mkObj [("flag", .str f), ("text", .str t)])]
                | none => []))
          | .error e => Json.mkObj [("ok", .bool false), ("reason", .str e)]))
  pure [("items", .arr (shown.map (itemJson rs)).toArray), ("invalid", .arr invalid.toArray),
    ("options", toJson options), ("answer", ans)]

end Fw.Wire.Report
