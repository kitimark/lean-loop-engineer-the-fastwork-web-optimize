import Fw.Ops.Wire
import Fw.Console.Land
import Fw.Console.Self
import Fw.Console.LandPool
import Fw.Console.Alert
import Fw.Plan.Trailer
import Fw.Plan.Lint
/-!
# JSON for the console's own rules (`console.landReadiness`, `console.actor`, `console.alert`, `plan.trailers`)

Stateless ops, dispatched by `Fw.Wire.handleCore` (this module cannot import `Fw.Wire`, which
imports it, so it decodes the card fields it needs itself).

| op | request | reply |
|---|---|---|
| `console.landReadiness` | `card` {id, needsDevice, owner?, approved?, head?, screenAt?, reviewAt?, deviceAt?, landed?} (a board or reducer card; other fields ignored), `sha` | `ready`, `needs` (`approve`/`build`/`screen`/`review`/`device`, in that order), `refusal` (the `card.land_request` refusal at `sha`, or null) |
| `console.actor` | `source`? (`alert`/`spawn`/`stop`/`build`/`landed`/`taskDone`/`planDefine`/`planMilestone`; missing = all) | `sources` [{source, actor, type, allowed}] |
| `console.alert` | `event` {hook_event_name, ts, agent_id?, agent_type?, tool_name?, notification_type?}, `flights`? [{agent_id?, agent_type?, tool_name?}] (tool calls in flight; no agent_id = the lead), `open`? [step ids] (alert steps still open on the board) | `post` (null or {step, key, title, kind, agent}: the `step.post` to send as actor script), `close` [{step, key}] (the `step.cancel`s to send as actor script) |
| `console.landScope` | `writes` [globs], `names`? [agent/task names for handoff files], `allow`? [globs], `paths` [changed files], `task`? / `stream`? (the task id and stream: port-*, proof-*, measure add their registration set) | `ok`, `reason` (null / `noWrites` / `outOfScope`), `violations`, `scope` (the globs used; `!` = exclude) |
| `console.landLock` | `held` (lock file exists), `alive`? (its pid is alive) | `verdict` (`free`/`busy`/`stale`) |
| `console.landGuard` | `held`, `alive`?, `here`? (commit is in the locked checkout), `own`? (the land's own commit) | `verdict` (`allow`/`held`/`stale`), `allow` |
| `console.landCommit` | `locked`, `mergeHead`? (null: MERGE_HEAD gone), `head`, `pre` (HEAD when the lock was taken) | `ok`, `tip`, `reason` (`no lock`/`merge state gone`/`head moved`) |
| `console.landPick` | `givenAhead`, `others`? [{name, ahead, contains}] | `pick` (`given`/`other`/`nothing`/`ambiguous`), `branch`, `names` |
| `console.landPool` | `cores`, `load` (one-minute load average rounded up) | `pool` (`Fw.Console.LandPool.poolFair`) |
| `console.landRetry` | `passed`, `loadFailure` | `rerun` (`Fw.Console.LandPool.rerunAlone`), `pool` (the re-run's pool, 1) |
| `plan.lint` | `tasks` [{id, title?, deps?, evidence?, evidenceOnMain?}] (`evidenceOnMain`: the glue's `git merge-base --is-ancestor <evidence> main`; missing = true), `commits`? [{sha, body}] (main's first-parent history) | `ok` (no error), `errors`, `warnings`, `infos`, `findings` [{task, code, severity, detail}] (`Fw.Plan.Lint`) |
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

/-! ## console.alert -/

open Fw.Console.Alert in
/-- `console.alert`: which alert step an event opens and which open ones it closes
(`Fw.Console.Alert.act`). -/
def opAlert (req : Json) : Except String Reply := do
  let j ← field req "event"
  let e : Ev := { event := ← str j "hook_event_name", ts := ← nat j "ts", agentId := ← optStr j "agent_id",
                  agentType := ← optStr j "agent_type", tool := ← optStr j "tool_name", ntype := ← optStr j "notification_type" }
  let fs ← (← arrD req "flights").mapM fun f => do
    pure ({ agentId := ← optStr f "agent_id", agentType := ← optStr f "agent_type", tool := ← optStr f "tool_name" } : Flight)
  let opn ← (← arrD req "open").mapM fun v => asStr "open" v
  let o := act e fs opn
  pure [("post", match o.post with
          | none => .null
          | some a => Json.mkObj [("step", .str a.step), ("key", .str a.key), ("title", .str a.title),
                                  ("kind", .str a.kind.name), ("agent", .str a.agent)]),
        ("close", .arr (o.close.toArray.map fun s => Json.mkObj [("step", .str s), ("key", .str (closeKey s))]))]

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

/-! ## console.landScope -/

open Fw.Console.Land in
/-- `console.landScope`: may these changed paths land? (`Fw.Console.Land.landVerdict`). -/
def opLandScope (req : Json) : Except String Reply := do
  let strs (k : String) (a : List Json) : Except String (List String) := a.mapM (asStr k)
  let writes ← strs "writes" (← arr req "writes").toList
  let names ← strs "names" (← arrD req "names")
  let allow ← strs "allow" (← arrD req "allow")
  let paths ← strs "paths" (← arr req "paths").toList
  let task ← strD req "task" ""
  let stream ← strD req "stream" ""
  let (ok, reason, vs) := match landVerdict writes names allow paths task stream with
    | .ok => (true, Json.null, [])
    | .noWrites => (false, Json.str "noWrites", [])
    | .outOfScope v => (false, Json.str "outOfScope", v)
  pure [("ok", .bool ok), ("reason", reason), ("violations", .arr (vs.toArray.map Json.str)),
        ("scope", .arr ((landScope writes names allow task stream).toArray.map Json.str))]

/-! ## console.landLock, console.landGuard, console.landCommit, console.landPick -/

open Fw.Console.Land in
/-- `console.landLock`: may a land take the lock? (`Fw.Console.Land.lockVerdict`). -/
def opLandLock (req : Json) : Except String Reply := do
  let held ← asBool "held" (← field req "held")
  let alive ← boolD req "alive" false
  let v := match lockVerdict held alive with | .free => "free" | .busy => "busy" | .stale => "stale"
  pure [("verdict", .str v)]

open Fw.Console.Land in
/-- `console.landGuard`: may this commit go through the `pre-commit` hook? (`Fw.Console.Land.guardVerdict`). -/
def opLandGuard (req : Json) : Except String Reply := do
  let held ← asBool "held" (← field req "held")
  let alive ← boolD req "alive" false
  let here ← boolD req "here" true
  let own ← boolD req "own" false
  let v := match guardVerdict held alive here own with | .allow => "allow" | .held => "held" | .stale => "stale"
  pure [("verdict", .str v), ("allow", .bool (v == "allow"))]

open Fw.Console.Land in
/-- `console.landCommit`: may the land commit its merge? (`Fw.Console.Land.landTip`). -/
def opLandCommit (req : Json) : Except String Reply := do
  let locked ← asBool "locked" (← field req "locked")
  let merge ← optStr req "mergeHead"
  let head ← str req "head"
  let pre ← str req "pre"
  pure (match landTip locked merge head pre with
    | .ok t => [("ok", .bool true), ("tip", .str t), ("reason", .null)]
    | .error r => [("ok", .bool false), ("tip", .null), ("reason", .str r)])

open Fw.Console.Land in
/-- `console.landPick`: which branch to land (`Fw.Console.Land.pick`). -/
def opLandPick (req : Json) : Except String Reply := do
  let ahead ← asBool "givenAhead" (← field req "givenAhead")
  let cs ← (← arrD req "others").mapM fun c => do
    pure ({ name := ← str c "name", ahead := ← asBool "ahead" (← field c "ahead"),
            contains := ← asBool "contains" (← field c "contains") } : Cand)
  pure (match pick ahead cs with
    | .given => [("pick", .str "given"), ("branch", .null), ("names", .arr #[])]
    | .other n => [("pick", .str "other"), ("branch", .str n), ("names", .arr #[.str n])]
    | .nothing => [("pick", .str "nothing"), ("branch", .null), ("names", .arr #[])]
    | .ambiguous ns => [("pick", .str "ambiguous"), ("branch", .null), ("names", .arr (ns.toArray.map Json.str))])

open Fw.Console.LandPool in
/-- `console.landPool`: how many land checks may run at once (`Fw.Console.LandPool.poolFair`). -/
def opLandPool (req : Json) : Except String Reply := do
  let c ← nat req "cores"
  let l ← nat req "load"
  pure [("pool", .num (poolFair c l))]

open Fw.Console.LandPool in
/-- `console.landRetry`: does a failed check re-run alone? (`Fw.Console.LandPool.rerunAlone`). -/
def opLandRetry (req : Json) : Except String Reply := do
  let p ← asBool "passed" (← field req "passed")
  let f ← asBool "loadFailure" (← field req "loadFailure")
  pure [("rerun", .bool (rerunAlone p f)), ("pool", .num rerunPool)]

/-! ## plan.lint -/

open Fw.Plan Fw.Plan.Lint in
/-- `plan.lint`: the findings of `Fw.Plan.Lint.lint` over the work graph rows and main's trailers. -/
def opPlanLint (req : Json) : Except String Reply := do
  let strs (k : String) (a : List Json) : Except String (List String) := a.mapM (asStr k)
  let ts ← (← arr req "tasks").toList.mapM fun t => do
    let ev ← match opt t "evidence" with
      | none | some .null => pure none
      | some v => some <$> asStr "evidence" v
    pure ({ id := ← str t "id", title := ← strD t "title" "", stream := "", milestone := none,
            deps := ← strs "deps" (← arrD t "deps"), owner := "", writes := [], devices := [],
            needs := [], evidence := ev, agent := none } : Task)
  let off ← (← arr req "tasks").toList.filterMapM fun t => do
    match opt t "evidenceOnMain" with
    | some (.bool false) => pure (some (← str t "id"))
    | none | some .null | some (.bool true) => pure none
    | some _ => throw "evidenceOnMain: expected a boolean"
  let cs ← (← arrD req "commits").mapM fun c => do
    pure ({ sha := ← str c "sha", body := ← str c "body" } : Fw.Plan.Trailer.Commit)
  let fs := lint ts cs off
  let n (s : String) := (fs.filter (·.severity == s)).length
  pure [("ok", .bool (ok ts cs off)), ("errors", .num (n "error")), ("warnings", .num (n "warn")), ("infos", .num (n "info")),
        ("findings", .arr (fs.toArray.map fun f => Json.mkObj
          [("task", .str f.task), ("code", .str f.code), ("severity", .str f.severity), ("detail", .str f.detail)]))]

/-! ## Dispatch -/

/-- The ops of this module. -/
def ops : List String := ["console.landReadiness", "console.actor", "console.alert", "console.landScope", "console.landLock", "console.landGuard",
  "console.landCommit", "console.landPick", "console.landPool", "console.landRetry", "plan.trailers", "plan.lint"]

/-- Dispatch one of these ops (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "console.landReadiness" => some (opLandReadiness req)
  | "console.actor" => some (opActor req)
  | "console.alert" => some (opAlert req)
  | "console.landScope" => some (opLandScope req)
  | "console.landLock" => some (opLandLock req)
  | "console.landGuard" => some (opLandGuard req)
  | "console.landCommit" => some (opLandCommit req)
  | "console.landPick" => some (opLandPick req)
  | "console.landPool" => some (opLandPool req)
  | "console.landRetry" => some (opLandRetry req)
  | "plan.trailers" => some (opTrailers req)
  | "plan.lint" => some (opPlanLint req)
  | _ => none

end Fw.Wire.Console
