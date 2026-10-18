import Lean.Data.Json
import Fw.Gate.State
import Fw.Measure.Wire
import Fw.Ops.Wire
/-!
# JSON codecs and ops of `Fw.Gate` (the breakpoint parity gate's verdict)

Glue between `fwcore`'s JSON lines and `Fw.Gate` (namespace `Fw.Wire.Gate`, so the math view treats
it as wire code). Total decoders only (`Except String`); no partial operations; no decision logic:
every status and verdict comes from `Fw.Gate`. Numbers are read as exact decimals.

| op | request | reply |
|---|---|---|
| `gate.state` | `anchors` (anchors.json as is), `parts` [id] (covered, in order), `props` (run header), `deviceEdges` [[n, n+1]], `port`? (`chromium`, `webkit-apple`, `webkit-glib`; absent or `null`: no reach claim), `states` [State] | `states` [Eval] |
| `gate.stale` | `anchors`, `parts`, `props`, `pairs` [{`after`, `fresh`}] (raw `parts` objects) | `stale` [{`compared`, `differ`}] |
| `gate.tally` | `cells` [{`verdicts` [verdict], `block` bool}] | `cells` [{`verdict`, `failing`, `total`, `unreachable`}] (`not-run` for an empty block) |
| `gate.reach` | `port`, `envs` [requested] | `reasons` [reason or `null`] (`Fw.Gate.reqReason`) |
| `gate.styleEq` | `pairs` [[a, b]] (string, or `null` = absent) | `eq` [bool] |
| `gate.cell` | `statuses` [status] | `verdict` |

State: `{requested {width, height, deviceWidth, dpr, hover, pointer, reducedMotion, colorScheme},
orig Arm, rewrite Arm, expect? [[k, v]], expectNeutral? [[k, v]]}`. Arm: `{viewport {innerHeight,
screenWidth, dpr}, observed {widthExact, hoverHover, …}, truth [[k, v]], truthLegacy [[k, v]],
neutral [[k, v]], parts {id: {role: {count, items [{rect? {x, y, w, h}, style {prop: value}}]}}}}`.
The matchMedia maps are entry arrays because their key order is the order of the items (a JSON
object would be re-sorted); `v` is `true`, `false` or `null`.

Eval: `{dev {orig, rewrite}, achieved, truth [{cls, key, status, fails, a?, b?, expect?}], truthCounts
{"kind:status": n},
parts [[id, {fails [Item], infoDiffs [Item]}]], rows [[row, verdict]], compared [[id, n]], reach,
verdict}` with
Item `{cls, role, idx, key, status}`: per part the failing count/box/style items and the `info`
items whose values differ, each in item order (an unreachable state lists no failing item). `reach`
is `null` or a reason; `verdict` is the rollup of all `rows`, part rows included. Names: status
`equal|differ|missing|na`, verdict `pass|fail|not-comparable|unreachable:<reason>`, reason
`primary-pair|whole-width|width-dpr`, truth kinds `truth.AR|truth.lean|truth.legacy|truth.neutral.AR|
truth.neutral.lean`. A truth value absent on an arm is left out of the reply (`a?`, `b?`).

`anchors` must be well-formed (`Fw.Gate.wellFormed`: every skip and role has a reason, every named
skip set exists), and every covered id must be a part of it; otherwise the op is an error.
Guards: `#guard`s at the end; golden vectors: `Fw.Wire.GateGolden`.
-/
namespace Fw.Wire.Gate
open Lean Fw.Gate
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str arr arrD)
open Fw.Wire.Measure (asRat)

/-! ## Names -/

/-- The wire name of a status. -/
def statusName : Status → String
  | .equal => "equal" | .differ => "differ" | .missing => "missing" | .na => "na"

/-- A status from its wire name. -/
def statusOf : String → Except String Status
  | "equal" => .ok .equal | "differ" => .ok .differ | "missing" => .ok .missing | "na" => .ok .na
  | s => .error s!"unknown status {s}"

/-- The wire name of an unreachable reason. -/
def reasonName : Reason → String
  | .primaryPair => "primary-pair" | .wholeWidth => "whole-width" | .widthDpr => "width-dpr"

/-- The wire name of a verdict. -/
def verdictName : Verdict → String
  | .pass => "pass" | .fail => "fail" | .nc => "not-comparable"
  | .unreachable r => "unreachable:" ++ reasonName r

/-- A verdict from its wire name. -/
def verdictOf : String → Except String Verdict
  | "pass" => .ok .pass | "fail" => .ok .fail | "not-comparable" => .ok .nc
  | "unreachable:primary-pair" => .ok (.unreachable .primaryPair)
  | "unreachable:whole-width" => .ok (.unreachable .wholeWidth)
  | "unreachable:width-dpr" => .ok (.unreachable .widthDpr)
  | s => .error s!"unknown verdict {s}"

/-- The wire name of a port. -/
def portName : Port → String
  | .chromium => "chromium" | .webkitApple => "webkit-apple" | .webkitGLib => "webkit-glib"

/-- A port from its wire name. -/
def portOf : String → Except String Port
  | "chromium" => .ok .chromium | "webkit-apple" => .ok .webkitApple | "webkit-glib" => .ok .webkitGLib
  | s => .error s!"unknown port {s}"

/-- The optional `port` of a request (absent or `null`: none). -/
def optPort (req : Json) : Except String (Option Port) :=
  match opt req "port" with
  | none | some .null => pure none
  | some (.str s) => do pure (some (← portOf s))
  | some _ => throw "port: expected a string or null"

/-- The wire name of an item kind. -/
def clsName : Cls → String
  | .count => "count" | .box => "box" | .style => "style" | .info => "info"

/-- The wire name of a truth kind. -/
def tclsName : TCls → String
  | .ar => "truth.AR" | .lean => "truth.lean" | .legacy => "truth.legacy"
  | .neutralAR => "truth.neutral.AR" | .neutralLean => "truth.neutral.lean"

/-! ## Decoders -/

/-- The entries of a JSON object (sorted by key). -/
def entriesOf (k : String) : Json → Except String (List (String × Json))
  | .obj kvs => .ok kvs.toList
  | _ => .error s!"field {k}: expected an object"

/-- An optional list of strings (absent or `null` is empty). -/
def strsD (j : Json) (k : String) : Except String (List String) := do
  (← arrD j k).mapM (asStr k)

/-- An optional number: anything but a number reads as unreported. -/
def optRat (j : Json) (k : String) : Option Rat :=
  match opt j k with
  | some (.num n) => some (mkRat n.mantissa (10 ^ n.exponent))
  | _ => none

/-- An optional Boolean: anything but a Boolean reads as unreported. -/
def optBool (j : Json) (k : String) : Option Bool :=
  match opt j k with
  | some (.bool b) => some b
  | _ => none

/-- A required exact number. -/
def rat (j : Json) (k : String) : Except String Rat := do asRat k (← field j k)

/-- The global skips of `anchors.json` (`style.skipPrefixes`, `style.skipSets`). -/
def anchorsOf (j : Json) : Except String Anchors := do
  let style ← field j "style"
  let pres ← (← arr style "skipPrefixes").toList.mapM fun p => do
    pure (⟨← str p "prefix", ← str p "why"⟩ : SkipPrefix)
  let sets ← (← entriesOf "skipSets" (← field style "skipSets")).mapM fun (n, s) => do
    pure (⟨n, ← strsD s "props", ← str s "why"⟩ : SkipSet)
  pure ⟨pres, sets⟩

/-- One role of a part. -/
def roleSpecOf (j : Json) : Except String RoleSpec := do
  let boxRel ← match opt j "boxRel" with
    | none => pure none
    | some b => pure (some ⟨← str b "role", ← asNat "boxRel.index" (← field b "index")⟩)
  pure ⟨← str j "role", boxRel, ← strsD j "dims", ← strsD j "skipSets", ← strsD j "skipProps",
    ← strsD j "skipIfInline", ← str j "why"⟩

/-- The covered parts, in the requested order, from `anchors.parts`. -/
def partSpecsOf (anchors : Json) (ids : List String) : Except String (List PartSpec) := do
  let parts ← field anchors "parts"
  ids.mapM fun id => do
    match opt parts id with
    | none => throw s!"unknown part {id}"
    | some p => pure ⟨id, ← (← arr p "roles").toList.mapM roleSpecOf⟩

/-- The recorded properties of the run (`header.props`). -/
def propsOf (j : Json) : Except String (List (String × PartProps)) := do
  (← entriesOf "props" j).mapM fun (pid, pj) => do
    let roles ← (← entriesOf pid pj).mapM fun (role, rj) => do
      pure (role, (⟨← strsD rj "restated", ← strsD rj "originOnly"⟩ : RoleProps))
    pure (pid, roles)

/-- The context of a gate request. -/
def ctxOf (req : Json) : Except String Ctx := do
  let aj ← field req "anchors"
  let a ← anchorsOf aj
  let ids ← (← arr req "parts").toList.mapM (asStr "parts")
  let ps ← partSpecsOf aj ids
  unless wellFormed a ps do throw "anchors: a skip or role without a reason, or an unknown skip set or box reference"
  let props ← match opt req "props" with
    | none => pure []
    | some p => propsOf p
  let edges ← (← arrD req "deviceEdges").mapM fun e => do
    match (← asArr "deviceEdges" e).toList with
    | n :: _ => asRat "deviceEdges" n
    | [] => throw "deviceEdges: empty pair"
  pure ⟨a, ps, props, edges, ← optPort req⟩

/-- A box. -/
def rectOf (j : Json) : Except String Rect := do
  pure ⟨← rat j "x", ← rat j "y", ← rat j "w", ← rat j "h"⟩

/-- One collected element. -/
def itemOf (j : Json) : Except String Item := do
  let rect ← match opt j "rect" with
    | none => pure none
    | some r => pure (some (← rectOf r))
  let style ← match opt j "style" with
    | none => pure []
    | some s => (← entriesOf "style" s).mapM fun (p, v) => do pure (p, ← asStr p v)
  pure ⟨rect, style, ← strsD j "inline"⟩

/-- One arm's raw part: roles that are absent or `null` are left out. -/
def partRawOf (j : Json) : Except String PartRaw := do
  let es ← entriesOf "part" j
  es.filterMapM fun (role, rj) =>
    match rj with
    | .null => pure none
    | _ => do pure (some (role, (⟨← asNat "count" (← field rj "count"),
        ← (← arr rj "items").toList.mapM itemOf⟩ : RoleRaw)))

/-- One arm's raw parts (`parts` of a raw record); `null` parts are left out. -/
def partsOf (j : Json) : Except String (List (String × PartRaw)) := do
  let es ← entriesOf "parts" j
  es.filterMapM fun (pid, pj) =>
    match pj with
    | .null => pure none
    | _ => do pure (some (pid, ← partRawOf pj))

/-- A matchMedia map as entries `[k, v]` with `v` true, false or null. -/
def tmapOf (k : String) (j : Json) : Except String TMap := do
  (← asArr k j).toList.mapM fun e => do
    match (← asArr k e).toList with
    | [.str key, .null] => pure (key, none)
    | [.str key, .bool b] => pure (key, some b)
    | _ => throw s!"field {k}: expected [key, true|false|null] entries"

/-- An optional matchMedia map (absent or `null` is none). -/
def otmapOf (j : Json) (k : String) : Except String (Option TMap) :=
  match opt j k with
  | none => pure none
  | some m => do pure (some (← tmapOf k m))

/-- One arm of a state. -/
def armOf (j : Json) : Except String Arm := do
  let v ← field j "viewport"
  let o ← field j "observed"
  pure {
    viewport := ⟨optRat v "innerHeight", optRat v "screenWidth", optRat v "dpr"⟩
    observed := ⟨optBool o "widthExact", optBool o "hoverHover", optBool o "hoverNone",
      optBool o "pointerFine", optBool o "pointerCoarse", optBool o "reducedMotion", optBool o "dark"⟩
    truth := ⟨← tmapOf "truth" (← field j "truth"), ← tmapOf "truthLegacy" (← field j "truthLegacy"),
      ← tmapOf "neutral" (← field j "neutral")⟩
    parts := ← partsOf (← field j "parts") }

/-- The requested environment. -/
def requestedOf (j : Json) : Except String Requested := do
  pure ⟨← rat j "width", ← rat j "height", ← rat j "deviceWidth", ← rat j "dpr", ← str j "hover",
    ← str j "pointer", ← str j "reducedMotion", ← str j "colorScheme"⟩

/-- One state. -/
def stateOf (j : Json) : Except String StateIn := do
  pure ⟨← requestedOf (← field j "requested"), ← armOf (← field j "orig"), ← armOf (← field j "rewrite"),
    ← otmapOf j "expect", ← otmapOf j "expectNeutral"⟩

/-! ## Encoders -/

/-- A truth value as an optional field: absent is left out, `null` stays `null`. -/
def tvalField (k : String) : TVal → List (String × Json)
  | none => []
  | some none => [(k, .null)]
  | some (some b) => [(k, .bool b)]

/-- One truth item (`fails` as `StateOut.itemFails`). -/
def titemJson (e : StateOut) (t : TItem) : Json :=
  Json.mkObj ([("cls", .str (tclsName t.cls)), ("key", .str t.key), ("status", .str (statusName t.status)),
    ("fails", .bool (e.itemFails t.status))] ++ tvalField "a" t.a ++ tvalField "b" t.b ++ tvalField "expect" t.expect)

/-- One part item. -/
def pitemJson (it : PItem) : Json :=
  Json.mkObj [("cls", .str (clsName it.cls)), ("role", .str it.role), ("idx", toJson it.idx),
    ("key", .str it.key), ("status", .str (statusName it.status))]

/-- A list of strings. -/
def strsJson (l : List String) : Json := .arr (l.map Json.str).toArray

/-- The truth items counted by `kind:status` (a JSON object, so the keys come out sorted). -/
def truthCounts (ts : List TItem) : Json :=
  let keys := ts.map fun t => tclsName t.cls ++ ":" ++ statusName t.status
  Json.mkObj (keys.eraseDups.map fun k => (k, toJson (keys.count k)))

/-- One evaluated state. -/
def evalJson (e : StateOut) : Json :=
  Json.mkObj [
    ("dev", Json.mkObj [("orig", strsJson e.devO), ("rewrite", strsJson e.devR)]),
    ("achieved", .bool e.achieved),
    ("truth", .arr (e.truth.map (titemJson e)).toArray),
    ("truthCounts", truthCounts e.truth),
    ("parts", .arr (e.parts.map fun p => Json.arr #[.str p.1, Json.mkObj [
      ("fails", .arr ((p.2.filter fun it => e.itemFails it.status).map pitemJson).toArray),
      ("infoDiffs", .arr ((p.2.filter fun it => it.cls == .info && it.differs).map pitemJson).toArray)]]).toArray),
    ("rows", .arr (e.rows.map fun r => Json.arr #[.str r.1, .str (verdictName r.2)]).toArray),
    ("compared", .arr (e.compared.map fun c => Json.arr #[.str c.1, toJson c.2]).toArray),
    ("reach", match e.reach with | none => .null | some r => .str (reasonName r)),
    ("verdict", .str (verdictName e.verdict))]

/-- A table cell. -/
def tallyJson : Option Tally → Json
  | none => Json.mkObj [("verdict", .str "not-run"), ("failing", toJson (0 : Nat)), ("total", toJson (0 : Nat)),
      ("unreachable", toJson (0 : Nat))]
  | some t => Json.mkObj [("verdict", .str (verdictName t.verdict)), ("failing", toJson t.failing),
      ("total", toJson t.total), ("unreachable", toJson t.unreachable)]

/-! ## Ops -/

/-- `gate.state`: evaluate every state. -/
def opState (req : Json) : Except String Reply := do
  let c ← ctxOf req
  let out ← (← arr req "states").toList.mapM fun s => do pure (evalJson (evalState c (← stateOf s)))
  pure [("states", .arr out.toArray)]

/-- `gate.stale`: sweep hysteresis counts. -/
def opStale (req : Json) : Except String Reply := do
  let c ← ctxOf req
  let out ← (← arr req "pairs").toList.mapM fun p => do
    let (cmp, dif) := stale c (← partsOf (← field p "after")) (← partsOf (← field p "fresh"))
    pure (Json.mkObj [("compared", toJson cmp), ("differ", toJson dif)])
  pure [("stale", .arr out.toArray)]

/-- `gate.tally`: table cells. -/
def opTally (req : Json) : Except String Reply := do
  let out ← (← arr req "cells").toList.mapM fun c => do
    let vs ← (← arr c "verdicts").toList.mapM fun v => do verdictOf (← asStr "verdicts" v)
    let block ← match opt c "block" with
      | none => pure false
      | some b => asBool "block" b
    pure (tallyJson (if block then blockCell vs else some (tally vs)))
  pure [("cells", .arr out.toArray)]

/-- A style value or absent. -/
def ostrOf (j : Json) : Except String (Option String) :=
  match j with
  | .null => pure none
  | .str s => pure (some s)
  | _ => throw "styleEq: expected a string or null"

/-- `gate.styleEq`: compare computed-style values. -/
def opStyleEq (req : Json) : Except String Reply := do
  let out ← (← arr req "pairs").toList.mapM fun p => do
    match (← asArr "pairs" p).toList with
    | [a, b] => do pure (Json.bool (styleValueEq (← ostrOf a) (← ostrOf b)))
    | _ => throw "styleEq: expected [a, b] pairs"
  pure [("eq", .arr out.toArray)]

/-- `gate.cell`: the rule over a list of statuses. -/
def opCell (req : Json) : Except String Reply := do
  let ss ← (← arr req "statuses").toList.mapM fun s => do statusOf (← asStr "statuses" s)
  pure [("verdict", .str (verdictName (cellVerdict ss)))]

/-- `gate.reach`: the reach rule on each requested environment for one port. -/
def opReach (req : Json) : Except String Reply := do
  let pt ← portOf (← str req "port")
  let out ← (← arr req "envs").toList.mapM fun q => do
    pure (match reqReason pt (← requestedOf q) with
      | none => Json.null
      | some r => .str (reasonName r))
  pure [("reasons", .arr out.toArray)]

/-- The ops of this module. -/
def ops : List String := ["gate.state", "gate.stale", "gate.tally", "gate.styleEq", "gate.cell", "gate.reach"]

/-- Dispatch a gate op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "gate.state" => some (opState req)
  | "gate.stale" => some (opStale req)
  | "gate.tally" => some (opTally req)
  | "gate.styleEq" => some (opStyleEq req)
  | "gate.cell" => some (opCell req)
  | "gate.reach" => some (opReach req)
  | _ => none

/-! ## Examples -/

private def run (s : String) : String :=
  match Json.parse s with
  | .error e => e
  | .ok j => match handle ((j.getObjValAs? String "op").toOption.getD "") j with
    | some (.ok r) => (Json.mkObj r).compress
    | some (.error e) => e
    | none => "none"

#guard run "{\"op\":\"gate.cell\",\"statuses\":[\"na\",\"equal\"]}" == "{\"verdict\":\"pass\"}"
#guard run "{\"op\":\"gate.cell\",\"statuses\":[]}" == "{\"verdict\":\"not-comparable\"}"
#guard run "{\"op\":\"gate.styleEq\",\"pairs\":[[\"1px\",\"1.0004px\"],[\"a\",null]]}" == "{\"eq\":[true,false]}"
#guard run "{\"op\":\"gate.tally\",\"cells\":[{\"verdicts\":[],\"block\":true},{\"verdicts\":[\"pass\",\"fail\",\"not-comparable\"]}]}" ==
  "{\"cells\":[{\"failing\":0,\"total\":0,\"unreachable\":0,\"verdict\":\"not-run\"},{\"failing\":1,\"total\":2,\"unreachable\":0,\"verdict\":\"fail\"}]}"
#guard run "{\"op\":\"gate.tally\",\"cells\":[{\"verdicts\":[\"unreachable:whole-width\",\"unreachable:primary-pair\"],\"block\":true},{\"verdicts\":[\"pass\",\"unreachable:width-dpr\"]}]}" ==
  "{\"cells\":[{\"failing\":0,\"total\":0,\"unreachable\":2,\"verdict\":\"unreachable:primary-pair\"},{\"failing\":0,\"total\":1,\"unreachable\":1,\"verdict\":\"pass\"}]}"
#guard run "{\"op\":\"gate.tally\",\"cells\":[{\"verdicts\":[\"unreachable:other\"]}]}" == "unknown verdict unreachable:other"
#guard run ("{\"op\":\"gate.reach\",\"port\":\"webkit-apple\",\"envs\":[" ++
  "{\"width\":600.5,\"height\":900,\"deviceWidth\":600.5,\"dpr\":2,\"hover\":\"hover\",\"pointer\":\"fine\",\"reducedMotion\":\"no-preference\",\"colorScheme\":\"light\"}," ++
  "{\"width\":1024,\"height\":768,\"deviceWidth\":1024,\"dpr\":2,\"hover\":\"none\",\"pointer\":\"fine\",\"reducedMotion\":\"no-preference\",\"colorScheme\":\"light\"}," ++
  "{\"width\":1024,\"height\":768,\"deviceWidth\":1024,\"dpr\":2,\"hover\":\"none\",\"pointer\":\"coarse\",\"reducedMotion\":\"no-preference\",\"colorScheme\":\"light\"}]}") ==
  "{\"reasons\":[\"whole-width\",\"primary-pair\",null]}"
#guard run ("{\"op\":\"gate.reach\",\"port\":\"chromium\",\"envs\":[" ++
  "{\"width\":600.5,\"height\":900,\"deviceWidth\":600.5,\"dpr\":1.25,\"hover\":\"hover\",\"pointer\":\"fine\",\"reducedMotion\":\"no-preference\",\"colorScheme\":\"light\"}]}") ==
  "{\"reasons\":[\"width-dpr\"]}"
#guard run "{\"op\":\"gate.reach\",\"port\":\"gecko\",\"envs\":[]}" == "unknown port gecko"
#guard run "{\"op\":\"gate.state\",\"anchors\":{\"style\":{\"skipPrefixes\":[],\"skipSets\":{}},\"parts\":{}},\"parts\":[\"x\"],\"states\":[]}" ==
  "unknown part x"

end Fw.Wire.Gate
