import Lean.Data.Json
import Fw.Ci.PoolTier
import Fw.Ci.Pool.FallbackWire
import Fw.Ops.Wire
namespace Fw.Wire.CiPoolTier
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD optN)
open Fw.Wire.CiPool (strsD strD strsJson cfgJson stateJson reqOf targetJson engineName)
open Fw.Ci.PoolTier
open Fw.Ci.Pool.Fallback (Req Target)

def viaName : Via → String
  | .github => "github"
  | .codemagic => "codemagic"
  | .circleci => "circleci"
  | .bitrise => "bitrise"

def pool7Over : Json := Json.mkObj [("circleMacAllow", strsJson ["webkit-sim"]),
  ("circleCaps", Json.mkObj [("webkit-sim", (40 : Nat))]), ("circleShortMaxMin", (40 : Nat))]

def cfgOf (req : Json) : Except String Cfg := do
  let o := (opt req "over").getD (Json.mkObj [])
  let base ← Fw.Wire.CiPool.cfgOf (Json.mkObj [("cfg", "phase1"), ("over", pool7Over.mergeObj o)])
  let cmOn ← boolD o "cmOn" pool7.cmOn
  let cmCls ← strD o "cmCls" pool7.cmCls
  let cmConc ← natD o "cmConc" pool7.cmConc
  let cmCapMin ← natD o "cmCapMin" pool7.cmCapMin
  let cmAllow ← strsD o "cmAllow" pool7.cmAllow
  pure ⟨base, cmOn, cmCls, cmConc, cmCapMin, cmAllow⟩

def stateOf (j : Json) : Except String State := do
  pure ⟨← Fw.Wire.CiPool.stateOf j, ← natD j "cmBusy" 0, ← natD j "cmUsed" 0, ← natD j "ccSpent" 0, ← natD j "ccStorage" 0⟩

def stateJson' (s : State) : Json :=
  (stateJson s.base).mergeObj (Json.mkObj [("cmBusy", s.cmBusy), ("cmUsed", s.cmUsed), ("ccSpent", s.ccSpent),
    ("ccStorage", s.ccStorage)])

def cfgJson' (c : Cfg) : Json :=
  (cfgJson c.base).mergeObj (Json.mkObj [("cmOn", c.cmOn), ("cmCls", c.cmCls), ("cmConc", c.cmConc),
    ("cmCapMin", c.cmCapMin), ("cmAllow", strsJson c.cmAllow)])

def rowJson (p : Req × Decision) : Json :=
  let k := p.1.key
  let head : List (String × Json) :=
    [("sha", k.sha), ("lane", k.lane), ("cfg", k.cfg), ("rep", k.rep), ("attempt", p.1.attempt),
      ("via", match p.2.via with | some v => Json.str (viaName v) | none => .null)]
  Json.mkObj <| head ++ match p.2 with
    | .codemagic cls e m => [("decision", "codemagic"),
        ("target", Json.mkObj [("via", "codemagic"), ("os", "macos"), ("cls", cls), ("engine", engineName e), ("timeoutMin", m),
          ("credits", (0 : Nat))])]
    | .base (.run t) => [("decision", "run"), ("target", targetJson t)]
    | .base .wait => [("decision", "wait")]
    | .base (.done o) => [("decision", "done"), ("outcome", o.tag)]

def counts (l : List (Req × Decision)) : Json :=
  Json.mkObj ([Via.github, .codemagic, .circleci, .bitrise].map fun v =>
    (viaName v, toJson (l.filter (·.2.via == some v)).length))

def opTier (req : Json) : Except String Reply := do
  let c ← cfgOf req
  let s ← stateOf (← field req "state")
  let rs ← (← arr req "reqs").toList.mapM reqOf
  let o := step c rs s
  pure [("log", .arr (o.1.map rowJson).toArray), ("counts", counts o.1), ("inflight", inflight o.2), ("macCap", macCap c),
    ("ghOk", Fw.Ci.Pool.Fallback.ghOk c.base (s.fb c)), ("cmOk", match rs with | r :: _ => toJson (cmOk c r s) | [] => .null),
    ("ccLeft", (s.fb c).circleCreditsLeft),
    ("ccStorageCredits", Fw.Ci.Provider.storageCredits s.ccStorage), ("state", stateJson' o.2)]

def sources : List (String × String × String) := [
  ("circleMacAllow", "CONFIRMED", "task macos-pool-7 (user 2026-10-21): CircleCI takes the seventh macOS job of webkit-sim, within the Fw.Ci.Overflow stop rules"),
  ("circleCaps", "INFERRED", "webkit-sim 40 min: the Codemagic cap of the same job (codemagic.yaml max_build_duration); no m4pro run of webkit-sim has finished yet"),
  ("circleShortMaxMin", "INFERRED", "40: admits the webkit-sim cap; the CircleCI stop rule Fw.Ci.Provider.capMs is 60 min"),
  ("cmCls", "CONFIRMED", "codemagic.yaml instance_type mac_mini_m2, the free personal-plan machine (codemagic.io/pricing, checked 2026-10-21)"),
  ("cmConc", "CONFIRMED", "codemagic.io/pricing: the free personal plan runs one build at a time"),
  ("cmCapMin", "CONFIRMED", "Fw.Ci.Codemagic.maxCapMin, the max_build_duration of codemagic.yaml"),
  ("cmAllow", "CONFIRMED", "codemagic.yaml has one workflow, webkit-sim; its cell is the original arm or, with FW_TARGET=rewrite, the rewrite arm built from the same commit (lane webkit-sim-rewrite)")]

def opConsts (req : Json) : Except String Reply := do
  let c ← cfgOf req
  pure [("cfg", cfgJson' c), ("macCap", macCap c), ("stopAt", Fw.Ci.Codemagic.stopAt),
    ("sources", .arr (sources.map fun (k, st, src) => Json.mkObj [("constant", k), ("status", st), ("source", src)]).toArray)]

/-- `ci.poolCell`: `{target, ghDigest?, cmDigest?}` to `{lane, routable, needsDigest, filed}`. -/
def opCell (req : Json) : Except String Reply := do
  let t ← str req "target"
  let dig (k : String) : Except String (Option String) :=
    match (opt req k) with
    | none => pure none
    | some Json.null => pure none
    | some j => do pure (some (← asStr k j))
  let gh ← dig "ghDigest"
  let cm ← dig "cmDigest"
  let lane := laneOfTarget t
  pure [("lane", match lane with | some l => Json.str l | none => .null), ("routable", routableTarget pool7 t),
    ("needsDigest", lane == some rewriteLane), ("filed", match lane with | some l => toJson (cellFiled l gh cm) | none => toJson false)]

/-- A platform key from JSON: the three builds and `cpus`, `memsize` (absent or 0: not read). -/
def keyOf (o : Json) : Except String PlatformKey := do
  pure ⟨← strD o "macosBuild" "", ← strD o "xcodeBuild" "", ← strD o "runtimeBuild" "", ⟨← natD o "cpus" 0, ← natD o "memsize" 0⟩⟩

/-- `ci.cellMerged`: `{ref:{macosBuild,xcodeBuild,runtimeBuild,cpus,memsize}, cell:{...}}` to `{merged}`. -/
def opMerged (req : Json) : Except String Reply := do
  let r ← keyOf (← field req "ref")
  let c ← keyOf (← field req "cell")
  pure [("merged", cellMerged r c)]

def classOf (o : Json) (k : String) : Except String RowClass := do
  let w ← str o k
  match RowClass.ofString w with
  | some c => pure c
  | none => throw s!"{k}: unknown class {w}"

def className : RowClass → String
  | .deterministic => "deterministic"
  | .stable => "stable"
  | .quarantined => "quarantined"

def useName : Use → String
  | .direct => "direct"
  | .paired => "paired"
  | .refused => "refused"

def obsOf (o : Json) : Except String Obs := do
  pure ⟨← classOf o "gh", ← classOf o "cm", ← keyOf (← field o "ghKey"), ← keyOf (← field o "cmKey")⟩

/-- `ci.poolRows`: `{ref, cell, rows:[{row, obs:[{gh, cm, ghKey, cmKey}]}], used?}` to the use of each row
(`direct`, `paired` with its class, `refused`), the counts, `kReq` and `reachable` pairs under the Codemagic line. -/
def opRows (req : Json) : Except String Reply := do
  let r ← keyOf (← field req "ref")
  let c ← keyOf (← field req "cell")
  let used ← natD req "used" 0
  let rows ← (← arr req "rows").toList.mapM fun j => do
    let obs ← (← arr j "obs").toList.mapM obsOf
    pure (← str j "row", obs)
  let out := rows.map fun (n, obs) =>
    let u := rowUse r c obs
    Json.mkObj ([("row", Json.str n), ("use", Json.str (useName u))] ++
      (if u == .paired then [("class", Json.str (className (pairedClass obs)))] else []))
  let cnt (u : Use) : Json := toJson (rows.filter fun x => rowUse r c x.2 == u).length
  pure [("kReq", kReq), ("reachable", pairsReachable used), ("merged", cellMerged r c), ("rows", .arr out.toArray),
    ("counts", Json.mkObj [("direct", cnt .direct), ("paired", cnt .paired), ("refused", cnt .refused)])]

def queuedOf (j : Json) : Except String Queued := do
  pure ⟨← reqOf j, ← natD j "queuedS" 0, ← natD j "runCells" 0⟩

/-- `ci.reroute`: the tier request with `queued` (each a request plus `queuedS`) instead of `reqs`; a queued job moves to
Codemagic when it has waited 300 s, is the only unfinished cell of its run (`runCells` 1; absent = 0) and the route sends it there. Reply `log` rows have `reroute`. -/
def opReroute (req : Json) : Except String Reply := do
  let c ← cfgOf req
  let s ← stateOf (← field req "state")
  let qs ← (← arr req "queued").toList.mapM queuedOf
  let o := reroutePlan c qs s
  let aged := qs.filter Queued.movable
  let rows := (aged.zip o.1).map fun (q, p) =>
    Json.mkObj [("sha", q.req.key.sha), ("lane", q.req.key.lane), ("cfg", q.req.key.cfg), ("rep", q.req.key.rep),
      ("queuedS", q.queuedS), ("runCells", q.runCells), ("reroute", p.2.isCm)]
  pure [("log", .arr rows.toArray), ("moved", cmCount o.1), ("skipped", qs.length - aged.length), ("state", stateJson' o.2)]

def ops : List String := ["ci.poolTier", "ci.poolTierConsts", "ci.poolCell", "ci.cellMerged", "ci.poolRows", "ci.reroute"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ci.poolTier" => some (opTier req)
  | "ci.poolTierConsts" => some (opConsts req)
  | "ci.poolCell" => some (opCell req)
  | "ci.cellMerged" => some (opMerged req)
  | "ci.poolRows" => some (opRows req)
  | "ci.reroute" => some (opReroute req)
  | _ => none

#guard (cfgOf (Json.mkObj [])).toOption == some pool7
#guard ((cfgOf (Json.mkObj [("over", Json.mkObj [("cmOn", false), ("ghMacCap", (50 : Nat))])])).toOption.map
  fun c => (c.cmOn, c.base.ghMacCap, c.base.circleMacAllow)) == some (false, 50, ["webkit-sim"])

private def run (op r : String) : String :=
  match Json.parse r with
  | .ok j => match handle op j with
    | some (.ok f) => (Json.mkObj f).compress
    | some (.error e) => s!"error: {e}"
    | none => "unknown op"
  | .error e => s!"parse: {e}"

private def runField (op r k : String) : String :=
  match Json.parse (run op r) with
  | .ok j => match j.getObjVal? k with
    | .ok v => v.compress
    | .error _ => "absent"
  | .error _ => run op r

private def rq (rep : Nat) : String :=
  "{\"sha\":\"0123456789abcdef0123456789abcdef01234567\",\"lane\":\"webkit-sim\",\"cfg\":\"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\",\"rep\":" ++
    toString rep ++ ",\"engine\":\"iosSimSafari\",\"image\":\"xcode-27\",\"capMin\":40}"

private def seven : String := "[" ++ ",".intercalate ((List.range 8).map rq) ++ "]"

#guard runField "ci.poolTier" ("{\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0,\"cmUsed\":46,\"ccSpent\":3575},\"reqs\":" ++ seven ++ "}") "counts" ==
  "{\"bitrise\":0,\"circleci\":1,\"codemagic\":1,\"github\":5}"
#guard runField "ci.poolTier" ("{\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0,\"cmUsed\":46,\"ccSpent\":3575},\"reqs\":" ++ seven ++ "}") "inflight" == "7"
#guard runField "ci.poolTier" ("{\"state\":{\"ghMacBusy\":5,\"ghTotalBusy\":5,\"cmUsed\":361},\"reqs\":[" ++ rq 0 ++ "]}") "cmOk" == "false"
#guard runField "ci.poolTierConsts" "{}" "macCap" == "7"
#guard run "ci.poolCell" "{\"target\":\"rewrite\",\"ghDigest\":\"ab\",\"cmDigest\":\"ab\"}" ==
  "{\"filed\":true,\"lane\":\"webkit-sim-rewrite\",\"needsDigest\":true,\"routable\":true}"
#guard runField "ci.poolCell" "{\"target\":\"rewrite\",\"ghDigest\":\"ab\",\"cmDigest\":\"cd\"}" "filed" == "false"
#guard runField "ci.poolCell" "{\"target\":\"both\"}" "routable" == "false"
#guard run "ci.cellMerged" "{\"ref\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\",\"cpus\":3,\"memsize\":7},\"cell\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\",\"cpus\":3,\"memsize\":7}}" == "{\"merged\":true}"
#guard run "ci.cellMerged" "{\"ref\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\",\"cpus\":3,\"memsize\":7},\"cell\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"cpus\":3,\"memsize\":7}}" == "{\"merged\":false}"
#guard run "ci.cellMerged" "{\"ref\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\",\"cpus\":3,\"memsize\":7},\"cell\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\",\"cpus\":8,\"memsize\":7}}" == "{\"merged\":false}"
#guard run "ci.cellMerged" "{\"ref\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\"},\"cell\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\"}}" == "{\"merged\":false}"
#guard run "ci.poolTier" "{\"over\":{\"cmConc\":\"x\"},\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[]}" |>.startsWith "error: "

end Fw.Wire.CiPoolTier
