import Fw.Ops.Wire
import Fw.Console.Land
import Fw.Console.Self
import Fw.Plan.Trailer
/-!
# JSON for the console's own rules (`console.landReadiness`, `console.actor`, `plan.trailers`)

Stateless ops, dispatched by `Fw.Wire.handleCore` (this module cannot import `Fw.Wire`, which
imports it, so it decodes the card fields it needs itself).

| op | request | reply |
|---|---|---|
| `console.landReadiness` | `card` {id, needsDevice, owner?, approved?, head?, screenAt?, reviewAt?, deviceAt?, landed?} (a board or reducer card; other fields ignored), `sha` | `ready`, `needs` (`approve`/`build`/`screen`/`review`/`device`, in that order), `refusal` (the `card.land_request` refusal at `sha`, or null) |
| `console.actor` | `source`? (`alert`/`claim`/`build`/`landed`/`taskDone`; missing = all) | `sources` [{source, actor, type, allowed}] |
| `plan.trailers` | `commits` [{sha, body}] (first-parent, newest first), `tasks` [{id, state}] (done iff state is `done`) | `done` [{task, evidence}] (the `task.done` facts, oldest first), `verdicts` [{task, sha, verdict}] (`done`/`unknown`/`alreadyDone`/`duplicate`, oldest first) |
-/
namespace Fw.Wire.Console
open Lean Fw.Wire.Ops

/-! ## console.landReadiness -/

/-- An optional nullable string field (wrong type refused). -/
def optStr (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asStr k v

/-- Decode the card fields land readiness reads (missing optional fields take the card defaults). -/
def cardOf (j : Json) : Except String Fw.Console.Card := do
  pure { id := ← str j "id", owner := ← strD j "owner" "", needsDevice := ← asBool "needsDevice" (← field j "needsDevice"),
         approved := ← boolD j "approved" false, head := ← optStr j "head",
         screenAt := ← optStr j "screenAt", reviewAt := ← optStr j "reviewAt",
         deviceAt := ← optStr j "deviceAt", landed := ← boolD j "landed" false }

open Fw.Console.Land in
/-- `console.landReadiness`: what card `card` still needs before it may land, and the refusal a
`card.land_request` at `sha` would get (`Fw.Console.Land`). -/
def opLandReadiness (req : Json) : Except String Reply := do
  let c ← cardOf (← field req "card")
  let sha ← str req "sha"
  pure [("ready", .bool (Fw.Console.ready c)),
        ("needs", .arr ((landNeeds c).toArray.map fun n => .str n.name)),
        ("refusal", ostr (landRefusal c sha))]

/-! ## console.actor -/

open Fw.Console.Self in
/-- One source as JSON. -/
def sourceJson (s : Source) : Json := Json.mkObj [
  ("source", .str s.name), ("actor", .str (actor s).name), ("type", .str (evType s).name),
  ("allowed", .bool (Fw.Console.may (actor s) (evType s)))]

open Fw.Console.Self in
/-- `console.actor`: the actor and event type of each of console-api's own event sources
(`Fw.Console.Self`); an unknown source is refused. -/
def opActor (req : Json) : Except String Reply := do
  let ss ← match ← optStr req "source" with
    | none => pure sources
    | some n => match Source.ofName n with
      | some s => pure [s]
      | none => throw s!"field source: unknown source {n}"
  pure [("sources", .arr (ss.toArray.map sourceJson))]

/-! ## plan.trailers -/

open Fw.Plan.Trailer in
/-- `plan.trailers`: which `Task: <id>` trailer on which first-parent commit marks which task
done (`Fw.Plan.Trailer.facts`), and the verdict of every trailer (`verdicts`). -/
def opTrailers (req : Json) : Except String Reply := do
  let cs ← (← arr req "commits").toList.mapM fun c => do
    pure ({ sha := ← str c "sha", body := ← str c "body" } : Commit)
  let ts ← (← arr req "tasks").toList.mapM fun t => do
    pure (← str t "id", (← str t "state") == "done")
  pure [("done", .arr ((facts ts cs).toArray.map fun (x, s) =>
            Json.mkObj [("task", .str x), ("evidence", .str s)])),
        ("verdicts", .arr ((verdicts ts cs).toArray.map fun (x, s, v) =>
            Json.mkObj [("task", .str x), ("sha", .str s), ("verdict", .str v.name)]))]

/-! ## Dispatch -/

/-- The ops of this module. -/
def ops : List String := ["console.landReadiness", "console.actor", "plan.trailers"]

/-- Dispatch one of these ops (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "console.landReadiness" => some (opLandReadiness req)
  | "console.actor" => some (opActor req)
  | "plan.trailers" => some (opTrailers req)
  | _ => none

end Fw.Wire.Console
