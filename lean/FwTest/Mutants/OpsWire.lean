import Fw.Ops.Wire

/-! # Mutant killers for `Fw.Ops.Wire` (task m0-mutants)

Golden replies for the defaults of the `ops.*` decoders (missing counts are 0, a missing `edits` is
false, a missing meter `window` is 0, a TTL from absent `w5m`/`w1h` is 300 s), for the `perRole`
cap and the `coldWake` rule name on the wire, and the op list matching the dispatcher. -/

namespace FwTest.Mutants.OpsWire
open Lean Fw.Wire.Ops

/-- Parse a JSON literal (`null` if it does not parse). -/
def lit (s : String) : Json := (Json.parse s).toOption.getD .null

/-- The compact reply of `ops.*` op `op` to the request `s` (`error: …` or `none` otherwise). -/
def reply (op s : String) : String :=
  match handle op (lit s) with
  | some (.ok r) => (Json.mkObj r).compress
  | some (.error e) => "error: " ++ e
  | none => "none"

-- every listed op is dispatched, and every dispatched op is listed
#guard ops == ["ops.spawn", "ops.pathCheck", "ops.usage", "ops.meter", "ops.hook", "ops.actor", "ops.obs", "ops.wait"]
#guard ops.all fun o => (handle o (Json.mkObj [])).isSome

-- ops.meter: TTL from absent w5m/w1h, absent wakeGapSec, absent state window
#guard reply "ops.meter" ("{\"now\":100,\"agents\":[{\"agent\":\"a\",\"ctx\":1,\"idleSec\":400}," ++
    "{\"agent\":\"b\",\"ctx\":1,\"idleSec\":400,\"w1h\":1},{\"agent\":\"c\",\"ctx\":1,\"idleSec\":0,\"w5m\":1," ++
    "\"wakeGapSec\":350},{\"agent\":\"d\",\"ctx\":1,\"idleSec\":0,\"ttlSec\":0}]}") ==
  "{\"alerts\":[{\"agent\":\"a\",\"rule\":\"idleExpiring\",\"window\":0},{\"agent\":\"c\",\"rule\":\"coldWake\"," ++
  "\"window\":0},{\"agent\":\"d\",\"rule\":\"idleExpiring\",\"window\":0}],\"state\":{\"fired\":[{\"agent\":\"a\"," ++
  "\"rule\":\"idleExpiring\"},{\"agent\":\"c\",\"rule\":\"coldWake\"},{\"agent\":\"d\",\"rule\":\"idleExpiring\"}]," ++
  "\"window\":0},\"verdicts\":[{\"agent\":\"a\",\"ttlSec\":300,\"verdict\":\"resumeCheap\"},{\"agent\":\"b\"," ++
  "\"ttlSec\":3600,\"verdict\":\"resumeOk\"},{\"agent\":\"c\",\"ttlSec\":300,\"verdict\":\"resumeOk\"}," ++
  "{\"agent\":\"d\",\"ttlSec\":0,\"verdict\":\"resumeOk\"}]}"
#guard reply "ops.meter" ("{\"now\":100,\"state\":{\"fired\":[{\"agent\":\"a\",\"rule\":\"coldWake\"}," ++
    "{\"agent\":\"b\",\"rule\":\"ctxBig\"},{\"agent\":\"c\",\"rule\":\"idleExpiring\"}]},\"agents\":[]}") ==
  "{\"alerts\":[],\"state\":{\"fired\":[{\"agent\":\"a\",\"rule\":\"coldWake\"},{\"agent\":\"b\",\"rule\":\"ctxBig\"}," ++
  "{\"agent\":\"c\",\"rule\":\"idleExpiring\"}],\"window\":0},\"verdicts\":[]}"
#guard reply "ops.meter" "{\"now\":100,\"state\":{\"fired\":[{\"agent\":\"a\",\"rule\":\"\"}]},\"agents\":[]}" ==
  "error: unknown rule "

-- ops.usage: transcript lines with missing counts read as 0
#guard reply "ops.usage" ("{\"lines\":[{\"message\":{\"id\":\"m\",\"usage\":{}}},{\"message\":{\"id\":\"n\"," ++
    "\"usage\":{\"cache_creation\":{}}}}]}") ==
  "{\"skipped\":0,\"table\":[{\"cache1h\":0,\"cache5m\":0,\"cacheCreate\":0,\"cacheRead\":0,\"id\":\"m\",\"input\":0," ++
  "\"output\":0},{\"cache1h\":0,\"cache5m\":0,\"cacheCreate\":0,\"cacheRead\":0,\"id\":\"n\",\"input\":0,\"output\":0}]," ++
  "\"totals\":{\"cache1h\":0,\"cache5m\":0,\"cacheCreate\":0,\"cacheRead\":0,\"input\":0,\"output\":0}}"

-- ops.spawn: a role without `edits` does not edit (so a nested spawn is allowed); perRole caps are read
#guard reply "ops.spawn" ("{\"alive\":[],\"roles\":[{\"name\":\"r\",\"runsAs\":\"subagent\"}],\"now\":0," ++
    "\"req\":{\"name\":\"x\",\"role\":\"r\",\"depth\":1}}") ==
  "{\"decision\":\"allow\",\"kind\":\"subagent\",\"reason\":null,\"wantKind\":\"subagent\"}"
#guard reply "ops.spawn" ("{\"alive\":[],\"roles\":[{\"name\":\"r\",\"runsAs\":\"teammate\"}],\"caps\":{\"perRole\":" ++
    "{\"r\":0}},\"now\":0,\"req\":{\"name\":\"x\",\"role\":\"r\"}}") ==
  "{\"decision\":\"deny\",\"kind\":\"teammate\",\"reason\":\"capRole\",\"role\":\"r\",\"wantKind\":\"teammate\"}"
#guard reply "ops.spawn" ("{\"alive\":[],\"roles\":[{\"name\":\"r\",\"runsAs\":\"teammate\"}],\"caps\":{}," ++
    "\"now\":0,\"req\":{\"name\":\"x\",\"role\":\"r\"}}") ==
  "{\"decision\":\"allow\",\"kind\":\"teammate\",\"reason\":null,\"wantKind\":\"teammate\"}"

end FwTest.Mutants.OpsWire
