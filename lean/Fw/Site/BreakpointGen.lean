import Lean.Data.Json
import Fw.Site.BreakpointMatrix

/-!
# `breakpoints.gen.json`: the generated breakpoint source for the site and the breakpoint gate

`genJson` is the whole document: the 30 conditions (exact CSS, legacy CSS, TS id, kind, features, edges), the
edge pairs, the fractional gaps, the MUI-internal neutral set with reasons, and the 124-load test matrix with the
expected value of every condition and every neutral query at every probe (golden vectors).

`checkInventory` compares the catalogue and the matrix against `breakpoints.json` (schema `fw.breakpoints/1`)
field by field; the CSS strings are compared byte for byte. `run` is the command-line driver
(`--inventory <path> --out <path> [--check]`), and `opBreakpointsGen` is the same as an fwcore op body.
-/

namespace Fw.Site.BreakpointGen

open Lean Fw.Site.Breakpoints

/-- Exact decimal JSON number for a terminating fraction, else `{"num","den"}`.

$$ \mathrm{pxJson}(p/q) = \begin{cases} m \cdot 10^{-k} & \text{least } k \le 12 \text{ with } q \mid 10^k p,\ m = 10^k p / q \\ \{p, q\} & \text{otherwise} \end{cases} $$

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

$$ \mathrm{condJson}(c) = \{\mathrm{id}, \mathrm{tsId}, \mathrm{css}(q), \mathrm{legacyCss}(q), \mathrm{kind}, \mathrm{features}(q), E(q), \mathrm{edgesPx}(q)\} $$

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

$$ \mathrm{probeJson}(p) = \{\mathrm{id}, \mathrm{block}, e_p, (\mathrm{ts}_i \mapsto \llbracket q_i \rrbracket_{e_p})_{i<30}, (n \mapsto \llbracket n \rrbracket_{e_p})_{n \in \mathrm{neutral}}\} $$

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

/-- The theorems that back the generated file (the gate may print them).

$$ \mathrm{backing} = (\texttt{MQ.eval\_congr}, \dots, \texttt{matrix\_neutral\_hover\_both\_sides}) $$ -/
def backingTheorems : List String := [
  "Fw.Site.Breakpoints.MQ.eval_congr", "Fw.Site.Breakpoints.MQ.eval_ofNat_congr",
  "Fw.Site.Breakpoints.MQ.eval_const_on_band", "Fw.Site.Breakpoints.catalogue_css",
  "Fw.Site.Breakpoints.catalogue_edges", "Fw.Site.Breakpoints.catalogue_axis_edges",
  "Fw.Site.Breakpoints.matrix_length", "Fw.Site.Breakpoints.matrix_blocks",
  "Fw.Site.Breakpoints.matrix_edge_pairs", "Fw.Site.Breakpoints.matrix_observes_every_edge",
  "Fw.Site.Breakpoints.matrix_pairs_agree", "Fw.Site.Breakpoints.matrix_fractional_in_gaps",
  "Fw.Site.Breakpoints.gap_iff", "Fw.Site.Breakpoints.matrix_neutral_inert",
  "Fw.Site.Breakpoints.matrix_neutral_hover_both_sides"]

/-- The fractional gaps: lower and upper feature, and the probe width.

$$ \mathrm{gaps} = ((w \le N, w \ge N{+}1, N + \tfrac12))_{N \in \{600, 640, 860, 1000\}} $$

The four gaps the inventory names, with their probes. -/
def gapsJson : Json :=
  .arr (#[600, 640, 860, 1000].map fun n =>
    Json.mkObj [("lower", .str (Feature.widthLe n).css), ("upper", .str (Feature.widthGeSucc n).css),
      ("open", toJson [n, n + 1]), ("probe", pxJson (Px.half n))])

/-- The generated document.

$$ \mathrm{genJson} = \{\mathrm{conditions}, \mathrm{edgePairs}, \mathrm{fractionalGaps}, \mathrm{neutral}, \mathrm{matrix}\} $$

The single source the site and the breakpoint gate consume. -/
def genJson : Json :=
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

/-- Read `j[k]` (or `null`).

$$ \mathrm{getK}(j, k) = \begin{cases} j[k] & k \in j \\ \mathrm{null} & \text{otherwise} \end{cases} $$ -/
def getK (j : Json) (k : String) : Json := (j.getObjVal? k).toOption.getD .null

/-- A JSON list of naturals, if it is one.

$$ \mathrm{natList}(j) \in \mathbb{N}^* \cup \{\bot\} $$ -/
def natList (j : Json) : Option (List Nat) := (fromJson? j : Except String (List Nat)).toOption

/-- A JSON list of strings, if it is one.

$$ \mathrm{strList}(j) \in \Sigma^{**} \cup \{\bot\} $$ -/
def strList (j : Json) : Option (List String) := (fromJson? j : Except String (List String)).toOption

/-- Mismatches of one catalogue row against its inventory row (empty when equal).

$$ \mathrm{checkCond}(c, r) = [\,] \iff \mathrm{css}(q) = r.\mathrm{condition} \land \kappa = r.\mathrm{kind} \land \mathrm{features}(q) = r.\mathrm{features} \land E(q) = r.\mathrm{edges} \land \dots $$ -/
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

$$ \mathrm{checkInventory}(I) = [\,] \iff \forall i < 30.\ \mathrm{row}_i(\mathrm{catalogue}) = \mathrm{row}_i(I) \land M \text{ agrees with } I.\mathrm{matrix} $$

The generator refuses to write unless this list is empty. -/
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

$$ \mathrm{op}(\mathit{req}) = \{\mathrm{gen} = \mathrm{genJson},\ \mathrm{mismatches} = \mathrm{checkInventory}(\mathit{req}.\mathrm{inventory})\} $$ -/
def opBreakpointsGen (req : Json) : Except String (List (String × Json)) := do
  let mism := match req.getObjVal? "inventory" with
    | .ok inv => checkInventory inv
    | .error _ => []
  pure [("gen", genJson), ("mismatches", toJson mism)]

/-- The value after flag `key` in an argument list.

$$ \mathrm{argOf}(\dots, k, v, \dots;\ k) = v $$ -/
def argOf : List String → String → Option String
  | k :: v :: rest, key => if k == key then some v else argOf (v :: rest) key
  | _, _ => none

#guard argOf ["--out", "x.json", "--inventory", "i.json"] "--inventory" == some "i.json"
#guard argOf ["--check"] "--out" == none

/-- Command-line driver: `--inventory <breakpoints.json> --out <breakpoints.gen.json> [--check]`.
Fails (exit 1) on any inventory mismatch; with `--check`, fails if the file on disk differs from the
generated text instead of writing it.

$$ \mathrm{run}(I, o) = \begin{cases} \text{write } \mathrm{genJson} \text{ to } o & \mathrm{checkInventory}(I) = [\,] \\ \text{exit } 1 & \text{otherwise} \end{cases} $$ -/
def run (args : List String) : IO UInt32 := do
  let some invPath := argOf args "--inventory" | IO.eprintln "usage: --inventory <path> --out <path> [--check]"; return 2
  let some outPath := argOf args "--out" | IO.eprintln "usage: --inventory <path> --out <path> [--check]"; return 2
  let inv ← match Json.parse (← IO.FS.readFile invPath) with
    | .ok j => pure j
    | .error e => IO.eprintln s!"breakpoints.gen: cannot parse {invPath}: {e}"; return 2
  let bad := checkInventory inv
  for b in bad do IO.eprintln s!"breakpoints.gen: inventory mismatch: {b}"
  unless bad.isEmpty do return 1
  let text := genJson.pretty 120 ++ "\n"
  if args.contains "--check" then
    let cur ← IO.FS.readFile outPath
    if cur == text then
      IO.println s!"breakpoints.gen: {outPath} is up to date; inventory agrees (30 conditions, {matrix.length} probes)"
      return 0
    IO.eprintln s!"breakpoints.gen: {outPath} is stale; regenerate"
    return 1
  IO.FS.writeFile outPath text
  IO.println s!"breakpoints.gen: wrote {outPath}; inventory agrees (30 conditions, {matrix.length} probes)"
  return 0

end Fw.Site.BreakpointGen
