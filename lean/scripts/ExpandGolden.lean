import Lean.Data.Json
import Fw.Oracle.ExpandWire

open Lean Fw.Wire.OracleExpand

def big : String := String.ofList (List.replicate 40000 'x')

def cases : List (String × String × Json) :=
  let row (c : String) : Json := Json.mkObj [("title", "t"), ("symptom", "s"), ("cause", .str c)]
  let ex (cfg id c : String) (blobs : List (String × Json)) : Json :=
    Json.mkObj [("cfg", .str cfg), ("rowId", .str id), ("row", row c), ("blobs", Json.mkObj blobs)]
  let ans (i c : String) (ps : List (String × Json)) : Json :=
    Json.mkObj [("id", .str i), ("choice", .str c), ("probabilities", Json.mkObj ps)]
  let paired (mode : String) (base arm : List Json) : Json :=
    Json.mkObj [("name", "incident-class"), ("mode", .str mode),
      ("replay", .arr #[Json.mkObj [("id", "a"), ("label", "c-quota")], Json.mkObj [("id", "b"), ("label", "c-late-check")]]),
      ("base", .arr base.toArray), ("arm", .arr arm.toArray)]
  let keys := ((Fw.Oracle.question "incident-class").map (·.spec.keys)).getD []
  let dist (m : List (String × Json)) : List (String × Json) := keys.map fun k => (k, (m.lookup k).getD (.num 0))
  let over := dist [("c-quota", .num ⟨6, 1⟩), ("c-late-check", .num ⟨5, 1⟩)]
  let exact := dist [("c-quota", .num ⟨6, 1⟩), ("c-late-check", .num ⟨4, 1⟩)]
  let exactB := dist [("c-quota", .num ⟨4, 1⟩), ("c-late-check", .num ⟨6, 1⟩)]
  let reply (i c : String) (ps : List (String × Json)) : Json :=
    let a := Json.mkObj [("type", "choice"), ("choice", .str c), ("probabilities", Json.mkObj ps)]
    Json.mkObj [("id", .str i), ("reply", .str (Json.mkObj [("model", .str Fw.Oracle.model),
      ("answers", Json.mkObj [("incident-class", a)])]).compress)]
  let pr (i : String) (b a : Bool) : Json := Json.mkObj [("id", .str i), ("base", .bool b), ("arm", .bool a)]
  let arm (n : String) (ps : List Json) : Json := Json.mkObj [("arm", .str n), ("pairs", .arr ps.toArray)]
  let gains4 := ["g1", "g2", "g3", "g4"].map (pr · false true)
  let strs (l : List String) : Json := .arr (l.map Json.str).toArray
  let adoptReq (arms : List Json) (dropped traced : List String) : Json :=
    Json.mkObj [("arms", .arr arms.toArray), ("dropped", strs dropped), ("traced", strs traced)]
  [("paths: order, ../ and @sha, trailing dot, dedup", "oracle.expandPaths",
      Json.mkObj [("row", row "../scripts/a.mjs@ecdc0787 then apps/b.ts. Again scripts/a.mjs")]),
   ("paths: the allowlist refuses docs, research, oracle code, patterns", "oracle.expandPaths",
      Json.mkObj [("row", row "docs/team/work-graph.json research/x.md lean/Fw/Oracle/Labels.lean scripts/*.mjs lean/Fw/A.lean")]),
   ("paths: naive takes every top directory, no pattern", "oracle.expandPaths",
      Json.mkObj [("cfg", "naive"), ("row", row "docs/team/work-graph.json scripts/a.mjs research/*.md")]),
   ("expand: no path, same row", "oracle.expand", ex "safe" "inc-a" "no path here" []),
   ("expand: only refused paths, same row", "oracle.expand", ex "safe" "inc-a" "docs/team/work-graph.json" []),
   ("expand: one kept file", "oracle.expand", ex "safe" "inc-a" "scripts/a.mjs" [("scripts/a.mjs", "line one\nline \"two\"")]),
   ("expand: a class id drops the file whole", "oracle.expand",
      ex "safe" "inc-a" "scripts/a.mjs scripts/b.mjs" [("scripts/a.mjs", "ok"), ("scripts/b.mjs", "// hardens C-Late-Check")]),
   ("expand: a severity word drops the file", "oracle.expand",
      ex "safe" "inc-a" "scripts/b.mjs" [("scripts/b.mjs", "a follow-up later")]),
   ("expand: the row id drops the file", "oracle.expand", ex "safe" "inc-a" "scripts/b.mjs" [("scripts/b.mjs", "see inc-a")]),
   ("expand: no text blob", "oracle.expand", ex "safe" "inc-a" "scripts/b.mjs" [("scripts/b.mjs", .null)]),
   ("expand: naive keeps the vocabulary file and the work graph", "oracle.expand",
      ex "naive" "inc-a" "scripts/b.mjs docs/team/work-graph.json"
        [("scripts/b.mjs", "// hardens c-late-check"), ("docs/team/work-graph.json", "{\"id\": \"inc-a\"}")]),
   ("expand: over the state cap, refused", "oracle.expand", ex "safe" "inc-a" "scripts/a.mjs" [("scripts/a.mjs", .str big)]),
   ("expand: the fit leaves out the file over the cap and keeps the next", "oracle.expand",
      ex "safe" "inc-a" "scripts/a.mjs scripts/b.mjs scripts/c.mjs"
        [("scripts/a.mjs", "a"), ("scripts/b.mjs", .str big), ("scripts/c.mjs", "c")]),
   ("paired strict: a Jev reply text counts, sums 1.1 fail, a failure is wrong", "oracle.paired",
      paired "strict" [reply "a" "c-quota" exact] [ans "a" "c-quota" over, Json.mkObj [("id", "b"), ("failure", Json.mkObj [])]]),
   ("paired renorm: sums 1.1 count after dividing, b gained", "oracle.paired",
      paired "renorm" [ans "a" "c-quota" exact] [ans "a" "c-quota" over, ans "b" "c-late-check" exactB]),
   ("adopt: four traced gains", "oracle.adopt", adoptReq [arm "jev" gains4] [] ["g1", "g2", "g3", "g4"]),
   ("adopt: net 3", "oracle.adopt",
      adoptReq [arm "jev" (gains4 ++ [pr "l1" true false])] [] ["g1", "g2", "g3", "g4"]),
   ("adopt: a gain on a dropped row and an untraced gain", "oracle.adopt",
      adoptReq [arm "haiku" gains4] ["g1"] ["g1", "g2", "g3"]),
   ("adopt: one arm fails, the other passes", "oracle.adopt",
      adoptReq [arm "jev" gains4, arm "sonnet" []] [] ["g1", "g2", "g3", "g4"])]

def lineOf (n op : String) (req : Json) : Json :=
  let resp : Json := match handle op req with
    | some (.ok f) => Json.mkObj f
    | some (.error e) => Json.mkObj [("error", .str e)]
    | none => Json.mkObj [("error", "unknown op")]
  let reqOp := match req with
    | .obj kvs => Json.obj (kvs.insert "op" (.str op))
    | j => j
  Json.mkObj [("name", .str n), ("request", reqOp), ("response", resp)]

def text : String := String.intercalate "\n" (cases.map fun (n, op, req) => (lineOf n op req).compress) ++ "\n"

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "oracle" / "expand.jsonl"
  let n := cases.length
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"oracle expand golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/ExpandGolden.lean)"
      return 1
    IO.println s!"oracle expand golden: {n} lines, up to date"
    return 0
  if let some d := p.parent then IO.FS.createDirAll d
  IO.FS.writeFile p text
  IO.println s!"oracle expand golden: {n} lines written"
  return 0
