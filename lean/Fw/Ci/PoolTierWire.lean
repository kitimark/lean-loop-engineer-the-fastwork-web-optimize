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

/-- `ci.poolCell`: for a count target (and optionally the two site digests) the pool lane, whether the target is routable and
whether the finished Codemagic cell may be filed. `{target, ghDigest?, cmDigest?}`. -/
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

/-- `ci.cellMerged`: whether a Codemagic cell's toolchain key may be pooled with the key of the GitHub cell v1.
`{ref:{macosBuild,xcodeBuild,runtimeBuild}, cell:{...}}`; a missing component reads as empty and refuses. -/
def opMerged (req : Json) : Except String Reply := do
  let key (k : String) : Except String PlatformKey := do
    let o ← field req k
    pure ⟨← strD o "macosBuild" "", ← strD o "xcodeBuild" "", ← strD o "runtimeBuild" ""⟩
  let r ← key "ref"
  let c ← key "cell"
  pure [("merged", cellMerged r c)]

def ops : List String := ["ci.poolTier", "ci.poolTierConsts", "ci.poolCell", "ci.cellMerged"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ci.poolTier" => some (opTier req)
  | "ci.poolTierConsts" => some (opConsts req)
  | "ci.poolCell" => some (opCell req)
  | "ci.cellMerged" => some (opMerged req)
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
#guard run "ci.cellMerged" "{\"ref\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\"},\"cell\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\"}}" == "{\"merged\":true}"
#guard run "ci.cellMerged" "{\"ref\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\",\"runtimeBuild\":\"c\"},\"cell\":{\"macosBuild\":\"a\",\"xcodeBuild\":\"b\"}}" == "{\"merged\":false}"
#guard run "ci.poolTier" "{\"over\":{\"cmConc\":\"x\"},\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[]}" |>.startsWith "error: "

end Fw.Wire.CiPoolTier
