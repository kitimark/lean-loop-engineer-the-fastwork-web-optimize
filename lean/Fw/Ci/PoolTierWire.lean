import Lean.Data.Json
import Fw.Ci.PoolTier
import Fw.Ci.Pool.FallbackWire
import Fw.Ops.Wire
/-!
# The ops `ci.poolTier` and `ci.poolTierConsts` (rule `Fw.Ci.PoolTier`; shapes in docs/team/tools/ci-pool.md)

| op | request | reply |
|---|---|---|
| `ci.poolTier` | `over`? (fields of `pool7` replaced), `state` (the `ci.poolRoute` state plus `cmBusy`, `cmUsed`, `ccSpent`, `ccStorage`), `reqs` [Req] | `log` [row with `decision` `codemagic`, `run`, `wait` or `done` and `via`], `counts` {via: n}, `inflight`, `macCap`, `ghOk`, `cmOk` (for the first request), `ccLeft`, `ccStorageClear`, `state` |
| `ci.poolTierConsts` | `over`? | `cfg`, `macCap`, `sources` |
-/
namespace Fw.Wire.CiPoolTier
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD optN)
open Fw.Wire.CiPool (strsD strD strsJson cfgJson stateJson reqOf targetJson engineName)
open Fw.Ci.PoolTier
open Fw.Ci.Pool.Fallback (Req Target)

/-- The wire name of a pool provider. -/
def viaName : Via → String
  | .github => "github"
  | .codemagic => "codemagic"
  | .circleci => "circleci"
  | .bitrise => "bitrise"

/-- The fields by which `pool7.base` differs from `Fw.Ci.Pool.Fallback.phase1`, as a `ci.poolRoute` `over`. -/
def pool7Over : Json := Json.mkObj [("circleMacAllow", strsJson ["webkit-sim"]),
  ("circleCaps", Json.mkObj [("webkit-sim", (40 : Nat))]), ("circleShortMaxMin", (40 : Nat))]

/-- `pool7` with the fields of the request's `over` replaced (fallback and Codemagic fields alike). -/
def cfgOf (req : Json) : Except String Cfg := do
  let o := (opt req "over").getD (Json.mkObj [])
  let base ← Fw.Wire.CiPool.cfgOf (Json.mkObj [("cfg", "phase1"), ("over", pool7Over.mergeObj o)])
  let cmOn ← boolD o "cmOn" pool7.cmOn
  let cmCls ← strD o "cmCls" pool7.cmCls
  let cmConc ← natD o "cmConc" pool7.cmConc
  let cmCapMin ← natD o "cmCapMin" pool7.cmCapMin
  let cmAllow ← strsD o "cmAllow" pool7.cmAllow
  pure ⟨base, cmOn, cmCls, cmConc, cmCapMin, cmAllow⟩

/-- The pool state from JSON: the fallback state (its `circleCreditsLeft` is not read) and the two tiers' facts. -/
def stateOf (j : Json) : Except String State := do
  pure ⟨← Fw.Wire.CiPool.stateOf j, ← natD j "cmBusy" 0, ← natD j "cmUsed" 0, ← natD j "ccSpent" 0, ← natD j "ccStorage" 0⟩

/-- The pool state as JSON. -/
def stateJson' (s : State) : Json :=
  (stateJson s.base).mergeObj (Json.mkObj [("cmBusy", s.cmBusy), ("cmUsed", s.cmUsed), ("ccSpent", s.ccSpent),
    ("ccStorage", s.ccStorage)])

/-- The pool constants as JSON. -/
def cfgJson' (c : Cfg) : Json :=
  (cfgJson c.base).mergeObj (Json.mkObj [("cmOn", c.cmOn), ("cmCls", c.cmCls), ("cmConc", c.cmConc),
    ("cmCapMin", c.cmCapMin), ("cmAllow", strsJson c.cmAllow)])

/-- One log row as JSON. -/
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

/-- How many decisions of a tick each provider takes. -/
def counts (l : List (Req × Decision)) : Json :=
  Json.mkObj ([Via.github, .codemagic, .circleci, .bitrise].map fun v =>
    (viaName v, toJson (l.filter (·.2.via == some v)).length))

/-- `ci.poolTier`. -/
def opTier (req : Json) : Except String Reply := do
  let c ← cfgOf req
  let s ← stateOf (← field req "state")
  let rs ← (← arr req "reqs").toList.mapM reqOf
  let o := step c rs s
  pure [("log", .arr (o.1.map rowJson).toArray), ("counts", counts o.1), ("inflight", inflight o.2), ("macCap", macCap c),
    ("ghOk", Fw.Ci.Pool.Fallback.ghOk c.base (s.fb c)), ("cmOk", match rs with | r :: _ => toJson (cmOk c r s) | [] => .null),
    ("ccLeft", Fw.Ci.Overflow.classLeft c.base.circleCls s.ccSpent),
    ("ccStorageClear", Fw.Ci.Overflow.storageClearAt s.ccStorage), ("state", stateJson' o.2)]

/-- Each constant `pool7` adds to `Fw.Ci.Pool.Fallback.phase1`, with its status and source. -/
def sources : List (String × String × String) := [
  ("circleMacAllow", "CONFIRMED", "task macos-pool-7 (user 2026-10-21): CircleCI takes the seventh macOS job of webkit-sim, within the Fw.Ci.Overflow stop rules"),
  ("circleCaps", "INFERRED", "webkit-sim 40 min: the Codemagic cap of the same job (codemagic.yaml max_build_duration); no m4pro run of webkit-sim has finished yet"),
  ("circleShortMaxMin", "INFERRED", "40: admits the webkit-sim cap; the CircleCI stop rule Fw.Ci.Provider.capMs is 60 min"),
  ("cmCls", "CONFIRMED", "codemagic.yaml instance_type mac_mini_m2, the free personal-plan machine (codemagic.io/pricing, checked 2026-10-21)"),
  ("cmConc", "CONFIRMED", "codemagic.io/pricing: the free personal plan runs one build at a time"),
  ("cmCapMin", "CONFIRMED", "Fw.Ci.Codemagic.maxCapMin, the max_build_duration of codemagic.yaml"),
  ("cmAllow", "CONFIRMED", "codemagic.yaml has one workflow, webkit-sim")]

/-- `ci.poolTierConsts`. -/
def opConsts (req : Json) : Except String Reply := do
  let c ← cfgOf req
  pure [("cfg", cfgJson' c), ("macCap", macCap c), ("stopAt", Fw.Ci.Codemagic.stopAt),
    ("sources", .arr (sources.map fun (k, st, src) => Json.mkObj [("constant", k), ("status", st), ("source", src)]).toArray)]

/-- The ops of this module. -/
def ops : List String := ["ci.poolTier", "ci.poolTierConsts"]

/-- Dispatch an op of this module (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ci.poolTier" => some (opTier req)
  | "ci.poolTierConsts" => some (opConsts req)
  | _ => none

/-! ## Examples -/

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
#guard run "ci.poolTier" "{\"over\":{\"cmConc\":\"x\"},\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[]}" |>.startsWith "error: "

end Fw.Wire.CiPoolTier
