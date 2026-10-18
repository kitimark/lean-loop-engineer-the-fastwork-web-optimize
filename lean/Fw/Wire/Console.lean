import Fw.Ops.Wire
import Fw.Console.Land
import Fw.Console.Self
import Fw.Console.LandPool
import Fw.Console.Alert
import Fw.Console.Preview
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
| `console.previewTarget` | `main` (main's sha), `facts` [{src, sha, onMain, noCode, land (optional: the land commit on main), cands [{ref, sha, contains}]}] (head candidates in priority order), `children` [{facts}] (the candidate lists of the sub-tasks of an umbrella) | `kind` (`main`/`integration`/`own`/`none`), `ref`, `sha`, `head` (sha or null), `headSrc` (`Fw.Console.Preview.headOf`) |
| `console.previewAdmit` | `secret`, `cookie`, `origin` (the proofs the route checked: `Fw.Console.Preview.Proof`), `preview` (the new preview's id), `task`, `now` (ms), `diskMb`, `hasTarget`, `live` [{id, task, rp, op, started}] | `ok`, `reason` (`notOwner`/`taskBusy`/`tooMany`/`lowDisk`/`noTarget`/`noPorts`), `actor`, `rp`, `op` (the ports), `deadline`, `ttl`, `k` (`Fw.Console.Preview.admit`) |
| `console.previewTick` | `now`, `live` | `keep` [ids], `kill` [ids] (`tick`, `expired`) |
| `console.previewStop` | `secret`, `cookie`, `origin`, `preview` (id), `live` | `ok`, `reason` (`notOwner`/`unknown`), `actor`, `kill` [ids] (`stop`, `own`) |
| `console.previewFail` | `preview` (id), `live` | `keep` [ids], `kill` [ids] (a failed build's teardown: `fail`, `own`) |
| `console.previewReap` | `live` | `kill` [ids] (all of the table, `reap`) |
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

/-! ## console.preview* -/

open Fw.Console.Preview in
/-- The actor named `name`, or an error. -/
def actorOfName (name : String) : Except String Fw.Console.Actor :=
  match name with
  | "user" => .ok .user | "lead" => .ok .lead | "owner" => .ok .owner | "reviewer" => .ok .reviewer
  | "script" => .ok .script | "git" => .ok .git | "hook" => .ok .hook
  | _ => throw s!"field actor: unknown actor {name}"

open Fw.Console.Preview in
/-- The proofs of a request (`secret`, `cookie`, `origin`), each a boolean. -/
def proofOf (req : Json) : Except String Proof := do
  pure { secret := ← asBool "secret" (← field req "secret"), cookie := ← asBool "cookie" (← field req "cookie"),
         origin := ← asBool "origin" (← field req "origin") }

open Fw.Console.Preview in
/-- The live table of a request. -/
def liveOf (req : Json) : Except String (List Pv) := do
  (← arrD req "live").mapM fun p => do
    pure ({ id := ← str p "id", task := ← str p "task", rp := ← nat p "rp", op := ← nat p "op", started := ← nat p "started" } : Pv)

open Fw.Console.Preview in
/-- A head fact of a request. -/
def factOf (j : Json) : Except String Fact := do
  let cs ← (← arrD j "cands").mapM fun c => do
    pure ({ ref := ← str c "ref", sha := ← str c "sha", contains := ← asBool "contains" (← field c "contains") } : Cand)
  pure { src := ← str j "src", sha := ← str j "sha", onMain := ← asBool "onMain" (← field j "onMain"),
         noCode := ← asBool "noCode" (← field j "noCode"), cands := cs,
         land := (← optStr j "land").getD "" }

open Fw.Console.Preview in
/-- `console.previewTarget` (`Fw.Console.Preview.headOf`). -/
def opPreviewTarget (req : Json) : Except String Reply := do
  let fs ← (← arrD req "facts").mapM factOf
  let ks ← (← arrD req "children").mapM fun c => do
    (← arrD c "facts").mapM factOf
  let d := headOf (← str req "main") fs ks
  let hd := match d.1 with
    | some f => [("head", Json.str f.sha), ("headSrc", Json.str f.src)]
    | none => [("head", Json.null), ("headSrc", Json.null)]
  pure (hd ++ (match d.2 with
    | .main s => [("kind", .str "main"), ("ref", .str "main"), ("sha", .str s)]
    | .integration r s => [("kind", .str "integration"), ("ref", .str r), ("sha", .str s)]
    | .own s => [("kind", .str "own"), ("ref", .null), ("sha", .str s)]
    | .none => [("kind", .str "none"), ("ref", .null), ("sha", .null)]))

open Fw.Console.Preview in
/-- `console.previewAdmit` (`Fw.Console.Preview.admit`). -/
def opPreviewAdmit (req : Json) : Except String Reply := do
  let s ← liveOf req
  let p ← proofOf req
  let r : Req := { actor := p.actor, id := ← str req "preview", task := ← str req "task",
                   now := ← nat req "now", diskMb := ← nat req "diskMb", hasTarget := ← asBool "hasTarget" (← field req "hasTarget") }
  let lim := [("ttl", Json.num ttl), ("k", Json.num K), ("actor", Json.str (Fw.Console.Actor.name p.actor))]
  pure (match admit s r with
    | .error e => [("ok", .bool false), ("reason", .str e.name), ("rp", .null), ("op", .null), ("deadline", .null)] ++ lim
    | .ok (p :: _) => [("ok", .bool true), ("reason", .null), ("rp", .num p.rp), ("op", .num p.op), ("deadline", .num p.deadline)] ++ lim
    | .ok [] => [("ok", .bool false), ("reason", .str "noPorts"), ("rp", .null), ("op", .null), ("deadline", .null)] ++ lim)

open Fw.Console.Preview in
/-- The ids of a table as JSON. -/
def idsJson (s : List Pv) : Json := .arr (s.toArray.map fun p => Json.str p.id)

open Fw.Console.Preview in
/-- `console.previewTick` (`Fw.Console.Preview.tick`, `expired`). -/
def opPreviewTick (req : Json) : Except String Reply := do
  let s ← liveOf req
  let now ← nat req "now"
  pure [("keep", idsJson (tick s now)), ("kill", idsJson (expired s now))]

open Fw.Console.Preview in
/-- `console.previewStop` (`Fw.Console.Preview.stop`, `own`). -/
def opPreviewStop (req : Json) : Except String Reply := do
  let s ← liveOf req
  let a := (← proofOf req).actor
  let i ← str req "preview"
  let an := ("actor", Json.str (Fw.Console.Actor.name a))
  pure (if !mayStart a then [("ok", .bool false), ("reason", .str "notOwner"), an, ("kill", .arr #[])]
    else match own s i with
      | [] => [("ok", .bool false), ("reason", .str "unknown"), an, ("kill", .arr #[])]
      | k => [("ok", .bool true), ("reason", .null), an, ("kill", idsJson k)])

open Fw.Console.Preview in
/-- `console.previewFail` (`Fw.Console.Preview.fail`, `own`): the teardown of a failed build. -/
def opPreviewFail (req : Json) : Except String Reply := do
  let s ← liveOf req
  let i ← str req "preview"
  pure [("keep", idsJson (fail s i)), ("kill", idsJson (own s i))]

open Fw.Console.Preview in
/-- `console.previewReap` (`Fw.Console.Preview.reap`). -/
def opPreviewReap (req : Json) : Except String Reply := do
  pure [("kill", idsJson (reap (← liveOf req)).2)]

/-! ## Dispatch -/

/-- The ops of this module. -/
def ops : List String := ["console.landReadiness", "console.actor", "console.alert", "console.landScope", "console.landLock", "console.landGuard",
  "console.landCommit", "console.landPick", "console.landPool", "console.landRetry", "plan.trailers", "plan.lint",
  "console.previewTarget", "console.previewAdmit", "console.previewTick", "console.previewStop", "console.previewFail", "console.previewReap"]

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
  | "console.previewTarget" => some (opPreviewTarget req)
  | "console.previewAdmit" => some (opPreviewAdmit req)
  | "console.previewTick" => some (opPreviewTick req)
  | "console.previewStop" => some (opPreviewStop req)
  | "console.previewFail" => some (opPreviewFail req)
  | "console.previewReap" => some (opPreviewReap req)
  | _ => none

end Fw.Wire.Console
