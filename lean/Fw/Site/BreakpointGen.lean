import Lean.Data.Json
import Fw.Site.BreakpointMatrix

/-!
# `breakpoints.gen.json`: the generated breakpoint source for the site and the breakpoint gate

`genJson` is the whole document: the 30 conditions (exact CSS, legacy CSS, TS id, kind, features, edges), the
edge pairs, the fractional gaps, the MUI-internal neutral set with reasons, and the 124-load test matrix with the
expected value of every condition and every neutral query at every probe (golden vectors).

`checkInventory` compares the catalogue and the matrix against `breakpoints.json` (schema `fw.breakpoints/1`)
field by field; the CSS strings are compared byte for byte. `run` is the command-line driver
(`lake exe breakgen [--inventory <path>] [--check <file>]`), and `opBreakpointsGen` is the same as an fwcore op body.
-/

namespace Fw.Site.BreakpointGen

open Lean Fw.Site.Breakpoints

/-- Exact decimal JSON number for a terminating fraction, else `{"num","den"}`.

A CSS length as a JSON number, exactly. -/
def pxJson (x : Px) : Json :=
  match (List.range 13).find? (fun k => (10 ^ k * x.num) % x.den == 0) with
  | some k => .num ⟨Int.ofNat (10 ^ k * x.num / x.den), k⟩
  | none => Json.mkObj [("num", toJson x.num), ("den", toJson x.den)]

#guard (pxJson (Px.half 600)).compress == "600.5"
#guard (pxJson (Px.ofNat 900)).compress == "900"
#guard (pxJson ⟨5, 4, by decide⟩).compress == "1.25"
#guard (pxJson ⟨1, 3, by decide⟩).compress == "{\"den\":3,\"num\":1}"

/-- One catalogue row as JSON.

Everything the site and the gate need to know about one condition. -/
def condJson (c : Entry) : Json :=
  Json.mkObj [
    ("id", .str c.id), ("tsId", .str c.tsId), ("css", .str c.query.css),
    ("legacyCss", match c.query.legacyCss with | some s => .str s | none => .null),
    ("kind", .str c.kind.str),
    ("features", toJson c.query.features),
    ("edges", .arr (c.query.taggedEdges.toArray.map fun (a, n) =>
      Json.mkObj [("feature", .str a.str), ("pair", toJson [n, n + 1])])),
    ("edgesPx", toJson c.query.edgesPx)]

/-- One probe as JSON, with the expected value of all 30 conditions and of the neutral queries.

A golden vector: what `matchMedia` must answer for every condition at this load. -/
def probeJson (p : Probe) : Json :=
  let e := p.env
  Json.mkObj [
    ("id", .str p.id), ("block", .str p.block.str),
    ("width", pxJson e.width), ("height", pxJson e.height),
    ("deviceWidth", pxJson e.deviceWidth), ("deviceHeight", pxJson e.deviceHeight), ("dpr", pxJson e.dpr),
    ("hover", .str (Feature.hoverKw e.hover)), ("pointer", .str (Feature.pointerKw e.pointer)),
    ("reducedMotion", .str (Feature.motionKw e.motion)), ("colorScheme", .str (Feature.schemeKw e.scheme)),
    ("mediaType", .str (Feature.mediaTypeKw e.mediaType)),
    ("forcedColors", .str (Feature.forcedColorsKw e.forcedColors)),
    ("expect", Json.mkObj (catalogue.map fun c => (c.tsId, toJson (c.query.eval e)))),
    ("expectNeutral", Json.mkObj (neutral.map fun n => (n.tsId, toJson (n.query.eval e))))]

/-- The theorems that back the generated file (the gate may print them). -/
def backingTheorems : List String := [
  "Fw.Site.Breakpoints.MQ.eval_congr", "Fw.Site.Breakpoints.MQ.eval_ofNat_congr",
  "Fw.Site.Breakpoints.MQ.eval_const_on_band", "Fw.Site.Breakpoints.catalogue_css",
  "Fw.Site.Breakpoints.catalogue_edges", "Fw.Site.Breakpoints.catalogue_axis_edges",
  "Fw.Site.Breakpoints.matrix_length", "Fw.Site.Breakpoints.matrix_blocks",
  "Fw.Site.Breakpoints.matrix_edge_pairs", "Fw.Site.Breakpoints.matrix_observes_every_edge",
  "Fw.Site.Breakpoints.matrix_pairs_agree", "Fw.Site.Breakpoints.matrix_fractional_in_gaps",
  "Fw.Site.Breakpoints.gap_iff", "Fw.Site.Breakpoints.matrix_neutral_inert",
  "Fw.Site.Breakpoints.matrix_neutral_hover_both_sides"]

/-- The fractional gaps: lower and upper feature, the open pair, and the probe width.

The four gaps the inventory names, with their probes. -/
def gapsJson : Json :=
  .arr (#[600, 640, 860, 1000].map fun n =>
    Json.mkObj [("lower", .str (Feature.widthLe n).css), ("upper", .str (Feature.widthGeSucc n).css),
      ("open", toJson [n, n + 1]), ("probe", pxJson (Px.half n))])

/-- The generated document.

The single source the site and the breakpoint gate consume. -/
def genJson (_ : Unit := ()) : Json :=
  Json.mkObj [
    ("schema", .str "fw.breakpoints.gen/1"),
    ("generatedBy", .str "lean/Fw/Site/BreakpointGen.lean (Fw.Site.BreakpointGen.genJson); do not edit"),
    ("inventory", .str "research/kickoff/11-breakpoints/breakpoints.json (fw.breakpoints/1)"),
    ("backingTheorems", toJson backingTheorems),
    ("conditions", .arr (catalogue.toArray.map condJson)),
    ("edgePairs", Json.mkObj [
      ("width", toJson (widthEdgePairs.map fun n => [n, n + 1])),
      ("deviceWidth", toJson [[500, 501]]),
      ("touchRm", toJson (touchRmEdges.map fun n => [n, n + 1]))]),
    ("fractionalGaps", gapsJson),
    ("neutral", .arr (neutral.toArray.map fun n =>
      Json.mkObj [("tsId", .str n.tsId), ("css", .str n.query.css), ("reason", .str n.reason),
        ("inventoryId", match catalogue.find? (·.query == n.query) with
          | some c => .str c.id | none => .null)])),
    ("matrix", Json.mkObj [
      ("loadsPerEngine", toJson matrix.length),
      ("engines", toJson ["chromium", "playwright-webkit"]),
      ("blocks", .arr (blockBreakdown.toArray.map fun (b, n) =>
        Json.mkObj [("id", .str b.str), ("loads", toJson n)])),
      ("probes", .arr (matrix.toArray.map probeJson))])]

/-! ## Checking against the inventory -/

/-- Read `j[k]` (or `null`). -/
def getK (j : Json) (k : String) : Json := (j.getObjVal? k).toOption.getD .null

/-- A JSON list of naturals, if it is one. -/
def natList (j : Json) : Option (List Nat) := (fromJson? j : Except String (List Nat)).toOption

/-- A JSON list of strings, if it is one. -/
def strList (j : Json) : Option (List String) := (fromJson? j : Except String (List String)).toOption

/-- Mismatches of one catalogue row against its inventory row (empty when equal).

(Each equality requires the inventory field to have the right JSON type; an `equivalentForms` that is not a list of
strings counts as empty.) -/
def checkCond (c : Entry) (inv : Json) : List String :=
  let s (k : String) : Option String := (getK inv k).getStr?.toOption
  let edgesInv : Option (List (String × Nat)) :=
    match getK inv "edges" with
    | .arr es => es.toList.mapM fun e => do
        let f ← (getK e "feature").getStr?.toOption
        let p ← natList (getK e "pair")
        match p with
        | [a, b] => if b == a + 1 then some (f, a) else none
        | _ => none
    | _ => none
  let forms := (strList (getK inv "equivalentForms")).getD []
  (if s "id" == some c.id then [] else [s!"{c.id}: id {s "id"}"]) ++
  (if s "condition" == some c.query.css then []
    else [s!"{c.id}: css {repr c.query.css} vs inventory {repr (s "condition")}"]) ++
  (if s "kind" == some c.kind.str then [] else [s!"{c.id}: kind {c.kind.str} vs {s "kind"}"]) ++
  (if strList (getK inv "features") == some c.query.features then [] else [s!"{c.id}: features"]) ++
  (if edgesInv == some (c.query.taggedEdges.map fun (a, n) => (a.str, n)) then [] else [s!"{c.id}: edges"]) ++
  (if natList (getK inv "edges_px") == some c.query.edgesPx then [] else [s!"{c.id}: edges_px"]) ++
  (if forms.any (·.startsWith "(") then
      match c.query.legacyCss with
      | some l => if forms.contains l then [] else [s!"{c.id}: legacy {l} not in equivalentForms"]
      | none => [s!"{c.id}: no legacy form but inventory lists one"]
    else [])

/-- Every mismatch between the Lean catalogue / matrix and the inventory document (empty when they agree).

Here `R` is the list of `I.conditions` rows whose id starts with `mq.`, in order, `c_i` is the `i`-th catalogue
entry, and every `I.*` field other than `conditions` is read under `I.matrix` (`touch-rm.at` is the `at` field of
the `featureCombos.profiles` entry with id `touch-rm`).

`run` exits 1 when `--inventory` is given and this list is not empty; `opBreakpointsGen` returns the list next to
`gen`. -/
def checkInventory (inv : Json) : List String :=
  let rows := match getK inv "conditions" with
    | .arr cs => cs.toList.filter fun c => ((getK c "id").getStr?.toOption.getD "").startsWith "mq."
    | _ => []
  let m := getK inv "matrix"
  let pairs (j : Json) : Option (List (List Nat)) := (fromJson? j : Except String (List (List Nat))).toOption
  let breakdown := getK (getK m "estimate") "breakdown"
  let touchRm := match getK (getK m "featureCombos") "profiles" with
    | .arr ps => (ps.toList.find? fun p => getK p "id" == Json.str "touch-rm").map (getK · "at")
    | _ => none
  (if rows.length == catalogue.length then [] else [s!"conditions: {rows.length} mq.* rows vs {catalogue.length}"]) ++
  (catalogue.zip rows).flatMap (fun (c, r) => checkCond c r) ++
  (if pairs (getK m "edgePairs") == some (widthEdgePairs.map fun n => [n, n + 1]) then []
    else ["matrix.edgePairs"]) ++
  (if pairs (getK m "deviceWidthPairs") == some [[500, 501]] then [] else ["matrix.deviceWidthPairs"]) ++
  (if touchRm.bind pairs == some (touchRmEdges.map fun n => [n, n + 1]) then [] else ["touch-rm.at"]) ++
  (if (getK (getK m "estimate") "loadsPerEngine").getNat?.toOption == some matrix.length then []
    else ["matrix.estimate.loadsPerEngine"]) ++
  (blockBreakdown.filterMap fun (b, n) =>
    if (getK breakdown b.str).getNat?.toOption == some n then none else some s!"matrix.estimate.breakdown.{b.str}")

/-- fwcore op body `breakpoints.gen`: `{inventory?: <breakpoints.json object>}` → `{gen, mismatches}`.

The result is always `ok`; a request without an `inventory` key (or one that is not a JSON object) gets no
mismatches. -/
def opBreakpointsGen (req : Json) : Except String (List (String × Json)) := do
  let mism := match req.getObjVal? "inventory" with
    | .ok inv => checkInventory inv
    | .error _ => []
  pure [("gen", genJson), ("mismatches", toJson mism)]

/-- The value after the first occurrence of flag `key` that has a successor in the argument list. -/
def argOf : List String → String → Option String
  | k :: v :: rest, key => if k == key then some v else argOf (v :: rest) key
  | _, _ => none

#guard argOf ["--out", "x.json", "--inventory", "i.json"] "--inventory" == some "i.json"
#guard argOf ["--check"] "--out" == none

/-- The exact bytes of the generated file: `genJson` pretty-printed at width 120, newline-terminated.

What `breakgen` prints and what `--check` compares against. -/
def genText (_ : Unit := ()) : String := genJson.pretty 120 ++ "\n"

/-- Command-line driver of `lake exe breakgen [--inventory <breakpoints.json>] [--check <file>]`: without
`--check` it prints the generated JSON to stdout; with `--check <file>` it fails when the file's bytes differ from
the generated text; with `--inventory` it first fails on any mismatch against the inventory.

(An unreadable file raises an IO error; flags are found by `argOf`.) -/
def run (args : List String) : IO UInt32 := do
  if let some invPath := argOf args "--inventory" then
    let inv ← match Json.parse (← IO.FS.readFile invPath) with
      | .ok j => pure j
      | .error e => IO.eprintln s!"breakgen: cannot parse {invPath}: {e}"; return 2
    let bad := checkInventory inv
    for b in bad do IO.eprintln s!"breakgen: inventory mismatch: {b}"
    unless bad.isEmpty do return 1
  match argOf args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == genText.toUTF8.data then
      IO.eprintln s!"breakgen: {path} is up to date (30 conditions, {matrix.length} probes)"
      return 0
    IO.eprintln s!"breakgen: {path} differs from the generated bytes; regenerate with `lake exe breakgen > {path}`"
    return 1
  | none =>
    IO.print genText
    return 0

end Fw.Site.BreakpointGen
