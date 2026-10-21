import Lean.Data.Json
import Fw.Ci.Pool.Fallback
import Fw.Ops.Wire
/-!
# The ops `ci.poolRoute` and `ci.poolConsts` (rule `Fw.Ci.Pool.Fallback`; shapes in docs/team/tools/ci-pool.md)
-/
namespace Fw.Wire.CiPool
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD optN)
open Fw.Ci.Pool.Fallback
open Fw.Ci.Pool.Key (Key)

/-- The wire name of a provider. -/
def viaName : Via → String
  | .github => "github"
  | .circleci => "circleci"
  | .bitrise => "bitrise"

/-- The wire name of a machine family. -/
def osName : Os → String
  | .macos => "macos"
  | .linux => "linux"

/-- The wire name of an engine. -/
def engineName : Engine → String
  | .iosSimSafari => "iosSimSafari"
  | .wktrIosSim => "wktrIosSim"
  | .pwWebkitMac => "pwWebkitMac"
  | .pwWebkitWpe => "pwWebkitWpe"

/-- An engine from its wire name. -/
def engineOf (s : String) : Except String Engine :=
  match [Engine.iosSimSafari, .wktrIosSim, .pwWebkitMac, .pwWebkitWpe].find? (engineName · == s) with
  | some e => .ok e
  | none => .error s!"field engine: unknown engine {s}"

/-- A string list field with a default. -/
def strsD (j : Json) (k : String) (d : List String) : Except String (List String) :=
  match opt j k with
  | none => .ok d
  | some v => do (← asArr k v).toList.mapM (asStr k)

/-- A string field with a default. -/
def strD (j : Json) (k : String) (d : String) : Except String String :=
  match opt j k with
  | none => .ok d
  | some v => asStr k v

/-- The `circleCaps` field: an object of lane to minutes. -/
def capsD (j : Json) (d : List (String × Nat)) : Except String (List (String × Nat)) :=
  match opt j "circleCaps" with
  | none => .ok d
  | some (.obj o) => o.toList.mapM fun (k, v) => do pure (k, ← asNat "circleCaps" v)
  | some _ => .error "field circleCaps: expected an object"

/-- A named configuration with the fields of `over` replaced. -/
def cfgOf (req : Json) : Except String Cfg := do
  let b ← match ← strD req "cfg" "phase1" with
    | "phase1" => pure phase1
    | "enterprise" => pure enterprise
    | n => throw s!"field cfg: unknown configuration {n}"
  let o := (opt req "over").getD (Json.mkObj [])
  pure {
    ghMacCap := ← natD o "ghMacCap" b.ghMacCap, ghTotalCap := ← natD o "ghTotalCap" b.ghTotalCap,
    ghWaitMaxS := ← natD o "ghWaitMaxS" b.ghWaitMaxS, waitMaxS := ← natD o "waitMaxS" b.waitMaxS,
    circleCls := ← strD o "circleCls" b.circleCls, circleMacConc := ← natD o "circleMacConc" b.circleMacConc,
    circleShortMaxMin := ← natD o "circleShortMaxMin" b.circleShortMaxMin,
    circleSetupMin := ← natD o "circleSetupMin" b.circleSetupMin,
    circleMacAllow := ← strsD o "circleMacAllow" b.circleMacAllow, circleCaps := ← capsD o b.circleCaps,
    bitriseOn := ← boolD o "bitriseOn" b.bitriseOn, bitriseCls := ← strD o "bitriseCls" b.bitriseCls,
    bitriseConc := ← natD o "bitriseConc" b.bitriseConc, bitriseMaxMin := ← natD o "bitriseMaxMin" b.bitriseMaxMin,
    bitriseAllow := ← strsD o "bitriseAllow" b.bitriseAllow, wpeCls := ← strD o "wpeCls" b.wpeCls,
    wpeTolerant := ← strsD o "wpeTolerant" b.wpeTolerant, ghOnly := ← strsD o "ghOnly" b.ghOnly,
    crossPoolOk := ← strsD o "crossPoolOk" b.crossPoolOk }

/-- A string list as JSON. -/
def strsJson (l : List String) : Json := .arr (l.map Json.str).toArray

/-- A configuration as JSON. -/
def cfgJson (c : Cfg) : Json := Json.mkObj [
  ("ghMacCap", c.ghMacCap), ("ghTotalCap", c.ghTotalCap), ("ghWaitMaxS", c.ghWaitMaxS), ("waitMaxS", c.waitMaxS),
  ("circleCls", c.circleCls), ("circleMacConc", c.circleMacConc), ("circleShortMaxMin", c.circleShortMaxMin),
  ("circleSetupMin", c.circleSetupMin), ("circleMacAllow", strsJson c.circleMacAllow),
  ("circleCaps", Json.mkObj (c.circleCaps.map fun (k, v) => (k, toJson v))), ("bitriseOn", c.bitriseOn),
  ("bitriseCls", c.bitriseCls), ("bitriseConc", c.bitriseConc), ("bitriseMaxMin", c.bitriseMaxMin),
  ("bitriseAllow", strsJson c.bitriseAllow), ("wpeCls", c.wpeCls), ("wpeTolerant", strsJson c.wpeTolerant),
  ("ghOnly", strsJson c.ghOnly), ("crossPoolOk", strsJson c.crossPoolOk)]

/-- The slot state from JSON. -/
def stateOf (j : Json) : Except String State := do
  let rem ← match opt j "ghRemainingS" with
    | none => pure none
    | some v => do pure (some (← (← asArr "ghRemainingS" v).toList.mapM (asNat "ghRemainingS")))
  pure ⟨← nat j "ghMacBusy", ← nat j "ghTotalBusy", ← natD j "ghQueuedAhead" 0, ← boolD j "ghDegraded" false, rem,
    ← natD j "circleBusy" 0, ← natD j "bitriseBusy" 0, ← natD j "circleCreditsLeft" 0⟩

/-- The slot state as JSON. -/
def stateJson (s : State) : Json := Json.mkObj [
  ("ghMacBusy", s.ghMacBusy), ("ghTotalBusy", s.ghTotalBusy), ("ghQueuedAhead", s.ghQueuedAhead),
  ("ghDegraded", s.ghDegraded),
  ("ghRemainingS", match s.ghRemainingS with | some l => .arr (l.map toJson).toArray | none => .null),
  ("circleBusy", s.circleBusy), ("bitriseBusy", s.bitriseBusy), ("circleCreditsLeft", s.circleCreditsLeft)]

/-- A request from JSON; the key must be valid and the cap known. -/
def reqOf (j : Json) : Except String Req := do
  let k : Key := ⟨← str j "sha", ← str j "lane", ← str j "cfg", ← nat j "rep"⟩
  if !k.valid then throw s!"invalid key for lane {k.lane}"
  let cap ← match ← optN j "capMin" with
    | some m => pure m
    | none => match Fw.Ci.Pool.Caps.rows.find? (·.lane == k.lane) with
      | some r => pure r.cap
      | none => throw s!"field capMin: no cap row for lane {k.lane}"
  pure ⟨k, ← natD j "attempt" 0, ← engineOf (← str j "engine"), ← str j "image", cap, ← natD j "ageS" 0,
    ← boolD j "current" true⟩

/-- A target as JSON. -/
def targetJson (t : Target) : Json := Json.mkObj [
  ("via", viaName t.via), ("os", osName t.os), ("cls", t.cls), ("engine", engineName t.engine),
  ("timeoutMin", t.timeoutMin), ("credits", t.credits)]

/-- One log row as JSON. -/
def rowJson (p : Id × Decision) : Json :=
  let k := p.1.1
  let head : List (String × Json) :=
    [("sha", k.sha), ("lane", k.lane), ("cfg", k.cfg), ("rep", k.rep), ("attempt", p.1.2)]
  Json.mkObj <| head ++ match p.2 with
    | .run t => [("decision", "run"), ("target", targetJson t)]
    | .wait => [("decision", "wait")]
    | .done o => [("decision", "done"), ("outcome", o.tag)]

/-- `ci.poolRoute`. -/
def opRoute (req : Json) : Except String Reply := do
  let c ← cfgOf req
  let s ← stateOf (← field req "state")
  let rs ← (← arr req "reqs").toList.mapM reqOf
  let o := step c rs s
  pure [("macFree", macFree c s), ("expWaitS", match expWaitS c s with | some w => toJson w | none => .null),
    ("ghOk", ghOk c s), ("log", .arr (o.log.map rowJson).toArray), ("sent", o.sent.length),
    ("waiting", o.waiting.length), ("done", o.done.length), ("state", stateJson o.state)]

/-- `ci.poolConsts`. -/
def opConsts (req : Json) : Except String Reply := do
  let c ← cfgOf req
  pure [("cfg", cfgJson c), ("sources", .arr (sources.map fun (k, st, src) =>
    Json.mkObj [("constant", k), ("status", st), ("source", src)]).toArray)]

/-- The ops of this module. -/
def ops : List String := ["ci.poolRoute", "ci.poolConsts"]

/-- Dispatch an op of this module (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ci.poolRoute" => some (opRoute req)
  | "ci.poolConsts" => some (opConsts req)
  | _ => none

/-! ## Examples -/

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

private def rq (lane : String) (extra : String := "") : String :=
  "{\"sha\":\"0123456789abcdef0123456789abcdef01234567\",\"lane\":\"" ++ lane ++
    "\",\"cfg\":\"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\",\"rep\":0,\"engine\":\"wktrIosSim\",\"image\":\"macos-26\"" ++
    extra ++ "}"

#guard runField "ci.poolRoute" ("{\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[" ++ rq "wktr" ++ "]}") "log" ==
  "[{\"attempt\":0,\"cfg\":\"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\",\"decision\":\"run\",\"lane\":\"wktr\",\"rep\":0,\"sha\":\"0123456789abcdef0123456789abcdef01234567\",\"target\":{\"cls\":\"macos-26\",\"credits\":0,\"engine\":\"wktrIosSim\",\"os\":\"macos\",\"timeoutMin\":16,\"via\":\"github\"}}]"
#guard runField "ci.poolRoute" ("{\"state\":{\"ghMacBusy\":5,\"ghTotalBusy\":5,\"ghRemainingS\":null},\"reqs\":[" ++ rq "wktr" ++ "]}") "waiting" == "1"
#guard runField "ci.poolRoute" ("{\"state\":{\"ghMacBusy\":5,\"ghTotalBusy\":5,\"ghRemainingS\":[900]},\"reqs\":[]}") "expWaitS" == "900"
#guard runField "ci.poolRoute" ("{\"over\":{\"circleMacAllow\":[\"wktr\"],\"circleCaps\":{\"wktr\":5}},\"state\":{\"ghMacBusy\":5,\"ghTotalBusy\":5,\"circleCreditsLeft\":30000},\"reqs\":[" ++ rq "wktr" ++ "]}") "state" ==
  "{\"bitriseBusy\":0,\"circleBusy\":1,\"circleCreditsLeft\":28400,\"ghDegraded\":false,\"ghMacBusy\":5,\"ghQueuedAhead\":0,\"ghRemainingS\":null,\"ghTotalBusy\":5}"
#guard runField "ci.poolRoute" ("{\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[" ++ rq "wktr" ",\"current\":false" ++ "]}") "done" == "1"
#guard run "ci.poolRoute" ("{\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[" ++ rq "no-such-lane" ++ "]}") ==
  "error: field capMin: no cap row for lane no-such-lane"
#guard run "ci.poolRoute" ("{\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[" ++ rq "wktr" ",\"engine\":\"blink\"" ++ "]}") ==
  "error: field engine: unknown engine blink"
#guard run "ci.poolRoute" "{\"cfg\":\"x\",\"state\":{\"ghMacBusy\":0,\"ghTotalBusy\":0},\"reqs\":[]}" ==
  "error: field cfg: unknown configuration x"
#guard runField "ci.poolConsts" "{\"cfg\":\"enterprise\"}" "cfg" |>.startsWith "{\"bitriseAllow\":[]"
#guard (Json.parse (runField "ci.poolConsts" "{\"cfg\":\"enterprise\"}" "cfg")).toOption.bind
  (fun j => (j.getObjValAs? Nat "ghMacCap").toOption) == some 50

end Fw.Wire.CiPool
