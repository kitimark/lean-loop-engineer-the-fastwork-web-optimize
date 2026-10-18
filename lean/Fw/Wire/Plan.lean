import Fw.Wire
import Fw.Plan.Core
import Fw.Plan.Incident
/-!
# JSON for the plan commands and the board plan

The wire form of `task.define`, `task.drop`, `task.claim`, `task.done`, `milestone.define`,
`agent.spawn` and `agent.stop`: the
same flat event envelope as the other console commands (`key`, `ts`, `actor`, `type`) plus

| type | fields |
|---|---|
| `task.define` | `task`, `title`, `stream`, `owner`, `deps` (required); `milestone`, `evidence` (string or null/missing), `writes`, `devices`, `needs`, `live` (string arrays, missing = `[]`), `cut` (boolean, missing = `false`), `evidenceOnMain` (boolean, missing or null = `true`: the glue's `git merge-base --is-ancestor <evidence> main`; written only when false) |
| `task.drop` | `task` |
| `task.claim` | `task`, `agent` |
| `task.done` | `task`, `evidence` |
| `milestone.define` | `milestone`, `title` |
| `agent.spawn` | `agent` |
| `agent.stop` | `agent` |

`live` on `task.define` is legacy: new writers omit it (an agent is bound by `agent.spawn` /
`agent.stop`, `Fw.Plan.agentOf`); it is still decoded so old logs replay to the same board.

`eventOfJson` decodes these and hands every other type to `Fw.Wire.eventOfJson` (so the existing
commands decode exactly as before). The board plan (`viewJson`) is the `plan` field of the stateful
`console.query` board: `{tasks, milestones, criticalPath, parallelSafe}`.

The stateless op `plan.incidentLint` (task `incident-lint`, `Fw.Plan.Incident`), dispatched by
`Fw.Wire.Serve.serveLine` through `handle`:

| op | request | reply |
|---|---|---|
| `plan.incidentLint` | `incidents` [ledger records as in the file], `tasks` [{id, evidence?, agent?}] (work graph rows with board state), `commits`? [refs that are commits on main], `files`? [refs that exist], `classes`? [class ids of research/mistakes/ledger.json] | `ok`, `errors`, `warnings`, `incidents` [{id, status, findings [{code, severity, detail}]}] |
-/
namespace Fw.Wire.Plan
open Lean Fw.Wire Fw.Plan

/-- An optional string-array field: missing or `null` is `[]`. -/
def strsD (j : Json) (k : String) : Except String (List String) :=
  match opt j k with
  | none => .ok []
  | some v => do (← asArr k v).toList.mapM (asStr k)

/-- An optional boolean field: missing or `null` is `false`. -/
def boolD (j : Json) (k : String) : Except String Bool :=
  match opt j k with
  | none => .ok false
  | some (.bool b) => .ok b
  | some _ => .error s!"field {k}: expected a boolean"

/-- An optional boolean field that defaults to true: missing or `null` is `true`. -/
def boolT (j : Json) (k : String) : Except String Bool :=
  match opt j k with
  | none | some .null => .ok true
  | some (.bool b) => .ok b
  | some _ => .error s!"field {k}: expected a boolean"

/-- Decode a `task.define` payload. -/
def defOfJson (j : Json) : Except String Def := do
  pure { task := ← str j "task", title := ← str j "title", stream := ← str j "stream",
         milestone := ← optStr j "milestone", deps := ← strs j "deps", owner := ← str j "owner",
         writes := ← strsD j "writes", devices := ← strsD j "devices", needs := ← strsD j "needs",
         evidence := ← optStr j "evidence", cut := ← boolD j "cut", live := ← strsD j "live",
         onMain := ← boolT j "evidenceOnMain" }

/-- Decode a plan command of the given type; `none` when the type is not a plan type. -/
def cmdOfJson (t : String) (j : Json) : Option (Except String Cmd) :=
  match t with
  | "task.define" => some (.define <$> defOfJson j)
  | "task.drop" => some (do pure (.drop (← str j "task")))
  | "task.claim" => some (do pure (.claim (← str j "task") (← str j "agent")))
  | "task.done" => some (do pure (.done (← str j "task") (← str j "evidence")))
  | "milestone.define" => some (do pure (.milestone (← str j "milestone") (← str j "title")))
  | "agent.spawn" => some (do pure (.spawn (← str j "agent")))
  | "agent.stop" => some (do pure (.stop (← str j "agent")))
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
      ("writes", strsJson d.writes), ("devices", strsJson d.devices), ("needs", strsJson d.needs),
      ("evidence", ostr d.evidence)]
      ++ (if d.cut then [("cut", .bool true)] else [])
      ++ (if d.live.isEmpty then [] else [("live", strsJson d.live)])
      ++ (if d.onMain then [] else [("evidenceOnMain", .bool false)])
  | .drop x => [("task", .str x)]
  | .claim x a => [("task", .str x), ("agent", .str a)]
  | .done x e => [("task", .str x), ("evidence", .str e)]
  | .milestone m t => [("milestone", .str m), ("title", .str t)]
  | .spawn a | .stop a => [("agent", .str a)]

/-- Encode a task of the board plan. -/
def taskViewJson (t : TaskView) : Json := Json.mkObj [
  ("id", .str t.id), ("title", .str t.title), ("stream", .str t.stream),
  ("milestone", ostr t.milestone), ("owner", .str t.owner), ("deps", strsJson t.deps),
  ("needs", strsJson t.needs), ("lane", .str t.lane.name), ("state", .str t.state.name), ("blockers", strsJson t.blockers), ("agent", ostr t.agent),
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

/-! ## plan.incidentLint (task incident-lint) -/

/-- An optional string field: missing or `null` is the empty string. -/
def strE (j : Json) (k : String) : Except String String :=
  match opt j k with
  | none => .ok ""
  | some v => asStr k v

open Fw.Plan.Incident in
/-- Decode one ledger record (fields the lint does not read are ignored; a `status` key, even `null`,
sets `hasStatus`). A missing or `null` `fix` has no fix task and no `also` tasks. The Lean fields
(`leanVerdict`, `leanReason`, `hardening`, `empiricalCheck`, `mistakeClass`) are optional strings. -/
def incidentOfJson (j : Json) : Except String Incident := do
  let ev ← (← (match opt j "evidence" with | none => pure #[] | some v => asArr "evidence" v)).toList.mapM
    fun e => do pure ({ kind := ← strE e "kind", ref := ← strE e "ref" } : Ev)
  let (fixTask, also) ← match opt j "fix" with
    | none => pure (none, [])
    | some f => do pure (← optStr f "task", ← strsD f "also")
  pure { id := ← str j "id", cause := ← strE j "cause", evidence := ev, repro := ← optStr j "repro",
         fixTask, also, regression := ← optStr j "regression",
         hasStatus := (j.getObjVal? "status").toOption.isSome,
         leanVerdict := ← optStr j "leanVerdict", leanReason := ← optStr j "leanReason",
         hardening := ← optStr j "hardening", empiricalCheck := ← optStr j "empiricalCheck",
         mistakeClass := ← optStr j "mistakeClass" }

/-- Decode a task row of `plan.incidentLint`: id, evidence and agent (string or null/missing). -/
def incidentTaskOfJson (t : Json) : Except String Task := do
  pure { id := ← str t "id", title := "", stream := "", milestone := none, deps := [], owner := "",
         writes := [], devices := [], needs := [], evidence := ← optStr t "evidence",
         agent := ← optStr t "agent" }

open Fw.Plan.Incident in
/-- `plan.incidentLint`: `Fw.Plan.Incident.lintAll` over the ledger records and the collected facts. -/
def opIncidentLint (req : Json) : Except String Reply := do
  let l ← (← arr req "incidents").toList.mapM incidentOfJson
  let ts ← (← arr req "tasks").toList.mapM incidentTaskOfJson
  let F : Facts := { tasks := ts, commits := ← strsD req "commits", files := ← strsD req "files",
                     classes := ← strsD req "classes" }
  let rs := lintAll F l
  let fs := rs.flatMap (·.findings)
  pure [("ok", .bool (okAll F l)), ("errors", toJson (fs.filter (·.code.isError)).length),
        ("warnings", toJson (fs.filter (!·.code.isError)).length),
        ("incidents", .arr (rs.toArray.map fun r => Json.mkObj [
          ("id", .str r.id), ("status", .str r.status.name),
          ("findings", .arr (r.findings.toArray.map fun f => Json.mkObj [
            ("code", .str f.code.name), ("severity", .str f.code.severity), ("detail", .str f.detail)]))]))]

/-- The stateless ops of this module. -/
def ops : List String := ["plan.incidentLint"]

/-- Dispatch one of these ops (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "plan.incidentLint" => some (opIncidentLint req)
  | _ => none

end Fw.Wire.Plan
