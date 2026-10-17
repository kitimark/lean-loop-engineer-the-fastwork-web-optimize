import Lean.Data.Json
import Fw.Spec.Verdict
import Fw.Spec.Lease
/-!
# JSON-lines protocol (the only boundary the TypeScript shell sees)

One request object per line on stdin, one response per line on stdout.
`{"op":"lease.step","state":{...},"cmd":{...}}` → `{"state":{...},"reply":{...}}`
`{"op":"verdict","dir":"lower","ctl":[..],"var":[..]}` → `{"verdict":"better"}`
-/
namespace Fw.Wire
open Lean

def handle (req : Json) : Except String Json := do
  let op ← req.getObjValAs? String "op"
  match op with
  | "lease.step" =>
    let s ← req.getObjValAs? Fw.Lease.State "state"
    let c ← req.getObjValAs? Fw.Lease.Cmd "cmd"
    let (s', r) := Fw.Lease.step s c
    return Json.mkObj [("state", toJson s'), ("reply", toJson r)]
  | "verdict" =>
    let d ← req.getObjValAs? Fw.Verdict.Dir "dir"
    let a ← req.getObjValAs? (List Int) "ctl"
    let b ← req.getObjValAs? (List Int) "var"
    return Json.mkObj [("verdict", toJson (Fw.Verdict.verdict d a b))]
  | other => throw s!"unknown op {other}"

def handleLine (line : String) : String :=
  match Json.parse line >>= handle with
  | .ok j    => j.compress
  | .error e => (Json.mkObj [("error", Json.str e)]).compress

end Fw.Wire
