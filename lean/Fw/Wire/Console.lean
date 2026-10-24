import Fw.Ops.Wire
import Fw.Console.Land
import Fw.Console.Self
import Fw.Console.LandPool
import Fw.Console.LandTier
import Fw.Console.LandRemote
import Fw.Console.Alert
import Fw.Console.Preview
import Fw.Console.PreviewOwner
import Fw.Console.PreviewArm
import Fw.Console.PreviewReturn
import Fw.Console.PreviewCache
import Fw.Console.Builds
import Fw.Console.BuildsOpen
import Fw.Wire.Compose
import Fw.Wire.Layers
import Fw.Wire.Review
import Fw.Wire.ReviewPreview
import Fw.Wire.ReviewFeedback
import Fw.Wire.Report
import Fw.Wire.Steps
import Fw.Wire.ReviewInfo
import Fw.Console.Daemon
import Fw.Console.LandLegs
import Fw.Land.RenderGuard
import Fw.Plan.Trailer
import Fw.Plan.Lint
namespace Fw.Wire.Console
open Lean Fw.Wire.Ops

def optStr (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asStr k v

def cardOf (j : Json) : Except String Fw.Console.Card := do
  pure { id := ← str j "id", owner := ← strD j "owner" "", needsDevice := ← asBool "needsDevice" (← field j "needsDevice"),
         approved := ← boolD j "approved" false, head := ← optStr j "head",
         screenAt := ← optStr j "screenAt", reviewAt := ← optStr j "reviewAt",
         deviceAt := ← optStr j "deviceAt", landed := ← boolD j "landed" false }

open Fw.Console.Land in
def opLandReadiness (req : Json) : Except String Reply := do
  let c ← cardOf (← field req "card")
  let sha ← str req "sha"
  pure [("ready", .bool (Fw.Console.ready c)),
        ("needs", .arr ((landNeeds c).toArray.map fun n => .str n.name)),
        ("refusal", ostr (landRefusal c sha))]

open Fw.Console.Self in
def sourceJson (s : Source) : Json := Json.mkObj [
  ("source", .str s.name), ("actor", .str (actor s).name), ("type", .str (evType s).name),
  ("allowed", .bool (Fw.Console.may (actor s) (evType s)))]

open Fw.Console.Self in
def opActor (req : Json) : Except String Reply := do
  let ss ← match ← optStr req "source" with
    | none => pure sources
    | some n => match Source.ofName n with
      | some s => pure [s]
      | none => throw s!"field source: unknown source {n}"
  pure [("sources", .arr (ss.toArray.map sourceJson))]

open Fw.Console.Alert in
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
                                  ("kind", .str a.kind.name), ("agent", .str a.agent),
                                  ("audience", .str a.audience.name), ("body", .str a.body)]),
        ("close", .arr (o.close.toArray.map fun s => Json.mkObj [("step", .str s), ("key", .str (closeKey s))]))]

open Fw.Plan.Trailer in
def opTrailers (req : Json) : Except String Reply := do
  let cs ← (← arr req "commits").toList.mapM fun c => do
    pure ({ sha := ← str c "sha", body := ← str c "body" } : Commit)
  let ts ← (← arr req "tasks").toList.mapM fun t => do
    pure (← str t "id", (← str t "state") == "done")
  pure [("done", .arr ((facts ts cs).toArray.map fun (x, s) =>
            Json.mkObj [("task", .str x), ("evidence", .str s)])),
        ("verdicts", .arr ((verdicts ts cs).toArray.map fun (x, s, v) =>
            Json.mkObj [("task", .str x), ("sha", .str s), ("verdict", .str v.name)]))]

open Fw.Console.Land in
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

open Fw.Console.Land in
def opLandLock (req : Json) : Except String Reply := do
  let held ← asBool "held" (← field req "held")
  let alive ← boolD req "alive" false
  let v := match lockVerdict held alive with | .free => "free" | .busy => "busy" | .stale => "stale"
  pure [("verdict", .str v)]

open Fw.Console.Land in
def opLandGuard (req : Json) : Except String Reply := do
  let held ← asBool "held" (← field req "held")
  let alive ← boolD req "alive" false
  let here ← boolD req "here" true
  let own ← boolD req "own" false
  let v := match guardVerdict held alive here own with | .allow => "allow" | .held => "held" | .stale => "stale"
  pure [("verdict", .str v), ("allow", .bool (v == "allow"))]

open Fw.Console.Land in
def opLandCommit (req : Json) : Except String Reply := do
  let locked ← asBool "locked" (← field req "locked")
  let merge ← optStr req "mergeHead"
  let head ← str req "head"
  let pre ← str req "pre"
  pure (match landTip locked merge head pre with
    | .ok t => [("ok", .bool true), ("tip", .str t), ("reason", .null)]
    | .error r => [("ok", .bool false), ("tip", .null), ("reason", .str r)])

open Fw.Console.Land in
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
def opLandPool (req : Json) : Except String Reply := do
  let c ← nat req "cores"
  let l ← nat req "load"
  pure [("pool", .num (poolFair c l))]

open Fw.Console.LandPool in
def opLandRetry (req : Json) : Except String Reply := do
  let p ← asBool "passed" (← field req "passed")
  let f ← asBool "loadFailure" (← field req "loadFailure")
  pure [("rerun", .bool (rerunAlone p f)), ("pool", .num rerunPool)]

open Fw.Console.LandTier in
def opLandTier (req : Json) : Except String Reply := do
  let ids ← strsD req "ids"
  let js (l : List String) : Json := .arr (l.toArray.map Json.str)
  let built ← match opt req "built" with
    | none | some .null => pure false
    | some j => asBool "built" j
  pure [("local", js (pick .onMac ids)), ("remote", js (pick .onCi ids)), ("browser", .bool (browserRuns ids)),
    ("build", .bool (needsBuild built (pick .onMac ids)))]

open Fw.Console.LandLegs in
def opLandLeg (req : Json) : Except String Reply := do
  let name ← asStr "leg" (← field req "leg")
  let ids ← strsD req "ids"
  match Leg.ofName? name with
  | none => throw s!"field leg: unknown land leg {name}"
  | some l =>
    pure [("ids", .arr ((pickFor l (Fw.Console.LandTier.pick .onCi ids)).toArray.map Json.str)), ("engine", .bool (engineRuns l ids))]

open Fw.Console.LandLegs in
def opLandLegs (req : Json) : Except String Reply := do
  let rs ← (← arrD req "results").mapM (asBool "results")
  pure [("ok", .bool (legsOk rs))]

open Fw.Console.LandLegs in
def opLandLegsVeto (req : Json) : Except String Reply := do
  let rs ← match opt req "results" with
    | none | some .null => pure none
    | some _ => some <$> (← arrD req "results").mapM (asBool "results")
  pure [("veto", .bool (legsVeto rs))]

open Fw.Console.LandTier in
def opLandLane (req : Json) : Except String Reply := do
  let e ← asBool "exitOk" (← field req "exitOk")
  let c ← asBool "coreUser" (← field req "coreUser")
  let n ← match opt req "skipped" with
    | none | some .null => pure none
    | some _ => some <$> nat req "skipped"
  let id ← match opt req "check" with
    | none | some .null => pure ""
    | some j => asStr "check" j
  let k := effectiveSkipped id n
  let v := laneVerdict e c k
  pure [("verdict", .str v.name), ("ok", .bool v.ok), ("skipped", match k with | some m => .num m | none => .null)]

open Fw.Console.LandRemote in
def opLandRemote (req : Json) : Except String Reply := do
  let l ← asBool "localOk" (← field req "localOk")
  let n ← asBool "needed" (← field req "needed")
  let allow ← (← arrD req "allow").mapM fun j => do
    let s ← asStr "allow" j
    match Provider.ofName s with | some p => pure p | none => throw s!"unknown provider {s}"
  let wj ← field req "want"
  let w : Want := { sha := ← strD wj "sha" "", laneId := ← strD wj "laneId" "", laneDigest := ← strD wj "laneDigest" "" }
  let k ← natD req "waitsLeft" 0
  let rs ← (← arrD req "runs").mapM fun r => do
    let ps ← strD r "provider" ""
    let st ← strD r "state" ""
    match Provider.ofName ps, RunState.ofName st with
    | some p, some s => pure ({ provider := p, sha := ← strD r "sha" "", laneId := ← strD r "laneId" "",
                                laneDigest := ← strD r "laneDigest" "", state := s } : Run)
    | none, _ => throw s!"unknown provider {ps}"
    | _, none => throw s!"unknown run state {st}"
  let v := verdict l n allow w k rs
  pure [("kind", .str v.kind), ("reason", .str v.reason), ("ok", .bool v.ok),
        ("provider", match v.provider with | some p => .str p.name | none => .null)]

open Fw.Console.LandRemote in
def opLandLaneState (req : Json) : Except String Reply := do
  let c ← natD req "exit" 2
  let t ← match opt req "timedOut" with | none | some .null => pure false | some _ => asBool "timedOut" (← field req "timedOut")
  let said ← match opt req "saidFail" with | none | some .null => pure true | some _ => asBool "saidFail" (← field req "saidFail")
  let jobs ← match opt req "jobs" with
    | none | some .null => pure none
    | some _ => some <$> (← arrD req "jobs").mapM jobOf
  let st ← strD req "status" ""
  let co ← strD req "conclusion" ""
  pure [("state", .str (laneState c t st co said jobs (← natD req "reads" 0)).name), ("reread", .bool (rereads c t st co jobs))]
where
  jobOf (j : Json) : Except String Job := do pure { status := ← strD j "status" "", conclusion := ← strD j "conclusion" "" }

open Fw.Console.LandRemote in
def opLandLegStates (req : Json) : Except String Reply := do
  let js ← (← arrD req "jobs").mapM opLandLaneState.jobOf
  pure [("legs", .arr (js.map fun j => Json.str (legState j).name).toArray)]

open Fw.Console.LandRemote in
def opLandDigest (req : Json) : Except String Reply := do
  pure [("digest", .str (laneDigest .onCi (← strsD req "ids")))]

open Fw.Land.RenderGuard in
def opLandRenderGuard (req : Json) : Except String Reply := do
  let ts ← (← arr req "tokens").toList.mapM (asStr "tokens")
  let hs := guard ts
  pure [("refuse", .bool !hs.isEmpty), ("hits", .arr (hs.toArray.map fun h =>
    Json.mkObj [("commit", .str h.commit), ("path", .str h.path), ("media", .str h.media.name)]))]

open Fw.Plan Fw.Plan.Lint in
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

open Fw.Console.Preview in
def actorOfName (name : String) : Except String Fw.Console.Actor :=
  match name with
  | "user" => .ok .user | "lead" => .ok .lead | "owner" => .ok .owner | "reviewer" => .ok .reviewer
  | "script" => .ok .script | "git" => .ok .git | "hook" => .ok .hook
  | _ => throw s!"field actor: unknown actor {name}"

open Fw.Console.Preview in
def proofOf (req : Json) : Except String Proof := do
  pure { secret := ← asBool "secret" (← field req "secret"), cookie := ← asBool "cookie" (← field req "cookie"),
         origin := ← asBool "origin" (← field req "origin") }

open Fw.Console.Preview in
def liveOf (req : Json) : Except String (List Pv) := do
  (← arrD req "live").mapM fun p => do
    pure ({ id := ← str p "id", task := ← str p "task", rp := ← nat p "rp", op := ← nat p "op", started := ← nat p "started" } : Pv)

open Fw.Console.Preview in
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
def opPreviewAdmit (req : Json) : Except String Reply := do
  let s ← liveOf req
  let p ← proofOf req
  let r : Req := { actor := p.actor, id := ← str req "preview", task := ← str req "task",
                   now := ← nat req "now", diskMb := ← nat req "diskMb", hasTarget := ← asBool "hasTarget" (← field req "hasTarget") }
  let lo ← match opt req "portBase" with
    | none => pure portLo
    | some _ => nat req "portBase"
  let lim := [("ttl", Json.num ttl), ("k", Json.num K), ("portLo", Json.num portLo), ("portN", Json.num portN), ("backendOff", Json.num backendOff), ("actor", Json.str (Fw.Console.Actor.name p.actor))]
  pure (match admit lo s r with
    | .error e => [("ok", .bool false), ("reason", .str e.name), ("rp", .null), ("op", .null), ("brp", .null), ("bop", .null), ("deadline", .null)] ++ lim
    | .ok (p :: _) => [("ok", .bool true), ("reason", .null), ("rp", .num p.rp), ("op", .num p.op),
        ("brp", .num (Fw.Console.Preview.Arm.backendOf p.rp)), ("bop", .num (Fw.Console.Preview.Arm.backendOf p.op)), ("deadline", .num p.deadline)] ++ lim
    | .ok [] => [("ok", .bool false), ("reason", .str "noPorts"), ("rp", .null), ("op", .null), ("brp", .null), ("bop", .null), ("deadline", .null)] ++ lim)

open Fw.Console.Preview in
def idsJson (s : List Pv) : Json := .arr (s.toArray.map fun p => Json.str p.id)

open Fw.Console.Preview in
def opPreviewTick (req : Json) : Except String Reply := do
  let s ← liveOf req
  let now ← nat req "now"
  pure [("keep", idsJson (tick s now)), ("kill", idsJson (expired s now))]

open Fw.Console.Preview in
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
def opPreviewFail (req : Json) : Except String Reply := do
  let s ← liveOf req
  let i ← str req "preview"
  pure [("keep", idsJson (fail s i)), ("kill", idsJson (own s i))]

open Fw.Console.Preview in
def opPreviewReap (req : Json) : Except String Reply := do
  pure [("kill", idsJson (reap (← liveOf req)).2)]

open Fw.Console.Preview in
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
      let viaGrant := allowGrant lan hostOk (← flag "grant") (← num "grantStarted") (← num "now") c
      pure (servePreview lan session hostOk (← flag "grant") (← num "grantStarted") (← num "now") c,
        if viaSession then "session" else if viaGrant then "grant" else "none")
    | _ => throw "field port: expected console or preview"
  pure [("allow", .bool ok), ("class", .str c.name), ("by", .str (if ok then by_ else "none"))]

open Fw.Console.Preview.Arm in
def opPreviewArm (req : Json) : Except String Reply := do
  let s ← liveOf req
  let lan ← asBool "lan" (← field req "lan")
  let session ← asBool "session" (← field req "session")
  let hostOk ← asBool "hostOk" (← field req "hostOk")
  let flag (k : String) : Except String Bool := match opt req k with
    | none => pure false
    | some j => asBool k j
  let num (k : String) : Except String Nat := match opt req k with
    | none => pure 0
    | some _ => nat req k
  let known ← flag "grant"
  let started ← num "grantStarted"
  let now ← num "now"
  let ok := armServe lan session hostOk known started now
  let by_ := if !ok then "none" else if Fw.Console.Preview.Owner.allowPreview lan session hostOk then "session" else "grant"
  let path ← str req "path"
  let act := match route s (← nat req "port") path with
    | .proxy i a b p => [("act", Json.str "proxy"), ("preview", .str i), ("arm", .str a.name), ("backend", .num b), ("path", .str p)]
    | .refuse => [("act", Json.str "refuse"), ("preview", .null), ("arm", .null), ("backend", .null), ("path", .null)]
  pure ([("allow", Json.bool ok), ("by", .str by_)] ++ act)

open Fw.Console.Preview.Return in
def opLoginReturn (req : Json) : Except String Reply := do
  let s ← liveOf req
  let cp ← nat req "consolePort"
  let pp : Option Nat ← match opt req "previewPort" with
    | none | some .null => pure none
    | some _ => do pure (some (← nat req "previewPort"))
  let host ← str req "host"
  let hosts ← (← arr req "hosts").toList.mapM (asStr "hosts")
  let consts := [("ttlMs", Json.num ttl), ("cap", .num cap)]
  match ← str req "kind" with
  | "redirect" =>
    let nonce ← str req "nonce"
    let t : Target := { port := ← nat req "port", pathq := ← str req "path" }
    let get := (← str req "method") == "GET"
    match redirect get (← asBool "html" (← field req "html")) hosts (← nat req "heldCount") host nonce s cp pp t with
    | .deny => pure ([("act", Json.str "deny"), ("keep", .bool false), ("location", .null)] ++ consts)
    | .login k => pure ([("act", Json.str "login"), ("keep", .bool k), ("location", .str (loginUrl host cp nonce k))] ++ consts)
  | "land" =>
    let held : Option (Target × Nat) ← match opt req "held" with
      | none | some .null => pure none
      | some j => do pure (some ({ port := ← nat j "port", pathq := ← str j "path" }, ← nat j "issuedAt"))
    let l := landing hosts s cp pp host (← nat req "now") held
    let to := match l with | .target _ => "target" | .builds => "builds" | .home => "home"
    pure ([("to", Json.str to), ("next", .str l.next)] ++ consts)
  | _ => throw "field kind: expected redirect or land"

open Fw.Console.Preview.Owner in
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
def opLanStart (req : Json) : Except String Reply := do
  let r := lanStart (← asBool "want" (← field req "want")) (← asBool "hasAddr" (← field req "hasAddr"))
    (← asBool "hasPass" (← field req "hasPass")) (← nat req "passLen")
  pure [("result", .str r), ("start", .bool (r == "start"))]

open Fw.Console.Preview.Owner in
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
def opPreviewCache (req : Json) : Except String Reply := do
  let names ← (← arrD req "manifest").mapM (asStr "manifest")
  let k := kind names (← str req "path")
  let name := match k with | .hashed => "hashed" | .html => "html" | .other => "other"
  pure [("kind", .str name), ("cacheControl", .str (cacheControl k)), ("immutable", .bool (reusesWithoutAsking k)),
        ("compress", .bool (compressible (← str req "path")))]


open Fw.Console.Builds in
def buildTargetJson : Fw.Console.Preview.Target → Json
  | .main s => Json.mkObj [("kind", "main"), ("ref", "main"), ("sha", s)]
  | _ => Json.null

def strPairs (k : String) : Json → Except String (List (String × String))
  | .obj kvs => kvs.toList.mapM fun kv => do pure (kv.1, ← asStr k kv.2)
  | _ => .error s!"field {k}: expected an object"

open Fw.Console.Builds in
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
def opBuildsPicker (req : Json) : Except String Reply := do
  let keys ← (← arrD req "keys").mapM (asStr "keys")
  let cur ← strD req "current" ""
  pure [("searches", Json.arr ((picker keys).map Json.str).toArray), ("current", Json.str (choose keys cur))]

open Fw.Console.BuildsOpen in
def strListPairs (k : String) : Json → Except String (List (String × List String))
  | .obj kvs => kvs.toList.mapM fun kv => do
      match kv.2 with
      | .arr a => pure (kv.1, ← a.toList.mapM (asStr k))
      | _ => throw s!"field {k}: expected an array of strings"
  | _ => throw s!"field {k}: expected an object"

open Fw.Console.BuildsOpen in
def registryOf (j : Json) : Except String (List PartFact × List PresetFact) := do
  let r ← field j "registry"
  let parts ← (← arrD r "parts").mapM fun p => do
    pure ({ id := ← str p "id", variants := ← (← arrD p "variants").mapM (asStr "variants"),
            impls := ← (← arrD p "impls").mapM (asStr "impls"),
            requires := ← (match opt p "requires" with | none => pure [] | some v => strListPairs "requires" v),
            conflicts := ← (match opt p "conflicts" with | none => pure [] | some v => strListPairs "conflicts" v),
            layers := ← (← arrD p "layers").mapM (asStr "layers") } : PartFact)
  let presets ← (← arrD r "presets").mapM fun p => do
    pure ({ name := ← str p "name",
            base := (match opt p "extends" with | some (.str b) => some b | _ => none),
            fw := ← (match opt p "fw" with | none => pure [] | some v => strPairs "fw" v) } : PresetFact)
  pure (parts, presets)

open Fw.Console.BuildsOpen in
def opBuildsSearch (req : Json) : Except String Reply := do
  let (parts, presets) ← registryOf req
  match validate parts presets (← str req "search") with
  | .ok c => pure [("ok", .bool true), ("canonical", .str c), ("reasons", Json.arr #[])]
  | .refused rs => pure [("ok", .bool false), ("canonical", Json.null), ("reasons", Json.arr (rs.map Json.str).toArray)]

open Fw.Console.BuildsOpen in
def opBuildsOpen (req : Json) : Except String Reply := do
  let pvs ← (← arrD req "previews").mapM fun p => do
    pure ({ id := ← str p "id", slot := ← str p "slot", sha := ← str p "sha", serving := ← boolD p "serving" false } : PvFact)
  let arm ← match ← strD req "arm" "r" with
    | "r" => pure Arm.rewrite
    | "compare" => pure Arm.compare
    | _ => throw "field arm: expected r or compare"
  let o ← match ← str req "mode" with
    | "row" => pure (openRow pvs (← str req "slot") (← str req "sha") (← strD req "search" ""))
    | "search" =>
      let (parts, presets) ← registryOf req
      pure (openSearch parts presets pvs (← str req "main") (← str req "search"))
    | _ => throw "field mode: expected row or search"
  match o with
  | .refused rs => pure [("ok", .bool false), ("reasons", Json.arr (rs.map Json.str).toArray), ("canonical", Json.null),
      ("act", Json.null), ("preview", Json.null), ("slot", Json.null), ("sha", Json.null), ("path", Json.null), ("url", Json.null)]
  | .go act c slot sha =>
    let lan ← boolD req "lan" false
    let lanAddr : Option String := match opt req "lanAddr" with | some (.str a) => some a | _ => none
    let port ← match opt req "port" with | none => pure 0 | some _ => nat req "port"
    let (name, id) : String × Option String := match act with
      | .reuse i => ("reuse", some i) | .wait i => ("wait", some i) | .rebuild i => ("rebuild", some i) | .start => ("start", none)
    let (pth, url) : Json × Json := match act with
      | .reuse i => let p := path i arm c; (.str p, .str (fullUrl lan lanAddr port p))
      | _ => (Json.null, Json.null)
    pure [("ok", .bool true), ("reasons", Json.arr #[]), ("canonical", .str c), ("act", .str name),
      ("preview", match id with | some i => .str i | none => Json.null), ("slot", .str slot), ("sha", .str sha), ("path", pth), ("url", url)]

open Fw.Console.Daemon in
def opDaemon (req : Json) : Except String Reply := do
  let pid (k : String) : Except String (Option Nat) := match opt req k with
    | none | some .null => pure none
    | some _ => do pure (some (← nat req k))
  let pj : Option Nat → Json := fun o => match o with | some p => Json.num p | none => Json.null
  match ← str req "kind" with
  | "start" =>
    let r ← pid "recorded"; let a ← pid "answered"
    let live ← boolD req "alive" false
    pure [("allow", .bool (startAllowed r a live)), ("verified", pj (verified r a)),
      ("reason", .str (if (verified r a).isSome then "running" else if unverifiedAlive r a live then "unverifiedAlive" else "ok"))]
  | "stop" =>
    let t := stopTarget (← pid "recorded") (← pid "answered")
    pure [("target", pj t), ("reason", .str (if t.isSome then "ok" else "notRunning"))]
  | "restart" =>
    let steps := restartPlan (verified (← pid "recorded") (← pid "answered"))
    pure [("steps", Json.arr (steps.toArray.map fun s => match s with
      | .stop p => Json.mkObj [("step", .str "stop"), ("pid", .num p)]
      | .start => Json.mkObj [("step", .str "start")]))]
  | "rotate" =>
    let limit ← match opt req "limit" with
      | none => pure logLimit
      | some _ => nat req "limit"
    let size ← nat req "size"
    pure [("rotate", .bool (rotate size limit)), ("limit", .num limit), ("warn", .bool (logWarns size)), ("warnLimit", .num logWarnLimit)]
  | _ => throw "field kind: expected start, stop, restart or rotate"

def ops : List String := ["console.landReadiness", "console.actor", "console.alert", "console.landScope", "console.landLock", "console.landGuard",
  "console.landCommit", "console.landPick", "console.landPool", "console.landRetry", "console.landTier", "console.landLeg", "console.landLegs", "console.landLegsVeto", "console.landLane", "console.landRemote", "console.landLaneState", "console.landLegStates", "console.landDigest", "console.landRenderGuard", "plan.trailers", "plan.lint",
  "console.previewTarget", "console.previewAdmit", "console.previewTick", "console.previewStop", "console.previewFail", "console.previewReap", "console.previewLink",
  "console.ownerLogin", "console.ownerGate", "console.previewGrant", "console.ownerAction", "console.previewArm", "console.loginReturn", "console.lanStart", "console.previewSweep", "console.previewCache", "console.builds", "console.buildsPicker", "console.buildsSearch", "console.buildsOpen", "console.compose", "console.review", "console.reviewPreview", "console.reviewFeedback", "console.report", "console.stepTopics", "console.reviewInfo", "console.reviewExcerpt", "console.daemon"]

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
  | "console.landLeg" => some (opLandLeg req)
  | "console.landLegs" => some (opLandLegs req)
  | "console.landLegsVeto" => some (opLandLegsVeto req)
  | "console.landLane" => some (opLandLane req)
  | "console.landRemote" => some (opLandRemote req)
  | "console.landLaneState" => some (opLandLaneState req)
  | "console.landLegStates" => some (opLandLegStates req)
  | "console.landDigest" => some (opLandDigest req)
  | "console.landRenderGuard" => some (opLandRenderGuard req)
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
  | "console.previewArm" => some (opPreviewArm req)
  | "console.loginReturn" => some (opLoginReturn req)
  | "console.lanStart" => some (opLanStart req)
  | "console.previewSweep" => some (opPreviewSweep req)
  | "console.previewCache" => some (opPreviewCache req)
  | "console.builds" => some (opBuilds req)
  | "console.buildsPicker" => some (opBuildsPicker req)
  | "console.buildsSearch" => some (opBuildsSearch req)
  | "console.buildsOpen" => some (opBuildsOpen req)
  | "console.compose" => some (Fw.Wire.Layers.opComposeArms req)
  | "console.review" => some (Fw.Wire.Review.opReview req)
  | "console.reviewPreview" => some (Fw.Wire.ReviewPreview.opReviewPreview req)
  | "console.reviewFeedback" => some (Fw.Wire.ReviewFeedback.opReviewFeedback req)
  | "console.report" => some (Fw.Wire.Report.opReport req)
  | "console.stepTopics" => some (Fw.Wire.Steps.opStepTopics req)
  | "console.reviewInfo" => some (Fw.Wire.ReviewInfo.opReviewInfo req)
  | "console.reviewExcerpt" => some (Fw.Wire.ReviewInfo.opReviewExcerpt req)
  | "console.daemon" => some (opDaemon req)
  | _ => none

end Fw.Wire.Console
