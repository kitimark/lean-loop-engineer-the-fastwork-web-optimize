import Fw.Wire
import Fw.Plan.Core
import Fw.Plan.Incident
import Fw.Plan.Overlap
import Fw.Plan.ReviewReady
import Fw.Plan.Polish
import Fw.Ops.SpawnGuard
/-!
# JSON for the plan commands and the board plan

The wire form of `task.define`, `task.drop`, `task.claim`, `task.done`, `milestone.define`,
`agent.spawn`, `agent.stop`, `agent.label`, and the outcome marks `task.handback`, `task.integrate`, `task.park`,
`task.unpark` (task `task-state-truth`): the
same flat event envelope as the other console commands (`key`, `ts`, `actor`, `type`) plus

| type | fields |
|---|---|
| `task.define` | `task`, `title`, `stream`, `owner`, `deps` (required); `milestone`, `evidence` (string or null/missing), `writes`, `devices`, `needs`, `live` (string arrays, missing = `[]`), `cut` (boolean, missing = `false`), `evidenceOnMain` (boolean, missing or null = `true`: the glue's `git merge-base --is-ancestor <evidence> main`; written only when false) |
| `task.drop` | `task` |
| `task.claim` | `task`, `agent`; `at` (claim time, ms; missing or null = the event's `ts`) |
| `task.done` | `task`, `evidence` |
| `milestone.define` | `milestone`, `title` |
| `agent.spawn` | `agent`; `at` (when the agent was seen, ms; missing or null = the event's `ts`) |
| `agent.stop` | `agent`; `at` (when the agent ended, ms; missing or null = the event's `ts`) |
| `agent.label` | `agent` (a life key: an agent id, a run key `wf:<run>` or a spawn guard's obs key), `name` (the name it is shown and bound under) |
| `task.handback` | `task`, `agent`; `tip` (string or null/missing) |
| `task.integrate` | `task`, `branch`, `tip` |
| `task.park` | `task`, `reason` |
| `task.unpark` | `task` |

A board task carries `state` (one of `Fw.Plan.TState.name`, `quiet` included: a live bound key not
seen within the quiet limit), `since` (when its running agent was last seen, ms: `Fw.Plan.seenAt`; for
a quiet task the last-seen time of its live keys: `Fw.Plan.quietOf`; else null), `keys`
(the live life keys of its agent with their last-seen times, `[{key, at}]`: `Fw.Plan.liveKeys`) and
`outcome`: null, or `{kind: "handedBack", agent, tip}`,
`{kind: "integrated", branch, tip}`, `{kind: "parked", reason}` (`Fw.Plan.outcomeOf`).

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
| `plan.reviewReady` | `items` [{id, status, evidence}], `runs` [{id, state}] (missing = `[]`), `task` (the task id, missing = blank), `dry` (the `VERDICT` line of `fw land --dry`, missing = blank) (task `review-flow-v2`, `Fw.Plan.ReviewReady`) | `ready` (`review`, `dispatch`, `wait`, `returnToBuilder`) |
| `plan.reviewVerdict` | `severities` [word] (`blocker`, `fix-before-land`, `follow-up`; any other word is a blocker), `audited`? [bool: the medium-only audit is done] | `verdict` (`accept`, `refuse`), `recheck` [bool: the verdict used is accept and a `fix-before-land` finding is present, so the checker re-checks], `blockers`, `fixes` [counts] |
| `plan.polishPlan` | `gen`, `paths`, `edited` [paths] (missing = `[]`), `dirtyBefore`? [paths dirty at plan time; dropped from `paths` and `edited`; missing = `[]`], `heads`? [{path, head}] (first lines; a generator stamp makes the path skip) (`Fw.Plan.Polish`, `dirty_never_scoped`) | `classes` [{path, class, mark}], `stages`, `scopes` {comments, prose}, `keep`, `restore`, `left` [edited paths that were dirty at plan time] |
| `plan.polishHunks` | `diff` [{path, spans [{start, len}]}] (new-side hunks of the branch diff, merge-base to head, `-U0`), `edits` [{path, spans}] (old-side hunks of the uncommitted edits against head), `main` [paths dirty in the main checkout] (`Fw.Plan.Polish.admitted`, `relOk`, `blocked`) | `ranges` [{path, ranges [{lo, hi}]}], `edits` [{path, pathOk, kept [bool per span]}], `blocked` |
| `plan.polishSettle` | `before` [untracked paths before the polish stage], `dirtyBefore`? [tracked paths dirty at plan time; missing = `[]`], `dirty` [tracked paths differing from HEAD], `untracked` [untracked paths now] (`Fw.Plan.Polish.settle`) | `restore` [dirty paths that were clean at plan time, to restore from HEAD], `remove` [untracked paths created since `before`] |
| `plan.polishWalk` | `head` [lines of the HEAD file], `hunks` [{target, oldLen, new [lines], keep}] in ascending order (`Fw.Plan.Polish.walk`) | `lines` [the file: HEAD with exactly the kept hunks applied] |
| `plan.polishCuts` | `gen` [paths], `heads`?, `docs` [{path, text}], `cuts` [{path, old, new}] (`Fw.Plan.Polish.applyAll`) | `cuts` [{path, old, verdict, missing}], `docs` [{path, text, changed}] |
| `plan.roster` | (none) | `roles` [{name, runsAs, edits}]: `Fw.Ops.SpawnGuard.prodRoles` |
| `plan.overlap` | `rows` [{id, writes}] (work graph), `running` [task ids], `candidate`? [task id], `override`? [reason] (task `spawn-write-overlap`, `Fw.Plan.Overlap`) | `verdict` (`clear`, `refused`, `overridden`, `unknown`), `conflicts` [{a, b, ga, gb}], `unknown` [ids] |
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

/-- An optional natural-number field: missing or `null` is the default `d`. -/
def natD (j : Json) (k : String) (d : Nat) : Except String Nat :=
  match opt j k with
  | none => .ok d
  | some v => match v.getNat? with
    | .ok n => .ok n
    | .error _ => .error s!"field {k}: expected a non-negative integer"

/-- Decode a plan command of the given type; `none` when the type is not a plan type. The time of
`task.claim`, `agent.spawn` and `agent.stop` is `at`, or the event's `ts` when `at` is missing. -/
def cmdOfJson (t : String) (j : Json) (ts : Nat) : Option (Except String Cmd) :=
  match t with
  | "task.define" => some (.define <$> defOfJson j)
  | "task.drop" => some (do pure (.drop (← str j "task")))
  | "task.claim" => some (do pure (.claim (← str j "task") (← str j "agent") (← natD j "at" ts)))
  | "task.done" => some (do pure (.done (← str j "task") (← str j "evidence")))
  | "milestone.define" => some (do pure (.milestone (← str j "milestone") (← str j "title")))
  | "agent.spawn" => some (do pure (.spawn (← str j "agent") (← natD j "at" ts)))
  | "agent.stop" => some (do pure (.stop (← str j "agent") (← natD j "at" ts)))
  | "agent.label" => some (do pure (.label (← str j "agent") (← str j "name")))
  | "task.handback" => some (do pure (.handback (← str j "task") (← str j "agent") (← optStr j "tip")))
  | "task.integrate" =>
    some (do pure (.integrate (← str j "task") (← str j "branch") (← str j "tip")))
  | "task.park" => some (do pure (.park (← str j "task") (← str j "reason")))
  | "task.unpark" => some (do pure (.unpark (← str j "task")))
  | _ => none

/-- Decode an event: plan types here (same envelope order: `key`, `ts`, `actor`, then the body),
every other type by `Fw.Wire.eventOfJson`. -/
def eventOfJson (j : Json) : Except String Fw.Console.Event :=
  let ts := (nat j "ts").toOption.getD 0
  match (match str j "type" with | .ok t => cmdOfJson t j ts | .error _ => none) with
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
  | .claim x a n => [("task", .str x), ("agent", .str a), ("at", toJson n)]
  | .done x e => [("task", .str x), ("evidence", .str e)]
  | .milestone m t => [("milestone", .str m), ("title", .str t)]
  | .spawn a n | .stop a n => [("agent", .str a), ("at", toJson n)]
  | .label k a => [("agent", .str k), ("name", .str a)]
  | .handback x a p => [("task", .str x), ("agent", .str a), ("tip", ostr p)]
  | .integrate x b p => [("task", .str x), ("branch", .str b), ("tip", .str p)]
  | .park x r => [("task", .str x), ("reason", .str r)]
  | .unpark x => [("task", .str x)]

/-- Encode an outcome mark of a board task (null when none). -/
def markJson : Option Mark → Json
  | none => .null
  | some (.handedBack a p) => Json.mkObj [("kind", .str "handedBack"), ("agent", .str a), ("tip", ostr p)]
  | some (.integrated b p) => Json.mkObj [("kind", .str "integrated"), ("branch", .str b), ("tip", .str p)]
  | some (.parked r) => Json.mkObj [("kind", .str "parked"), ("reason", .str r)]

/-- Encode a task of the board plan. -/
def taskViewJson (t : TaskView) : Json := Json.mkObj [
  ("id", .str t.id), ("title", .str t.title), ("stream", .str t.stream),
  ("milestone", ostr t.milestone), ("owner", .str t.owner), ("deps", strsJson t.deps),
  ("needs", strsJson t.needs), ("lane", .str t.lane.name), ("state", .str t.state.name), ("blockers", strsJson t.blockers), ("agent", ostr t.agent),
  ("since", match t.since with | none => .null | some n => toJson n),
  ("keys", .arr (t.keys.toArray.map fun (k, n) => Json.mkObj [("key", .str k), ("at", toJson n)])),
  ("evidence", ostr t.evidence), ("outcome", markJson t.outcome)]

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

open Fw.Plan.Overlap in
/-- `plan.overlap`: `Fw.Plan.Overlap.verdict` and `conflicts` over the graph rows and the running task ids. -/
def opOverlap (req : Json) : Except String Reply := do
  let rows ← (← arr req "rows").toList.mapM fun r => do
    pure ({ id := ← str r "id", writes := ← strsD r "writes" } : Row)
  let running ← strsD req "running"
  let cand ← optStr req "candidate"
  let ov ← optStr req "override"
  pure [("verdict", .str (verdict rows running cand ov).name),
        ("conflicts", .arr ((conflicts rows running cand).toArray.map fun c => Json.mkObj [
          ("a", .str c.a), ("b", .str c.b), ("ga", .str c.ga), ("gb", .str c.gb)])),
        ("unknown", strsJson (unknownIds rows running cand))]

open Fw.Plan.ReviewReady in
/-- `plan.reviewReady`: `Fw.Plan.ReviewReady.reviewReady` over the report items, the run states and the dry line. -/
def opReviewReady (req : Json) : Except String Reply := do
  let items ← (← arr req "items").toList.mapM fun r => do
    pure ({ id := ← str r "id", status := ← str r "status", evidence := ← str r "evidence" } : Item)
  let runs ← ((← match opt req "runs" with | none => pure #[] | some v => asArr "runs" v)).toList.mapM fun r => do
    pure ({ id := ← str r "id", state := ← str r "state" } : Run)
  let dry := (← optStr req "dry").getD ""
  let task := (← optStr req "task").getD ""
  pure [("ready", .str (reviewReady task items runs dry).name)]

open Fw.Plan.ReviewReady in
/-- `plan.reviewVerdict`: `verdictOf` (audited) or `strictVerdict` (the interim rule) over the severity words. -/
def opReviewVerdict (req : Json) : Except String Reply := do
  let fs := (← strsD req "severities").map Sev.ofString
  let audited ← boolD req "audited"
  let v := if audited then verdictOf fs else strictVerdict fs
  pure [("verdict", .str v.name), ("recheck", .bool (recheck v fs)),
        ("blockers", toJson (fs.filter (· == .blocker)).length),
        ("fixes", toJson (fs.filter (· == .fixBeforeLand)).length)]

/-- The optional `heads` field of the polish ops: [{path, head}], the first line of each file. -/
def heads (req : Json) : Except String (List (String × String)) := do
  (← match opt req "heads" with | none => pure #[] | some v => asArr "heads" v).toList.mapM fun h => do
    pure (← str h "path", ← str h "head")

open Fw.Plan.Polish in
/-- `plan.polishPlan`: the class and comment mark of each path, the stages that run, their scopes, and which edited paths are kept. -/
def opPolishPlan (req : Json) : Except String Reply := do
  let gen := genOf (← strsD req "gen") (← heads req)
  let dirtyBefore ← strsD req "dirtyBefore"
  let ps ← strsD req "paths"
  let ed0 ← strsD req "edited"
  let ps := undirty dirtyBefore ps
  let ed := undirty dirtyBefore ed0
  pure [("classes", .arr (ps.toArray.map fun p => Json.mkObj [("path", .str p), ("class", .str (classify gen p).name),
          ("mark", match mark p with | some m => .str m | none => .null)])),
        ("stages", strsJson ((stages gen ps).map (·.name))),
        ("scopes", Json.mkObj [("comments", strsJson (scope gen .comments ps)), ("prose", strsJson (scope gen .prose ps))]),
        ("keep", strsJson (ed.filter (keeps gen ps))), ("restore", strsJson (ed.filter (!keeps gen ps ·))),
        ("left", strsJson (ed0.filter dirtyBefore.contains)),
        ("protected", strsJson (ps.filter protectedPath))]

open Fw.Plan.Polish in
/-- `plan.polishCuts`: each cut judged in order against its file's text (`applyAll`), and each file's text after the applied cuts. -/
def opPolishCuts (req : Json) : Except String Reply := do
  let gen := genOf (← strsD req "gen") (← heads req)
  let docs ← (← arr req "docs").toList.mapM fun d => do pure (← str d "path", ← str d "text")
  let cuts ← (← arr req "cuts").toList.mapM fun c => do
    pure ({ path := ← str c "path", old := ← str c "old", new := ← str c "new" } : Cut)
  let paths := (docs.map (·.1) ++ cuts.map (·.path)).eraseDups
  let per := paths.map fun p =>
    let mine := cuts.filter (·.path == p)
    (p, mine, applyAll gen ((docs.lookup p).getD "") mine)
  let verdict (c : Cut) (v : CutV) : Json := Json.mkObj [("path", .str c.path), ("old", .str c.old),
    ("verdict", .str v.name), ("missing", strsJson (match v with | .dropsFacts ms => ms | _ => []))]
  pure [("cuts", .arr (per.flatMap (fun (_, cs, _, vs) => (cs.zip vs).map fun (c, v) => verdict c v)).toArray),
        ("docs", .arr (per.toArray.map fun (p, _, d, vs) => Json.mkObj [("path", .str p), ("text", .str d),
          ("changed", .bool (vs.any (· == .apply)))]))]

open Fw.Plan.Polish in
/-- `plan.polishHunks`: per diff path the line ranges `comment-sicko` may edit, per edit hunk whether it is kept, and the planned paths the main checkout has dirty. -/
def opPolishHunks (req : Json) : Except String Reply := do
  let spans (d : Json) : Except String (List Span) := do
    (← arr d "spans").toList.mapM fun s => do pure ({ start := ← natD s "start" 0, len := ← natD s "len" 1 } : Span)
  let diff ← (← arr req "diff").toList.mapM fun d => do pure (← str d "path", ← spans d)
  let edits ← (← arr req "edits").toList.mapM fun d => do pure (← str d "path", ← spans d)
  let dirty ← strsD req "main"
  let hs (p : String) : List Span := (diff.filter (·.1 == p)).flatMap (·.2)
  pure [("ranges", .arr (diff.toArray.map fun (p, ss) => Json.mkObj [("path", .str p),
          ("ranges", .arr (ss.toArray.map fun s => Json.mkObj [("lo", toJson s.reach.1), ("hi", toJson s.reach.2)]))])),
        ("edits", .arr (edits.toArray.map fun (p, ss) => Json.mkObj [("path", .str p), ("pathOk", .bool (relOk p)),
          ("kept", .arr (ss.toArray.map fun s => .bool (editKept (hs p) p s)))])),
        ("blocked", strsJson (blocked dirty (diff.map (·.1))))]

open Fw.Plan.Polish in
/-- `plan.polishSettle`: the paths to restore and the stray untracked paths to delete so the polish stage ends clean (`settle`). -/
def opPolishSettle (req : Json) : Except String Reply := do
  let a := settle (← strsD req "before") (← strsD req "dirtyBefore") ⟨← strsD req "dirty", ← strsD req "untracked"⟩
  pure [("restore", strsJson a.restore), ("remove", strsJson a.remove)]

open Fw.Plan.Polish in
/-- `plan.polishWalk`: the lines of a file after the kept hunks are applied to HEAD and the restored ones are not (`walk`). -/
def opPolishWalk (req : Json) : Except String Reply := do
  let head ← strsD req "head"
  let hs ← (← arr req "hunks").toList.mapM fun h => do
    pure ({ target := ← natD h "target" 0, oldLen := ← natD h "oldLen" 0, new := ← strsD h "new",
            keep := (h.getObjValAs? Bool "keep").toOption.getD false } : WHunk)
  pure [("lines", strsJson (walk head 0 hs))]

open Fw.Ops.SpawnGuard in
/-- `plan.roster`: `Fw.Ops.SpawnGuard.prodRoles`, the roles the spawn guard knows. -/
def opRoster : Reply :=
  [("roles", .arr (prodRoles.toArray.map fun r => Json.mkObj [("name", .str r.name),
    ("runsAs", .str (match r.runsAs with | .teammate => "teammate" | .subagent => "subagent" | .worktree => "worktree")),
    ("edits", .bool r.edits)]))]

/-- The stateless ops of this module. -/
def ops : List String :=
  ["plan.incidentLint", "plan.overlap", "plan.reviewReady", "plan.reviewVerdict", "plan.polishPlan", "plan.polishCuts",
   "plan.polishHunks", "plan.polishSettle", "plan.polishWalk", "plan.roster"]

/-- Dispatch one of these ops (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "plan.incidentLint" => some (opIncidentLint req)
  | "plan.overlap" => some (opOverlap req)
  | "plan.reviewReady" => some (opReviewReady req)
  | "plan.reviewVerdict" => some (opReviewVerdict req)
  | "plan.polishPlan" => some (opPolishPlan req)
  | "plan.polishCuts" => some (opPolishCuts req)
  | "plan.polishHunks" => some (opPolishHunks req)
  | "plan.polishSettle" => some (opPolishSettle req)
  | "plan.polishWalk" => some (opPolishWalk req)
  | "plan.roster" => some (pure opRoster)
  | _ => none

end Fw.Wire.Plan
