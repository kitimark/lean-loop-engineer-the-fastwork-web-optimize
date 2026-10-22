import Lean.Data.Json
import Fw.Oracle.Expand
import Fw.Oracle.ExpandPaired
import Fw.Oracle.ReplayWire
namespace Fw.Wire.OracleExpand
open Lean Fw.Oracle Fw.Oracle.Expand
open Fw.Wire.Ops (Reply field opt asStr str arrD)
open Fw.Wire.Oracle (ratJ numQ questionOf rawOf)
open Fw.Wire.OracleReplay (textsOf)

def cfgOf (req : Json) : Except String Cfg :=
  match opt req "cfg" with
  | none | some (.str "safe") => pure safe
  | some (.str "naive") => pure naive
  | some _ => throw "cfg: not safe or naive"

def rowTexts (row : List (String × String)) : List String := d1.fields.map fun (_, k) => (row.lookup k).getD ""

def blobsOf (req : Json) : Except String (List (String × Option String)) :=
  match opt req "blobs" with
  | none => pure []
  | some (.obj kvs) => kvs.toList.mapM fun (k, v) => match v with
    | .str s => pure (k, some s)
    | .null => pure (k, none)
    | _ => throw s!"blobs: {k} is not a text or null"
  | some _ => throw "blobs: not an object"

def verdictJ (fitted : Bool) : Except Drop String → List (String × Json)
  | .ok t => [("verdict", if fitted then "kept" else "overCap"), ("bytes", toJson (bytes t)), ("esc", toJson (escBytes t))]
  | .error .notAllowed => [("verdict", "notAllowed")]
  | .error .noText => [("verdict", "noText")]
  | .error (.vocab w) => [("verdict", "vocab"), ("word", .str w)]

def opPaths (req : Json) : Except String Reply := do
  let c ← cfgOf req
  let ps := pathsOf (rowTexts (textsOf (← field req "row")))
  pure [("paths", .arr (ps.map fun p => Json.mkObj [("path", .str p), ("allowed", .bool (allowed c p))]).toArray)]

def opExpand (req : Json) : Except String Reply := do
  let c ← cfgOf req
  let id ← str req "rowId"
  let row := textsOf (← field req "row")
  let blobs ← blobsOf req
  let blob := fun p => (blobs.lookup p).join
  let ps := pathsOf (rowTexts row)
  let r := expand c id row ps blob
  let fitted : List String := match r with | .expanded fs _ => fs.map Prod.fst | _ => []
  let files := ps.map fun p => Json.mkObj ([("path", .str p)] ++ verdictJ (fitted.contains p) (verdict c id p (blob p)))
  pure <| [("rowId", .str id), ("files", .arr files.toArray)] ++ match r with
    | .same => [("result", "same")]
    | .expanded fs n => [("result", "expanded"), ("esc", toJson n), ("filesText", .str (filesText fs))]
    | .refused n => [("result", "refused"), ("esc", toJson n)]

def rawAnswer (q : Question) (a : Json) : Option Raw :=
  match opt a "failure", opt a "reply", opt a "choice" with
  | some _, _, _ => none
  | none, some (.str t), _ => (Json.parse t |>.toOption).bind fun b => (rawOf q b).toOption
  | none, none, some (.str c) =>
    let probs := match opt a "probabilities" with
      | some (.obj kvs) => kvs.toList.filterMap fun (k, v) => (numQ v).map (k, ·)
      | _ => []
    some { type := "choice", pick := some c, probs }
  | _, _, _ => none

def rightIn (q : Question) (re : Bool) (label : String) (a : Json) : Bool :=
  match rawAnswer q a with
  | none => false
  | some r => match validate q.spec (if re then renorm r else r) with
    | .ok (.choice pk _) => pk == label
    | _ => false

def pairJ (p : Pair) : Json := Json.mkObj [("id", .str p.id), ("base", .bool p.base), ("arm", .bool p.arm)]

def pairOf (j : Json) : Except String Pair := do
  let b ← match opt j "base" with | some (.bool b) => pure b | _ => throw "pair: base is not a bool"
  let a ← match opt j "arm" with | some (.bool b) => pure b | _ => throw "pair: arm is not a bool"
  pure ⟨← str j "id", b, a⟩

def strsJ (l : List String) : Json := .arr (l.map Json.str).toArray

def flipsJ (ps : List Pair) : Reply :=
  [("gains", strsJ (gains ps)), ("losses", strsJ (losses ps)), ("net", toJson (net ps)),
   ("baseRight", toJson (ps.filter (·.base)).length), ("armRight", toJson (ps.filter (·.arm)).length),
   ("rows", toJson ps.length), ("p", ratJ (signP (gains ps).length (losses ps).length))]

def opPaired (req : Json) : Except String Reply := do
  let q ← questionOf req
  let mode ← str req "mode"
  let re ← match mode with
    | "strict" => pure false
    | "renorm" => pure true
    | m => throw s!"mode: {m} is not strict or renorm"
  let rows ← (← arrD req "replay").mapM fun j => do pure (← str j "id", ← str j "label")
  let base ← arrD req "base"
  let arm ← arrD req "arm"
  let right (l : List Json) (i lab : String) : Bool :=
    match l.find? (fun a => opt a "id" == some (.str i)) with
    | some a => rightIn q re lab a
    | none => false
  let ps := rows.map fun (i, lab) => (⟨i, right base i lab, right arm i lab⟩ : Pair)
  pure ([("mode", .str mode), ("pairs", .arr (ps.map pairJ).toArray)] ++ flipsJ ps)

def whyJ : Why → Json
  | .noArm => Json.mkObj [("kind", "noArm")]
  | .netLow a n => Json.mkObj [("kind", "netLow"), ("arm", .str a), ("net", toJson n)]
  | .gainOnDropped a i => Json.mkObj [("kind", "gainOnDropped"), ("arm", .str a), ("id", .str i)]
  | .untraced a i => Json.mkObj [("kind", "untraced"), ("arm", .str a), ("id", .str i)]

def opAdopt (req : Json) : Except String Reply := do
  let arms ← (← arrD req "arms").mapM fun j => do
    pure (⟨← str j "arm", ← (← arrD j "pairs").mapM pairOf⟩ : ArmPairs)
  let ids (k : String) : Except String (List String) := do (← arrD req k).mapM (asStr k)
  let dropped ← ids "dropped"
  let traced ← ids "traced"
  pure [("arms", .arr (arms.map fun a => Json.mkObj ([("arm", .str a.arm)] ++ flipsJ a.pairs)).toArray),
    ("reasons", .arr ((reasons arms dropped traced).map whyJ).toArray), ("adopt", .bool (adopt arms dropped traced))]

def ops : List String := ["oracle.expandPaths", "oracle.expand", "oracle.paired", "oracle.adopt"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "oracle.expandPaths" => some (opPaths req)
  | "oracle.expand" => some (opExpand req)
  | "oracle.paired" => some (opPaired req)
  | "oracle.adopt" => some (opAdopt req)
  | _ => none

def run (op : String) (r : String) : String :=
  match Json.parse r with
  | .ok j => match handle op j with
    | some (.ok f) => (Json.mkObj f).compress
    | some (.error e) => s!"error: {e}"
    | none => "unknown op"
  | .error e => s!"parse: {e}"

#guard run "oracle.expandPaths" "{\"row\":{\"cause\":\"docs/team/work-graph.json and scripts/a.mjs\"}}" ==
  "{\"paths\":[{\"allowed\":false,\"path\":\"docs/team/work-graph.json\"},{\"allowed\":true,\"path\":\"scripts/a.mjs\"}]}"
#guard run "oracle.expand" ("{\"rowId\":\"i\",\"row\":{\"title\":\"t\",\"cause\":\"scripts/a.mjs scripts/b.mjs\"}," ++
  "\"blobs\":{\"scripts/a.mjs\":\"x\",\"scripts/b.mjs\":\"c-quota\"}}") ==
  "{\"esc\":48,\"files\":[{\"bytes\":1,\"esc\":1,\"path\":\"scripts/a.mjs\",\"verdict\":\"kept\"}," ++
  "{\"path\":\"scripts/b.mjs\",\"verdict\":\"vocab\",\"word\":\"c-quota\"}],\"filesText\":\"file: scripts/a.mjs\\nx\"," ++
  "\"result\":\"expanded\",\"rowId\":\"i\"}"
#guard run "oracle.paired" ("{\"name\":\"incident-class\",\"mode\":\"strict\",\"replay\":[{\"id\":\"a\",\"label\":\"c-quota\"}]," ++
  "\"base\":[],\"arm\":[{\"id\":\"a\",\"choice\":\"c-quota\"}]}") ==
  "{\"armRight\":0,\"baseRight\":0,\"gains\":[],\"losses\":[],\"mode\":\"strict\",\"net\":0,\"p\":{\"den\":\"1\",\"num\":\"1\"}," ++
  "\"pairs\":[{\"arm\":false,\"base\":false,\"id\":\"a\"}],\"rows\":1}"
#guard run "oracle.adopt" "{\"arms\":[],\"dropped\":[],\"traced\":[]}" == "{\"adopt\":false,\"arms\":[],\"reasons\":[{\"kind\":\"noArm\"}]}"

end Fw.Wire.OracleExpand
