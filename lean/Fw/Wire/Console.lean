import Fw.Ops.Wire
import Fw.Console.Land
import Fw.Console.Self
import Fw.Console.LandPool
import Fw.Console.LandTier
import Fw.Console.Alert
import Fw.Console.Preview
import Fw.Console.PreviewOwner
import Fw.Console.PreviewCache
import Fw.Console.Builds
import Fw.Console.Daemon
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
| `console.previewTarget` | `main` (main's sha), `facts` [{src, sha, onMain, noCode, fpLine? (the head is on main's first-parent line), path? [{sha, p2Has}] (first-parent ancestry path from the head to main, oldest first), ownWork? (a merge's second parent contains the task's own work; default true), behind? (another candidate holds code this one lacks), cands [{ref, sha, contains}]}] (head candidates in priority order), `children` [{facts}] (the candidate lists of the sub-tasks of an umbrella) | `kind` (`main`/`integration`/`own`/`none`), `ref`, `sha`, `head` (sha or null), `headSrc` (`Fw.Console.Preview.headOf`) |
| `console.previewAdmit` | `secret`, `cookie`, `origin` (the proofs the route checked: `Fw.Console.Preview.Proof`), `preview` (the new preview's id), `task`, `now` (ms), `diskMb`, `hasTarget`, `portBase?` (first port of the range, default `portLo` = 47100), `live` [{id, task, rp, op, started}] | `ok`, `reason` (`notOwner`/`taskBusy`/`tooMany`/`lowDisk`/`noTarget`/`noPorts`), `actor`, `rp`, `op` (the ports), `deadline`, `ttl`, `k`, `portLo`, `portN` (`Fw.Console.Preview.admit`) |
| `console.previewTick` | `now`, `live` | `keep` [ids], `kill` [ids] (`tick`, `expired`) |
| `console.previewStop` | `secret`, `cookie`, `origin`, `preview` (id), `live` | `ok`, `reason` (`notOwner`/`unknown`), `actor`, `kill` [ids] (`stop`, `own`) |
| `console.previewFail` | `preview` (id), `live` | `keep` [ids], `kill` [ids] (a failed build's teardown: `fail`, `own`) |
| `console.previewReap` | `live` | `kill` [ids] (all of the table, `reap`) |
| `console.previewLink` | `hasTty`, `now`? (ms), `last`? (ms of the last link) | `sink` (`tty` or null: print no link), `allowed` [sinks] (`linkSink`: only `tty`), `reissue`? (with `now`: may a new link be issued, `mayReissue`: one per minute) |
| `console.ownerLogin` | `enabled` (the console has an owner passphrase), `correct` (the constant-time compare matched), `now` (ms), `fails`? [ms] and `lockUntil`? (the client address's record; missing = fresh), `gFails`? [ms] and `gLockUntil`? (the global record across all addresses; missing = fresh) | `verdict` (`disabled`/`locked`/`wrong`/`ok`), `fails`, `lockUntil` (the new address record), `gFails`, `gLockUntil` (the new global record), `retryAt` (the end of the longest active lock, else null), `maxTries`, `window`, `lock`, `globMax`, `globWindow`, `globLock` (`Fw.Console.Preview.Owner.attempt`) |
| `console.ownerGate` | `lan` (non-loopback or unknown remote address), `session` (console port: a valid owner bearer token in the Authorization header, never a cookie; preview port: a valid preview-access cookie), `hostOk` (Host names this port), `path`, `port`? (`console` default, or `preview`; the preview port also reads `grant` (the cookie names an inspect grant), `grantStarted`, `now` (ms), `via` (a Referer-routed path)) | `allow`, `by` (`session`/`grant`/`none`), `class` (`login`/`preview`/`other`/`shell`) (`Fw.Console.Preview.Owner.allow` for the console port, `allowPreview` for the preview port; `classify`) |
| `console.previewGrant` | `kind` (`issue`: may a grant be issued, from `lan`; `redeem`: a grant token is presented, with `known`, `used`, `issuedAt`, `now` (ms)), `lan` | `allow`, `verdict` (redeem: `ok`/`lan`/`unknown`/`used`/`expired`), `ttlMs` (issue), `cookieMs` (`Fw.Console.Preview.Owner.issueAllowed`, `redeem`) |
| `console.ownerAction` | `kind` (`owner`: an owner action, needs the bearer token and an Origin; `command`: any other non-GET route, an Origin if present; `login`: an Origin, no token), `bearer` (a valid owner token in the Authorization header), `origin`? ({host, port} or null: none sent), `host`? (the origin of the Host header when it names this console, else null), `extra` [{host, port}] (configured web origins), `previewPort`? (null = unset: nothing is trusted) | `allow`, `trusted` (the computed trusted origins, none on the preview port) (`Fw.Console.Preview.Owner.ownerAction`, `commandOk`, `loginOk`, `trustedOrigins`) |
| `console.lanStart` | `want` (LAN mode was asked for), `hasAddr` (a private address was found), `hasPass` (the keychain item was read), `passLen` (its length in characters; never echoed) | `result` (`off`/`noAddress`/`noPassphrase`/`shortPassphrase`/`start`), `start` (`Fw.Console.Preview.Owner.lanStart`) |
| `console.daemon` | `kind`: `start` (`recorded`? pid in api.json, `answered`? pid the health request reported), `stop` (same), `restart` (same), `line` (`line`: a log line kind), `rotate` (`size`, `limit`? default 5 MiB) | start: `allow`, `verified` (pid or null), `reason` (`ok`/`running`); stop: `target` (the only pid to signal, or null), `reason` (`ok`/`notRunning`); restart: `steps` [{step: `stop`+`pid` / `start`}]; line: `admit`, `secret`; rotate: `rotate`, `limit` (`Fw.Console.Daemon.startAllowed`, `stopTarget`, `restartPlan`, `logAdmits`, `rotate`) |
| `console.previewSweep` | `now`, `live` [{id, task, rp, op, started, seen? (last proxied request, default started)}] | `keep` [ids], `kill` [ids], `why` [{id, why: `ttl`/`idle`}], `idle` (ms) (`Fw.Console.Preview.Owner.sweep`, `reaped`) |
| `console.landTier` | `ids` [check ids] | `local` [ids], `remote` [ids] (`Fw.Console.LandTier.pick`, order kept) |
| `console.landLane` | `exitOk`, `coreUser`, `skipped` (skipped plus todo tests the summary reports; `null` when no summary was recognised) | `verdict` (`pass`/`fail`/`skipped`/`unknown`), `ok` (`Fw.Console.LandTier.laneVerdict`) |
| `console.previewCache` | `path` (the request path, no query), `manifest`? [names] (the rewrite build's `.vite/manifest.json` `file`/`css`/`assets` entries, each as `/<name>`) | `kind` (`hashed`/`html`/`other`), `cacheControl`, `immutable`, `compress` (`Fw.Console.PreviewCache.kind`, `cacheControl`, `compressible`) |
| `console.builds` | `main` (main's sha), `log` [{sha, time, body}] (main's first-parent log, newest first), `known` [{id, title}] (the work graph), `evidence`? [{task, sha}] (a work-graph task whose evidence commit is on main: sha = its land commit on main's first-parent line), `flags` [{part, variant, kind, requires? [keys]}], `presets` [{name, fw {part: variant}}] (fw with `extends` already resolved) | `ports` [{id, task, group, sha, landedAt, title, slot, search, target}], `optimize` [{id, kind, name, search, status, note, slot, target}], `searches` (`Fw.Console.Builds.portRows`, `optRows`, `enumerate`) |
| `console.buildsPicker` | `keys` (the `bySearch` keys of a build), `current`? | `searches` (the picker list), `current` (the search the compare view loads) (`Fw.Console.Builds.picker`, `choose`) |
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

open Fw.Console.LandTier in
/-- `console.landTier`: the selected check ids split by tier (`Fw.Console.LandTier.pick`). -/
def opLandTier (req : Json) : Except String Reply := do
  let ids ← strsD req "ids"
  let js (l : List String) : Json := .arr (l.toArray.map Json.str)
  pure [("local", js (pick .onMac ids)), ("remote", js (pick .onCi ids))]

open Fw.Console.LandTier in
/-- `console.landLane`: the lane verdict of one check (`Fw.Console.LandTier.laneVerdict`). -/
def opLandLane (req : Json) : Except String Reply := do
  let e ← asBool "exitOk" (← field req "exitOk")
  let c ← asBool "coreUser" (← field req "coreUser")
  let n ← match opt req "skipped" with
    | none | some .null => pure none
    | some _ => some <$> nat req "skipped"
  let v := laneVerdict e c n
  pure [("verdict", .str v.name), ("ok", .bool v.ok)]

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
         fpLine := ← boolD j "fpLine" false,
         path := ← (← arrD j "path").mapM fun c => do
           pure ({ sha := ← str c "sha", p2Has := ← asBool "p2Has" (← field c "p2Has") } : PathC),
         ownWork := ← boolD j "ownWork" false, behind := ← boolD j "behind" false }

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
  let lo ← match opt req "portBase" with
    | none => pure portLo
    | some _ => nat req "portBase"
  let lim := [("ttl", Json.num ttl), ("k", Json.num K), ("portLo", Json.num portLo), ("portN", Json.num portN), ("actor", Json.str (Fw.Console.Actor.name p.actor))]
  pure (match admit lo s r with
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

open Fw.Console.Preview in
/-- `console.previewLink` (`Fw.Console.Preview.linkPlan`, `linkSink`): where the owner link goes. -/
def opPreviewLink (req : Json) : Except String Reply := do
  let all : List (String × Sink) := [("tty", .tty), ("stdout", .stdout), ("stderr", .stderr), ("file", .file), ("log", .log), ("eventStore", .eventStore)]
  let name (s : Sink) : String := (all.find? fun p => p.2 == s).map (·.1) |>.getD "?"
  let plan := linkPlan (← asBool "hasTty" (← field req "hasTty"))
  let last : Option Nat ← match opt req "last" with
    | none => pure none
    | some _ => do pure (some (← nat req "last"))
  let re : Reply ← match opt req "now" with
    | none => pure []
    | some _ => do pure [("reissue", Json.bool (mayReissue last (← nat req "now")))]
  let base : Reply := [("sink", match plan with | some s => Json.str (name s) | none => Json.null),
        ("allowed", Json.arr ((all.filter fun p => linkSink p.2).map fun p => Json.str p.1).toArray)]
  pure (base ++ re)

open Fw.Console.Preview.Owner in
/-- `console.ownerLogin` (`Fw.Console.Preview.Owner.attempt`): the rate limit of the owner login, per client address and
across all addresses. -/
def opOwnerLogin (req : Json) : Except String Reply := do
  let recOf (fk lk : String) : Except String Rec := do
    let fails ← (← arrD req fk).mapM fun j => asNat fk j
    let lockUntil ← match opt req lk with
      | none => pure 0
      | some _ => nat req lk
    pure { fails := fails, lockUntil := lockUntil }
  let now ← nat req "now"
  let (v, r, g) := attempt (← recOf "fails" "lockUntil") (← recOf "gFails" "gLockUntil") now
    (← asBool "enabled" (← field req "enabled")) (← asBool "correct" (← field req "correct"))
  let arr (r : Rec) : Json := .arr (r.fails.toArray.map fun (t : Nat) => Json.num t)
  let endAt := max r.lockUntil g.lockUntil
  pure [("verdict", .str v.name), ("fails", arr r), ("lockUntil", .num r.lockUntil),
        ("gFails", arr g), ("gLockUntil", .num g.lockUntil),
        ("retryAt", if now < endAt then .num endAt else .null),
        ("maxTries", .num maxTries), ("window", .num window), ("lock", .num lockMs),
        ("globMax", .num globMax), ("globWindow", .num globWindow), ("globLock", .num globLock)]

open Fw.Console.Preview.Owner in
/-- `console.ownerGate` (`Fw.Console.Preview.Owner.allow`, `allowPreview`): which requests a port serves. -/
def opOwnerGate (req : Json) : Except String Reply := do
  let c := classify (← str req "path")
  let lan ← asBool "lan" (← field req "lan")
  let session ← asBool "session" (← field req "session")
  let hostOk ← asBool "hostOk" (← field req "hostOk")
  let port ← match opt req "port" with
    | none => pure "console"
    | some _ => str req "port"
  let flag (k : String) : Except String Bool := match opt req k with
    | none => pure false
    | some j => asBool k j
  let num (k : String) : Except String Nat := match opt req k with
    | none => pure 0
    | some _ => nat req k
  let (ok, by_) ← match port with
    | "console" => pure (allow lan session hostOk c, "none")
    | "preview" => do
      let viaSession := allowPreview lan session hostOk
      let viaGrant := allowGrant lan hostOk (← flag "grant") (← num "grantStarted") (← num "now") (← flag "via") c
      pure (servePreview lan session hostOk (← flag "grant") (← num "grantStarted") (← num "now") (← flag "via") c,
        if viaSession then "session" else if viaGrant then "grant" else "none")
    | _ => throw "field port: expected console or preview"
  pure [("allow", .bool ok), ("class", .str c.name), ("by", .str (if ok then by_ else "none"))]

open Fw.Console.Preview.Owner in
/-- `console.previewGrant` (`Fw.Console.Preview.Owner.issueAllowed`, `redeem`): may a grant be issued (`kind` issue, from
`lan`), and what happens when a grant token is presented (`kind` redeem). -/
def opPreviewGrant (req : Json) : Except String Reply := do
  let lan ← asBool "lan" (← field req "lan")
  match ← str req "kind" with
  | "issue" => pure [("allow", .bool (issueAllowed lan)), ("ttlMs", .num grantTokenTtl), ("cookieMs", .num grantCookieTtl)]
  | "redeem" =>
    let known ← asBool "known" (← field req "known")
    let used ← asBool "used" (← field req "used")
    let r := redeem lan known used (← nat req "issuedAt") (← nat req "now")
    pure [("allow", .bool (r == .ok)), ("verdict", .str r.name), ("cookieMs", .num grantCookieTtl)]
  | _ => throw "field kind: expected issue or redeem"

open Fw.Console.Preview.Owner in
/-- `console.ownerAction` (`Fw.Console.Preview.Owner.ownerAction`, `commandOk`, `loginOk`, `trustedOrigins`): may this request
act as the owner. The trusted origin list is computed here from the Host's own origin, the configured extra origins and the
preview port; a missing preview port trusts nothing. -/
def opOwnerAction (req : Json) : Except String Reply := do
  let originOf (j : Json) : Except String Origin := do pure { host := ← str j "host", port := ← nat j "port" }
  let optOrigin (k : String) : Except String (Option Origin) := match opt req k with
    | none | some .null => pure none
    | some j => do pure (some (← originOf j))
  let extra ← (← arrD req "extra").mapM originOf
  let pp ← match opt req "previewPort" with
    | none | some .null => pure none
    | some _ => do pure (some (← nat req "previewPort"))
  let trusted := trustedOrigins pp (← optOrigin "host") extra
  let origin ← optOrigin "origin"
  let ok ← match ← str req "kind" with
    | "owner" => pure (ownerAction trusted ⟨← asBool "bearer" (← field req "bearer"), false⟩ origin)
    | "command" => pure (commandOk trusted origin)
    | "login" => pure (loginOk trusted origin)
    | _ => throw "field kind: expected owner, command or login"
  pure [("allow", .bool ok), ("trusted", .arr (trusted.toArray.map fun o => Json.mkObj [("host", .str o.host), ("port", .num o.port)]))]

open Fw.Console.Preview.Owner in
/-- `console.lanStart` (`Fw.Console.Preview.Owner.lanStart`): whether LAN mode starts, and if not, why. -/
def opLanStart (req : Json) : Except String Reply := do
  let r := lanStart (← asBool "want" (← field req "want")) (← asBool "hasAddr" (← field req "hasAddr"))
    (← asBool "hasPass" (← field req "hasPass")) (← nat req "passLen")
  pure [("result", .str r), ("start", .bool (r == "start"))]

open Fw.Console.Preview.Owner in
/-- `console.previewSweep` (`Fw.Console.Preview.Owner.sweep`): the TTL and the idle stop in one decision. -/
def opPreviewSweep (req : Json) : Except String Reply := do
  let now ← nat req "now"
  let live ← (← arrD req "live").mapM fun p => do
    let pv : Fw.Console.Preview.Pv := { id := ← str p "id", task := ← str p "task", rp := ← nat p "rp", op := ← nat p "op", started := ← nat p "started" }
    let seen ← match opt p "seen" with
      | none => pure pv.started
      | some _ => nat p "seen"
    pure ({ pv := pv, seen := seen } : Live)
  let ids (l : List Live) : Json := .arr (l.toArray.map fun x => Json.str x.pv.id)
  pure [("keep", ids (sweep live now)), ("kill", ids (reaped live now)),
        ("why", .arr ((reaped live now).toArray.map fun x => Json.mkObj [("id", .str x.pv.id), ("why", .str (why x now))])),
        ("idle", .num idleLimit)]

open Fw.Console.PreviewCache in
/-- `console.previewCache` (`Fw.Console.PreviewCache.kind`): the cache header and compression of a preview file. -/
def opPreviewCache (req : Json) : Except String Reply := do
  let names ← (← arrD req "manifest").mapM (asStr "manifest")
  let k := kind names (← str req "path")
  let name := match k with | .hashed => "hashed" | .html => "html" | .other => "other"
  pure [("kind", .str name), ("cacheControl", .str (cacheControl k)), ("immutable", .bool (reusesWithoutAsking k)),
        ("compress", .bool (compressible (← str req "path")))]


open Fw.Console.Builds in
/-- The `Target` of a row as JSON. -/
def buildTargetJson : Fw.Console.Preview.Target → Json
  | .main s => Json.mkObj [("kind", "main"), ("ref", "main"), ("sha", s)]
  | _ => Json.null

/-- An object of strings as pairs. -/
def strPairs (k : String) : Json → Except String (List (String × String))
  | .obj kvs => kvs.toList.mapM fun kv => do pure (kv.1, ← asStr k kv.2)
  | _ => .error s!"field {k}: expected an object"

open Fw.Console.Builds in
/-- `console.builds` (`Fw.Console.Builds.portRows`, `optRows`, `enumerate`). -/
def opBuilds (req : Json) : Except String Reply := do
  let main ← str req "main"
  let log ← (← arrD req "log").mapM fun c => do
    pure ({ sha := ← str c "sha", time := ← nat c "time", body := ← strD c "body" "" } : LogCommit)
  let known ← (← arrD req "known").mapM fun k => do
    pure ({ id := ← str k "id", title := ← strD k "title" "" } : Known)
  let ev ← (← arrD req "evidence").mapM fun e => do
    pure ({ task := ← str e "task", sha := ← str e "sha" } : EvLand)
  let flags ← (← arrD req "flags").mapM fun f => do
    pure ({ part := ← str f "part", variant := ← str f "variant", kind := ← str f "kind",
            requires := ← (← arrD f "requires").mapM (asStr "requires") } : Flag)
  let presets ← (← arrD req "presets").mapM fun p => do
    pure ({ name := ← str p "name", fw := ← strPairs "fw" (← field p "fw") } : Preset)
  let ports := (portRows known log ev).map fun r => Json.mkObj [
    ("id", Json.str ("port:" ++ r.task)), ("task", r.task), ("group", group r.task), ("sha", r.sha),
    ("landedAt", Json.num r.landedAt), ("title", r.title), ("slot", landSlot r.task), ("search", ""),
    ("target", buildTargetJson (portTarget r))]
  let opts := (optRows presets flags).map fun o => Json.mkObj [
    ("id", Json.str (o.kind ++ ":" ++ o.name)), ("kind", o.kind), ("name", o.name), ("search", o.search),
    ("status", o.status.name), ("note", match o.status.note with | some n => Json.str n | none => Json.null),
    ("slot", o.slot), ("target", buildTargetJson (optTarget main))]
  pure [("ports", Json.arr ports.toArray), ("optimize", Json.arr opts.toArray),
        ("searches", Json.arr ((enumerate presets flags).map Json.str).toArray)]

open Fw.Console.Builds in
/-- `console.buildsPicker` (`Fw.Console.Builds.picker`, `choose`). -/
def opBuildsPicker (req : Json) : Except String Reply := do
  let keys ← (← arrD req "keys").mapM (asStr "keys")
  let cur ← strD req "current" ""
  pure [("searches", Json.arr ((picker keys).map Json.str).toArray), ("current", Json.str (choose keys cur))]

open Fw.Console.Daemon in
/-- `console.daemon` (`Fw.Console.Daemon`): what `fw console start|stop|restart` may do, which log line kinds are admitted, and when the log is rotated. -/
def opDaemon (req : Json) : Except String Reply := do
  let pid (k : String) : Except String (Option Nat) := match opt req k with
    | none | some .null => pure none
    | some _ => do pure (some (← nat req k))
  let pj : Option Nat → Json := fun o => match o with | some p => Json.num p | none => Json.null
  match ← str req "kind" with
  | "start" =>
    let r ← pid "recorded"; let a ← pid "answered"
    pure [("allow", .bool (startAllowed r a)), ("verified", pj (verified r a)), ("reason", .str (if startAllowed r a then "ok" else "running"))]
  | "stop" =>
    let t := stopTarget (← pid "recorded") (← pid "answered")
    pure [("target", pj t), ("reason", .str (if t.isSome then "ok" else "notRunning"))]
  | "restart" =>
    let steps := restartPlan (verified (← pid "recorded") (← pid "answered"))
    pure [("steps", Json.arr (steps.toArray.map fun s => match s with
      | .stop p => Json.mkObj [("step", .str "stop"), ("pid", .num p)]
      | .start => Json.mkObj [("step", .str "start")]))]
  | "line" =>
    let name ← str req "line"
    match Line.ofName? name with
    | some l => pure [("admit", .bool (logAdmits l)), ("secret", .bool l.secret)]
    | none => throw "field line: unknown line kind"
  | "rotate" =>
    let limit ← match opt req "limit" with
      | none => pure logLimit
      | some _ => nat req "limit"
    pure [("rotate", .bool (rotate (← nat req "size") limit)), ("limit", .num limit)]
  | _ => throw "field kind: expected start, stop, restart, line or rotate"

/-! ## Dispatch -/

/-- The ops of this module. -/
def ops : List String := ["console.landReadiness", "console.actor", "console.alert", "console.landScope", "console.landLock", "console.landGuard",
  "console.landCommit", "console.landPick", "console.landPool", "console.landRetry", "console.landTier", "console.landLane", "plan.trailers", "plan.lint",
  "console.previewTarget", "console.previewAdmit", "console.previewTick", "console.previewStop", "console.previewFail", "console.previewReap", "console.previewLink",
  "console.ownerLogin", "console.ownerGate", "console.previewGrant", "console.ownerAction", "console.lanStart", "console.previewSweep", "console.previewCache", "console.builds", "console.buildsPicker", "console.daemon"]

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
  | "console.landTier" => some (opLandTier req)
  | "console.landLane" => some (opLandLane req)
  | "plan.trailers" => some (opTrailers req)
  | "plan.lint" => some (opPlanLint req)
  | "console.previewTarget" => some (opPreviewTarget req)
  | "console.previewAdmit" => some (opPreviewAdmit req)
  | "console.previewTick" => some (opPreviewTick req)
  | "console.previewStop" => some (opPreviewStop req)
  | "console.previewFail" => some (opPreviewFail req)
  | "console.previewReap" => some (opPreviewReap req)
  | "console.previewLink" => some (opPreviewLink req)
  | "console.ownerLogin" => some (opOwnerLogin req)
  | "console.ownerGate" => some (opOwnerGate req)
  | "console.previewGrant" => some (opPreviewGrant req)
  | "console.ownerAction" => some (opOwnerAction req)
  | "console.lanStart" => some (opLanStart req)
  | "console.previewSweep" => some (opPreviewSweep req)
  | "console.previewCache" => some (opPreviewCache req)
  | "console.builds" => some (opBuilds req)
  | "console.buildsPicker" => some (opBuildsPicker req)
  | "console.daemon" => some (opDaemon req)
  | _ => none

end Fw.Wire.Console
