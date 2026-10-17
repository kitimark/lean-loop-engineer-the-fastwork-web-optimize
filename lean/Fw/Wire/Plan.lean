import Fw.Wire
import Fw.Plan.Core
/-!
# JSON for the plan commands and the board plan

The wire form of `task.define`, `task.drop`, `task.claim`, `task.done` and `milestone.define`: the
same flat event envelope as the other console commands (`key`, `ts`, `actor`, `type`) plus

| type | fields |
|---|---|
| `task.define` | `task`, `title`, `stream`, `owner`, `deps` (required); `milestone`, `evidence` (string or null/missing), `writes`, `devices` (string arrays, missing = `[]`) |
| `task.drop` | `task` |
| `task.claim` | `task`, `agent` |
| `task.done` | `task`, `evidence` |
| `milestone.define` | `milestone`, `title` |

`eventOfJson` decodes these and hands every other type to `Fw.Wire.eventOfJson` (so the existing
commands decode exactly as before). The board plan (`viewJson`) is the `plan` field of the stateful
`console.query` board: `{tasks, milestones, criticalPath, parallelSafe}`.
-/
namespace Fw.Wire.Plan
open Lean Fw.Wire Fw.Plan

/-- An optional string-array field: missing or `null` is `[]`. -/
def strsD (j : Json) (k : String) : Except String (List String) :=
  match opt j k with
  | none => .ok []
  | some v => do (← asArr k v).toList.mapM (asStr k)

/-- Decode a `task.define` payload. -/
def defOfJson (j : Json) : Except String Def := do
  pure { task := ← str j "task", title := ← str j "title", stream := ← str j "stream",
         milestone := ← optStr j "milestone", deps := ← strs j "deps", owner := ← str j "owner",
         writes := ← strsD j "writes", devices := ← strsD j "devices",
         evidence := ← optStr j "evidence" }

/-- Decode a plan command of the given type; `none` when the type is not a plan type. -/
def cmdOfJson (t : String) (j : Json) : Option (Except String Cmd) :=
  match t with
  | "task.define" => some (.define <$> defOfJson j)
  | "task.drop" => some (do pure (.drop (← str j "task")))
  | "task.claim" => some (do pure (.claim (← str j "task") (← str j "agent")))
  | "task.done" => some (do pure (.done (← str j "task") (← str j "evidence")))
  | "milestone.define" => some (do pure (.milestone (← str j "milestone") (← str j "title")))
  | _ => none

/-- Decode an event: plan types here (same envelope order: `key`, `ts`, `actor`, then the body),
every other type by `Fw.Wire.eventOfJson`. -/
def eventOfJson (j : Json) : Except String Fw.Console.Event :=
  match (match str j "type" with | .ok t => cmdOfJson t j | .error _ => none) with
  | none => Fw.Wire.eventOfJson j
  | some c => do
    pure { key := ← str j "key", ts := ← nat j "ts", actor := ← actorOf (← str j "actor"),
           body := .plan (← c) }

/-- A list of strings as a JSON array. -/
def strsJson (l : List String) : Json := .arr (l.toArray.map .str)

/-- The body fields of a plan command (the flat event form, without the envelope). -/
def cmdFields : Cmd → List (String × Json)
  | .define d => [("task", .str d.task), ("title", .str d.title), ("stream", .str d.stream),
      ("milestone", ostr d.milestone), ("deps", strsJson d.deps), ("owner", .str d.owner),
      ("writes", strsJson d.writes), ("devices", strsJson d.devices), ("evidence", ostr d.evidence)]
  | .drop x => [("task", .str x)]
  | .claim x a => [("task", .str x), ("agent", .str a)]
  | .done x e => [("task", .str x), ("evidence", .str e)]
  | .milestone m t => [("milestone", .str m), ("title", .str t)]

/-- Encode a task of the board plan. -/
def taskViewJson (t : TaskView) : Json := Json.mkObj [
  ("id", .str t.id), ("title", .str t.title), ("stream", .str t.stream),
  ("milestone", ostr t.milestone), ("owner", .str t.owner), ("deps", strsJson t.deps),
  ("state", .str t.state.name), ("blockers", strsJson t.blockers), ("agent", ostr t.agent),
  ("evidence", ostr t.evidence)]

/-- Encode a milestone of the board plan. -/
def milestoneViewJson (m : MilestoneView) : Json := Json.mkObj [
  ("id", .str m.id), ("title", .str m.title), ("done", toJson m.done), ("total", toJson m.total)]

/-- Encode the board plan. -/
def viewJson (v : View) : Json := Json.mkObj [
  ("tasks", .arr (v.tasks.toArray.map taskViewJson)),
  ("milestones", .arr (v.milestones.toArray.map milestoneViewJson)),
  ("criticalPath", strsJson v.criticalPath),
  ("parallelSafe", .arr (v.parallelSafe.toArray.map strsJson))]

/-- A board JSON object with the `plan` field added. -/
def withPlan (board : Json) (v : View) : Json := board.setObjVal! "plan" (viewJson v)

end Fw.Wire.Plan
