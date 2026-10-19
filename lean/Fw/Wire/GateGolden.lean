import Fw.Ops.Golden
import Fw.Site.BreakpointGen
/-!
# Golden vectors of the gate ops (`gate.*`)

Inputs: `packages/contracts/golden/gate/cases.json`, built from saved gate runs by
`packages/gate-breakpoints/scripts/golden-cases.mjs`: one `{name, request, saved?}` per case, where `request` is
an fwcore request built from saved raw records and `saved` is what the saved `summary.json` of that run reported
(the JavaScript rule wrote it, before the rule moved to Lean). Outputs, generated from Lean, never by hand:

* `gate.jsonl`: `{name, response}` per case of `cases.json`, the reply without the `id`;
* `literal.jsonl`: `{name, request, response}` per literal case below (the small ops and the refusals).

```
cd lean && lake env lean --run scripts/GateGolden.lean           # write the files
cd lean && lake env lean --run scripts/GateGolden.lean --check   # fail if a file is stale
```

Both modes also fail when a reply disagrees with a case's `saved` (every field of `saved` must equal the same
field of the reply, recursively; arrays element by element). `lake test` runs the check. Consumer:
`packages/gate-breakpoints/test/verdict.test.mjs` replays every case through the `fwcore` binary.
-/
namespace Fw.Wire.Gate.Golden
open Lean
open Fw.Wire.Ops.Golden (lit withOp respond)

/-- Every field of `s` is in `r` with an agreeing value (objects: per key; arrays: same length, per element;
otherwise equal JSON). `fuel` bounds the depth. -/
def agrees : Nat → Json → Json → Bool
  | 0, _, _ => false
  | n + 1, .obj kvs, r => kvs.toList.all fun (k, v) =>
      match r.getObjVal? k with
      | .ok rv => agrees n v rv
      | .error _ => false
  | n + 1, .arr xs, .arr ys => xs.size == ys.size && (xs.toList.zip ys.toList).all fun (x, y) => agrees n x y
  | _ + 1, s, r => s.compress == r.compress

#guard agrees 8 (lit "{\"a\":[1,{\"b\":true}]}") (lit "{\"a\":[1,{\"b\":true,\"c\":2}],\"d\":0}")
#guard !agrees 8 (lit "{\"a\":[1]}") (lit "{\"a\":[1,2]}")
#guard !agrees 8 (lit "{\"a\":\"pass\"}") (lit "{\"a\":\"fail\"}")
#guard !agrees 8 (lit "{\"a\":1}") (lit "{}")

/-- The small anchors of the literal cases: one prefix skip, one skip set, one part whose units are boxed relative
to its frame (the frame itself compares only its width). -/
def anchors : String :=
  "{\"style\":{\"skipPrefixes\":[{\"prefix\":\"animation\",\"why\":\"motion is not layout\"}],\"skipSets\":{\"ld\":{\"props\":[\"width\"],\"why\":\"derived from the box\"}}},\"parts\":{\"p\":{\"roles\":[{\"role\":\"box\",\"boxRel\":null,\"dims\":[\"w\"],\"skipSets\":[\"ld\"],\"skipProps\":[],\"why\":\"the frame\"},{\"role\":\"unit\",\"boxRel\":{\"role\":\"box\",\"index\":0},\"dims\":[\"x\"],\"skipSets\":[],\"skipProps\":[],\"why\":\"the units\"}]}}}"

/-- Recorded properties: `color` and `width` restated on both roles, `extra` only on the original's units. -/
def props : String :=
  "{\"p\":{\"box\":{\"restated\":[\"color\",\"width\",\"animation-name\"],\"originOnly\":[]},\"unit\":{\"restated\":[\"color\"],\"originOnly\":[\"extra\"]}}}"

/-- One arm: a box at `bx`, two units at `u0`, `u1` (absolute x), unit color `c`, extra `e`, matchMedia `t`. -/
def arm (bx u0 u1 : String) (c e t : String) : String :=
  "{\"viewport\":{\"innerHeight\":900,\"screenWidth\":1280,\"dpr\":1},\"observed\":{\"widthExact\":true,\"hoverHover\":true,\"hoverNone\":false,\"pointerFine\":true,\"pointerCoarse\":false,\"reducedMotion\":false,\"dark\":false},\"truth\":[[\"(width >= 600px)\"," ++ t ++ "]],\"truthLegacy\":[[\"(width >= 600px)\"," ++ t ++ "]],\"neutral\":[[\"print\",false]],\"parts\":{\"p\":{\"box\":{\"count\":1,\"items\":[{\"rect\":{\"x\":" ++ bx ++ ",\"y\":0,\"w\":100,\"h\":10},\"style\":{\"color\":\"red\",\"width\":\"" ++ bx ++ "px\",\"animation-name\":\"" ++ bx ++ "\"}}]},\"unit\":{\"count\":2,\"items\":[{\"rect\":{\"x\":" ++ u0 ++ ",\"y\":0,\"w\":5,\"h\":5},\"style\":{\"color\":\"" ++ c ++ "\",\"extra\":\"" ++ e ++ "\"}},{\"rect\":{\"x\":" ++ u1 ++ ",\"y\":0,\"w\":5,\"h\":5},\"style\":{\"color\":\"" ++ c ++ "\",\"extra\":\"" ++ e ++ "\"}}]}}}}"

/-- The requested environment of the literal states. -/
def requested : String :=
  "{\"width\":1280,\"height\":900,\"deviceWidth\":1280,\"dpr\":1,\"hover\":\"hover\",\"pointer\":\"fine\",\"reducedMotion\":\"no-preference\",\"colorScheme\":\"light\"}"

/-- A fractional requested environment (600.5 px at DPR 2, desktop inputs). -/
def requestedHalf : String :=
  "{\"width\":600.5,\"height\":900,\"deviceWidth\":600.5,\"dpr\":2,\"hover\":\"hover\",\"pointer\":\"fine\",\"reducedMotion\":\"no-preference\",\"colorScheme\":\"light\"}"

/-- A cross requested environment (hover `hover` with pointer `coarse`, 1200 px). -/
def requestedCross : String :=
  "{\"width\":1200,\"height\":900,\"deviceWidth\":1200,\"dpr\":1,\"hover\":\"hover\",\"pointer\":\"coarse\",\"reducedMotion\":\"no-preference\",\"colorScheme\":\"light\"}"

/-- A `gate.state` request over the literal anchors with one state (`port`: the JSON of the optional port
field, empty for none). -/
def stateReq (o r : String) (expect : String) (expectNeutral : String := "[[\"print\",false]]")
    (req : String := requested) (port : String := "") : Json :=
  lit ("{\"anchors\":" ++ anchors ++ ",\"parts\":[\"p\"],\"props\":" ++ props ++ ",\"deviceEdges\":[[500,501]]" ++
    (if port.isEmpty then "" else ",\"port\":" ++ port) ++ ",\"states\":[{\"requested\":" ++ req ++ ",\"orig\":" ++ o ++ ",\"rewrite\":" ++ r ++ ",\"expect\":" ++ expect ++ ",\"expectNeutral\":" ++ expectNeutral ++ "}]}")

/-- The requested fields of a matrix probe. -/
def probeReq (p : Fw.Site.Breakpoints.Probe) : Json :=
  let j := Fw.Site.BreakpointGen.probeJson p
  Json.mkObj (["width", "height", "deviceWidth", "dpr", "hover", "pointer", "reducedMotion", "colorScheme"].map
    fun k => (k, j.getObjValD k))

/-- A `gate.reach` request over the whole matrix for one port. -/
def matrixReach (port : String) : Json :=
  Json.mkObj [("port", .str port), ("envs", .arr (Fw.Site.Breakpoints.matrix.map probeReq).toArray)]

/-- Anchors with one part `c` whose variant `strip` replaces role `face` by role `strip`, counted against `digit`
(`newRole`: the new role's name). -/
def variantAnchors (newRole : String := "strip") : String :=
  "{\"style\":{\"skipPrefixes\":[],\"skipSets\":{}},\"parts\":{\"c\":{\"roles\":[" ++
  "{\"role\":\"digit\",\"boxRel\":null,\"dims\":[],\"skipSets\":[],\"skipProps\":[],\"why\":\"digits\"}," ++
  "{\"role\":\"face\",\"boxRel\":null,\"dims\":[],\"skipSets\":[],\"skipProps\":[],\"why\":\"faces\"}]," ++
  "\"variantRoles\":[{\"variant\":\"strip\",\"replaces\":\"face\",\"role\":\"" ++ newRole ++
  "\",\"countOf\":\"digit\",\"why\":\"one strip per digit\"}]}}}"

/-- A bare arm with the parts JSON `parts`. -/
def bareArm (parts : String) : String :=
  "{\"viewport\":{},\"observed\":{},\"truth\":[],\"truthLegacy\":[],\"neutral\":[],\"parts\":" ++ parts ++ "}"

/-- A `gate.state` request on part `c`: the original has 2 digits and 20 faces, the rewrite 2 digits, no face and
`strips` strips; `variants`: the JSON of the optional `variants` field, empty for none. -/
def variantReq (strips : Nat) (variants : String) (newRole : String := "strip") : Json :=
  let o := bareArm "{\"c\":{\"digit\":{\"count\":2,\"items\":[]},\"face\":{\"count\":20,\"items\":[]}}}"
  let r := bareArm ("{\"c\":{\"digit\":{\"count\":2,\"items\":[]},\"face\":{\"count\":0,\"items\":[]},\"strip\":{\"count\":" ++
    toString strips ++ ",\"items\":[{\"rect\":null,\"style\":{\"transform\":\"none\"}}]}}}")
  lit ("{\"anchors\":" ++ variantAnchors newRole ++ ",\"parts\":[\"c\"],\"deviceEdges\":[]" ++
    (if variants.isEmpty then "" else ",\"variants\":" ++ variants) ++ ",\"states\":[{\"requested\":" ++ requested ++
    ",\"orig\":" ++ o ++ ",\"rewrite\":" ++ r ++ ",\"expect\":null,\"expectNeutral\":null}]}")

/-- The literal cases: (name, op, request without op). -/
def literalCases : List (String × String × Json) := [
  ("cell: no applicable item is not comparable", "gate.cell", lit "{\"statuses\":[\"na\",\"na\"]}"),
  ("cell: equal and na pass", "gate.cell", lit "{\"statuses\":[\"equal\",\"na\",\"equal\"]}"),
  ("cell: a missing item fails", "gate.cell", lit "{\"statuses\":[\"na\",\"missing\"]}"),
  ("cell: an unknown status is refused", "gate.cell", lit "{\"statuses\":[\"same\"]}"),
  ("styleEq: exact decimals, the tolerance 1/1000 is inclusive", "gate.styleEq",
   lit "{\"pairs\":[[\"120px\",\"120.001px\"],[\"rgb(115.001, 115, 115)\",\"rgb(115, 115, 115)\"],[\"120px\",\"120.0011px\"],[\"120px\",\"120em\"],[\"1e3px\",\"1000px\"],[\"auto\",null],[null,null]]}"),
  ("tally: an empty block is not-run; an empty sweep is not comparable", "gate.tally",
   lit "{\"cells\":[{\"verdicts\":[],\"block\":true},{\"verdicts\":[]},{\"verdicts\":[\"pass\",\"not-comparable\",\"fail\",\"fail\"],\"block\":true}]}"),
  ("state: units shifted with their box, same colors: every row passes; the skipped width and animation never fail",
   "gate.state", stateReq (arm "10" "20" "40" "red" "a" "true") (arm "110" "120" "140" "red" "b" "true") "[[\"(width >= 600px)\",true]]"),
  ("state: a unit moved 0.75 px against its box, a color differs, Lean's value differs on both arms",
   "gate.state", stateReq (arm "10" "20" "40" "red" "a" "true") (arm "10" "20.75" "40" "blue" "a" "true") "[[\"(width >= 600px)\",false]]"),
  ("state: no vector (expect and expectNeutral null): the Lean row is not comparable; orig and rewrite disagree",
   "gate.state", stateReq (arm "10" "20" "40" "red" "a" "true") (arm "10" "20" "40" "red" "a" "false") "null" "null"),
  ("state: an unknown part is refused", "gate.state",
   lit ("{\"anchors\":" ++ anchors ++ ",\"parts\":[\"q\"],\"states\":[]}")),
  ("state: a skip set without a reason is refused", "gate.state",
   lit "{\"anchors\":{\"style\":{\"skipPrefixes\":[],\"skipSets\":{\"ld\":{\"props\":[\"width\"],\"why\":\"\"}}},\"parts\":{}},\"parts\":[],\"states\":[]}"),
  ("stale: the box moved after the sweep, against a fresh load", "gate.stale",
   lit ("{\"anchors\":" ++ anchors ++ ",\"parts\":[\"p\"],\"props\":" ++ props ++ ",\"pairs\":[{\"after\":" ++
     ((lit (arm "10" "20" "40" "red" "a" "true")).getObjValD "parts").compress ++ ",\"fresh\":" ++
     ((lit (arm "12" "20" "40" "red" "a" "true")).getObjValD "parts").compress ++ "}]}")),
  ("tally: unreachable verdicts count neither pass nor fail; an all-unreachable cell is unreachable", "gate.tally",
   lit "{\"cells\":[{\"verdicts\":[\"unreachable:whole-width\",\"unreachable:primary-pair\"],\"block\":true},{\"verdicts\":[\"unreachable:width-dpr\",\"pass\"]},{\"verdicts\":[\"unreachable:whole-width\",\"fail\"]},{\"verdicts\":[\"unreachable:whole-width\",\"not-comparable\"]}]}"),
  ("state: a fractional width on WebKit (Apple) is unreachable: every row, the verdict, and no failing item",
   "gate.state", stateReq (arm "10" "20" "40" "red" "a" "true") (arm "10" "20.75" "40" "blue" "a" "true") "[[\"(width >= 600px)\",false]]"
     (req := requestedHalf) (port := "\"webkit-apple\"")),
  ("state: the same fractional state on Chromium is reachable (600.5 x 2 is whole) and fails",
   "gate.state", stateReq (arm "10" "20" "40" "red" "a" "true") (arm "10" "20.75" "40" "blue" "a" "true") "[[\"(width >= 600px)\",false]]"
     (req := requestedHalf) (port := "\"chromium\"")),
  ("state: hover with a coarse pointer on WebKit (GLib) is unreachable by its primary pair",
   "gate.state", stateReq (arm "10" "20" "40" "red" "a" "true") (arm "10" "20" "40" "red" "a" "true") "[[\"(width >= 600px)\",true]]"
     (req := requestedCross) (port := "\"webkit-glib\"")),
  ("state: a part failure fails the state verdict even when every matchMedia row passes",
   "gate.state", stateReq (arm "10" "20" "40" "red" "a" "true") (arm "10" "20" "40" "blue" "a" "true") "[[\"(width >= 600px)\",true]]"
     (port := "null")),
  ("state: an unknown port is refused", "gate.state",
   stateReq (arm "10" "20" "40" "red" "a" "true") (arm "10" "20" "40" "red" "a" "true") "null" (port := "\"gecko\"")),
  ("reach: every matrix probe on Chromium (all reachable)", "gate.reach", matrixReach "chromium"),
  ("reach: every matrix probe on WebKit (Apple): the fractional and cross probes are unreachable", "gate.reach",
   matrixReach "webkit-apple"),
  ("reach: every matrix probe on WebKit (GLib): the fractional and cross probes are unreachable", "gate.reach",
   matrixReach "webkit-glib"),
  ("state, variant strip: the faces are not judged; 2 strips against the original's 2 digits pass", "gate.state",
   variantReq 2 "{\"c\":\"strip\"}"),
  ("state, variant strip: 3 strips against the original's 2 digits fail on the strip count", "gate.state",
   variantReq 3 "{\"c\":\"strip\"}"),
  ("state, variant faithful (no variant role): the face count 20 against 0 fails", "gate.state",
   variantReq 2 "{\"c\":\"faithful\"}"),
  ("state, no variants field: the plain roles are judged", "gate.state", variantReq 2 ""),
  ("state: a variant role whose new role name is already a role is refused", "gate.state",
   variantReq 2 "{\"c\":\"strip\"}" (newRole := "digit"))]

/-- The text of `literal.jsonl`. -/
def literalText : String :=
  String.join (literalCases.map fun (name, op, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- One case of `cases.json`: (name, op, request, saved). -/
def caseOf (j : Json) : Except String (String × String × Json × Option Json) := do
  let name ← j.getObjValAs? String "name"
  let req ← j.getObjVal? "request"
  let op ← req.getObjValAs? String "op"
  pure (name, op, req, (j.getObjVal? "saved").toOption)

/-- The golden directory, relative to `lean/`. -/
def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "gate"

/-- Compare (or write) `gate.jsonl` and `literal.jsonl`, and check every reply against its case's `saved`;
returns the number of stale files plus disagreeing cases. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  let src ← IO.FS.readFile (d / "cases.json")
  let cases ← match Json.parse src >>= fun j => do (← j.getArr?).toList.mapM caseOf with
    | .ok cs => pure cs
    | .error e => throw (IO.userError s!"gate golden: {d / "cases.json"}: {e}")
  let mut bad := 0
  let mut text := ""
  for (name, op, req, saved) in cases do
    let resp := respond op req
    if (resp.getObjVal? "error").isOk then
      IO.println s!"gate golden: {name}: {resp.compress.take 300}"
      bad := bad + 1
    if let some s := saved then
      unless agrees 64 s resp do
        IO.println s!"gate golden: {name}: the reply disagrees with the saved summary"
        bad := bad + 1
    text := text ++ (Json.mkObj [("name", .str name), ("response", resp)]).compress ++ "\n"
  for (stem, t) in [("gate", text), ("literal", literalText)] do
    let p := d / s!"{stem}.jsonl"
    if write then
      IO.FS.writeFile p t
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != t then
        IO.println s!"gate golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/GateGolden.lean)"
        bad := bad + 1
  IO.println s!"gate golden: {cases.length} saved-run cases ({(cases.filter (·.2.2.2.isSome)).length} checked against saved summaries), {literalCases.length} literal cases, {if write then "written" else "checked"}, {bad} problems"
  return bad

end Fw.Wire.Gate.Golden
