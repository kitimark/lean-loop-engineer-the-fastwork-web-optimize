import Lean.Data.Json
import Fw.Oracle.Retrieve
import Fw.Oracle.ExpandWire
namespace Fw.Wire.OracleRetrieve
open Lean Fw.Oracle Fw.Oracle.Expand
open Fw.Oracle.Retrieve (RetrieveCfg rcfg tree Call callAt rel hook HookSt traceAt traceBytes Range readRanges
  evidenceValid validEvidence candidates pick1Row pick pickRow pickSends rangeLabel lineSlice hybridRow Item sendPlan
  runSends runTokens ArmCmp)
open Fw.Wire.Ops (Reply field opt asStr asNat str nat arrD natD strD)
open Fw.Wire.Oracle (numQ)
open Fw.Wire.OracleReplay (textsOf)
open Fw.Wire.OracleExpand (blobsOf pairOf flipsJ strsJ)

def strsOf (req : Json) (k : String) : Except String (List String) := do (← arrD req k).mapM (asStr k)

def treeVerdictJ (id p : String) (t : Option String) : List (String × Json) :=
  match verdict safe id p t with
  | .error .notAllowed => [("verdict", "notAllowed")]
  | .error .noText => [("verdict", "noText")]
  | .error (.vocab w) => [("verdict", "vocab"), ("word", .str w)]
  | .ok _ => match hit id p with
    | some w => [("verdict", "pathVocab"), ("word", .str w)]
    | none => [("verdict", "kept")]

def opVocab (req : Json) : Except String Reply := do
  pure [("words", strsJ (vocab (← str req "rowId")))]

def opTree (req : Json) : Except String Reply := do
  let id ← str req "rowId"
  let files ← blobsOf req
  pure [("files", .arr (files.map fun (p, t) => Json.mkObj ([("path", .str p)] ++ treeVerdictJ id p t)).toArray),
    ("kept", strsJ ((tree id files).map Prod.fst))]

def callOf (j : Json) : Except String Call := do
  pure { tool := ← str j "tool", path := ← strD j "path" "", glob := ← strD j "glob" "", bytes := ← natD j "bytes" 0 }

def stOf (j : Json) : Except String HookSt := do pure { calls := ← natD j "calls" 0, bytes := ← natD j "bytes" 0 }

def opHook (req : Json) : Except String Reply := do
  let root ← str req "root"
  let paths ← strsOf req "paths"
  let st ← match opt req "state" with | some j => stOf j | none => pure {}
  let c ← callOf (← field req "call")
  pure <| match callAt root c with
    | none => [("decision", "deny"), ("why", "outside")]
    | some c' => match hook rcfg paths st c' with
      | .allow => [("decision", "allow"), ("path", .str c'.path),
          ("state", Json.mkObj [("calls", toJson (st.calls + 1)), ("bytes", toJson (st.bytes + c'.bytes))])]
      | .deny w => [("decision", "deny"), ("why", .str w)]

def verdictName : Retrieve.Verdict → String
  | .ok => "ok"
  | .outside => "outside"
  | .overReads => "overReads"
  | .overBytes => "overBytes"

def opTrace (req : Json) : Except String Reply := do
  let root ← str req "root"
  let paths ← strsOf req "paths"
  let raw ← (← arrD req "calls").mapM callOf
  pure [("verdict", .str (verdictName (traceAt rcfg root paths raw))), ("calls", toJson raw.length),
    ("bytes", toJson (traceBytes raw)),
    ("paths", .arr (raw.map fun c => match rel root c.path with | some p => Json.str p | none => Json.null).toArray)]

def rangeJ (r : Range) : Json := Json.mkObj [("path", .str r.path), ("first", toJson r.first), ("last", toJson r.last)]

def rangeOf (j : Json) : Except String Range := do pure ⟨← str j "path", ← nat j "first", ← nat j "last"⟩

def opRanges (req : Json) : Except String Reply := do
  let reads ← (← arrD req "reads").mapM fun j => do
    pure (← str j "path", ← (← arrD j "lines").mapM (asNat "lines"))
  pure [("ranges", .arr ((readRanges reads).map rangeJ).toArray)]

def opEvidence (req : Json) : Except String Reply := do
  let rs ← (← arrD req "ranges").mapM rangeOf
  let es ← (← arrD req "evidence").mapM rangeOf
  pure [("valid", .arr ((validEvidence rs es).map rangeJ).toArray),
    ("invalid", .arr ((es.filter fun e => !evidenceValid rs e).map rangeJ).toArray)]

def rowJ (row : List (String × String)) : Json := Json.mkObj (row.map fun (k, v) => (k, Json.str v))

def opPick1 (req : Json) : Except String Reply := do
  let row := textsOf (← field req "row")
  let ps ← strsOf req "paths"
  let cs := candidates rcfg ps
  pure [("candidates", strsJ cs), ("row", rowJ (pick1Row rcfg row ps))]

def probsOf : Json → List (String × Rat)
  | .obj kvs => kvs.toList.filterMap fun (k, v) => (numQ v).map (k, ·)
  | _ => []

def opPick (req : Json) : Except String Reply := do
  let cs ← strsOf req "candidates"
  let probs := match opt req "probabilities" with | some j => probsOf j | none => []
  let row := textsOf (← field req "row")
  let texts := textsOf ((opt req "texts").getD (Json.mkObj []))
  let p := if cs = [] then none else pick cs probs
  let r := pickRow rcfg row (p.bind fun x => (texts.lookup x).map (x, ·))
  pure [("pick", match p with | some x => .str x | none => .null), ("row", rowJ r), ("sends", toJson (pickSends cs p))]

def opHybrid (req : Json) : Except String Reply := do
  let row := textsOf (← field req "row")
  let rs ← (← arrD req "ranges").mapM rangeOf
  let texts := textsOf ((opt req "texts").getD (Json.mkObj []))
  let parts := rs.filterMap fun r => (texts.lookup r.path).map fun t => (rangeLabel r, lineSlice t r)
  let fs := fit row [] parts
  pure [("row", rowJ (hybridRow row parts)), ("kept", strsJ (fs.map Prod.fst)),
    ("cut", strsJ ((parts.map Prod.fst).filter fun l => !(fs.map Prod.fst).contains l)), ("esc", toJson (sizeWith row fs))]

def itemOf (j : Json) : Except String Item := do pure ⟨← str j "id", ← nat j "sends", ← nat j "tokens"⟩

def opPlan (req : Json) : Except String Reply := do
  let items ← (← arrD req "items").mapM itemOf
  let (rs, d) := sendPlan Fw.Oracle.defaultBudget Fw.Oracle.defaultRunBudget (← nat req "logged") items
  pure [("runs", .arr (rs.map fun r => Json.mkObj [("ids", strsJ (r.map (·.id))), ("sends", toJson (runSends r)),
      ("tokens", toJson (runTokens r))]).toArray),
    ("deferred", strsJ (d.map (·.id))), ("sends", toJson ((rs.map runSends).sum))]

def whyJ : Retrieve.Why → Json
  | .netLowC a n => Json.mkObj [("kind", "netLowC"), ("arm", .str a), ("net", toJson n)]
  | .netLowX a n => Json.mkObj [("kind", "netLowX"), ("arm", .str a), ("net", toJson n)]
  | .gainOnDropped a i => Json.mkObj [("kind", "gainOnDropped"), ("arm", .str a), ("id", .str i)]
  | .untraced a i => Json.mkObj [("kind", "untraced"), ("arm", .str a), ("id", .str i)]

def opAdopt (req : Json) : Except String Reply := do
  let a : ArmCmp := ⟨← str req "arm", ← (← arrD req "vsC").mapM pairOf, ← (← arrD req "vsX").mapM pairOf⟩
  let dropped ← strsOf req "dropped"
  let traced ← strsOf req "traced"
  pure [("arm", .str a.arm), ("vsC", Json.mkObj (flipsJ a.vsC)), ("vsX", Json.mkObj (flipsJ a.vsX)),
    ("reasons", .arr ((Retrieve.reasons a dropped traced).map whyJ).toArray),
    ("adopt", .bool (Retrieve.adopt a dropped traced))]

def ops : List String :=
  ["oracle.retrieveVocab", "oracle.retrieveTree", "oracle.retrieveHook", "oracle.retrieveTrace",
   "oracle.retrieveRanges", "oracle.retrieveEvidence", "oracle.retrievePick1", "oracle.retrievePick",
   "oracle.retrieveHybrid", "oracle.retrievePlan", "oracle.retrieveAdopt"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "oracle.retrieveVocab" => some (opVocab req)
  | "oracle.retrieveTree" => some (opTree req)
  | "oracle.retrieveHook" => some (opHook req)
  | "oracle.retrieveTrace" => some (opTrace req)
  | "oracle.retrieveRanges" => some (opRanges req)
  | "oracle.retrieveEvidence" => some (opEvidence req)
  | "oracle.retrievePick1" => some (opPick1 req)
  | "oracle.retrievePick" => some (opPick req)
  | "oracle.retrieveHybrid" => some (opHybrid req)
  | "oracle.retrievePlan" => some (opPlan req)
  | "oracle.retrieveAdopt" => some (opAdopt req)
  | _ => none

def run (op : String) (r : String) : String :=
  match Json.parse r with
  | .ok j => match handle op j with
    | some (.ok f) => (Json.mkObj f).compress
    | some (.error e) => s!"error: {e}"
    | none => "unknown op"
  | .error e => s!"parse: {e}"

#guard run "oracle.retrieveHook" "{\"root\":\"/t\",\"paths\":[\"a.mjs\"],\"call\":{\"tool\":\"Read\",\"path\":\"/t/a.mjs\",\"bytes\":5}}" ==
  "{\"decision\":\"allow\",\"path\":\"a.mjs\",\"state\":{\"bytes\":5,\"calls\":1}}"
#guard run "oracle.retrieveHook" "{\"root\":\"/t\",\"paths\":[\"a.mjs\"],\"call\":{\"tool\":\"Read\",\"path\":\"/u/a.mjs\"}}" ==
  "{\"decision\":\"deny\",\"why\":\"outside\"}"
#guard run "oracle.retrieveHook" "{\"root\":\"/t\",\"paths\":[\"a.mjs\"],\"state\":{\"calls\":8},\"call\":{\"tool\":\"Grep\",\"path\":\"/t\"}}" ==
  "{\"decision\":\"deny\",\"why\":\"overReads\"}"
#guard run "oracle.retrieveTrace" "{\"root\":\"/t\",\"paths\":[\"a.mjs\"],\"calls\":[{\"tool\":\"Read\",\"path\":\"a.mjs\",\"bytes\":40000}]}" ==
  "{\"bytes\":40000,\"calls\":1,\"paths\":[\"a.mjs\"],\"verdict\":\"overBytes\"}"
#guard run "oracle.retrievePick" "{\"candidates\":[\"a.mjs\",\"b.mjs\"],\"probabilities\":{\"f2\":0.6,\"none\":0.4},\"row\":{},\"texts\":{}}" ==
  "{\"pick\":\"b.mjs\",\"row\":{},\"sends\":2}"
#guard run "oracle.retrieveEvidence" "{\"ranges\":[{\"path\":\"a\",\"first\":1,\"last\":6}],\"evidence\":[{\"path\":\"a\",\"first\":2,\"last\":9}]}" ==
  "{\"invalid\":[{\"first\":2,\"last\":9,\"path\":\"a\"}],\"valid\":[]}"

end Fw.Wire.OracleRetrieve
