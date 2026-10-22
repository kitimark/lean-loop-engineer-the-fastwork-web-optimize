import Lean.Data.Json
import Fw.Oracle.RetrieveWire

open Lean Fw.Wire.OracleRetrieve

def cases : List (String × String × Json) :=
  let strs (l : List String) : Json := .arr (l.map Json.str).toArray
  let row : Json := Json.mkObj [("title", "t"), ("symptom", "s"), ("cause", "c")]
  let call (tool path : String) (bytes : Nat) (glob : String := "") : Json :=
    Json.mkObj ([("tool", .str tool), ("path", .str path), ("bytes", toJson bytes)] ++
      if glob == "" then [] else [("glob", .str glob)])
  let hookReq (c : Json) (calls bytes : Nat) : Json :=
    Json.mkObj [("root", "/t"), ("paths", strs ["apps/a.ts", "scripts/b.mjs"]),
      ("state", Json.mkObj [("calls", toJson calls), ("bytes", toJson bytes)]), ("call", c)]
  let traceReq (cs : List Json) : Json :=
    Json.mkObj [("root", "/t"), ("paths", strs ["apps/a.ts", "scripts/b.mjs"]), ("calls", .arr cs.toArray)]
  let rng (p : String) (a b : Nat) : Json := Json.mkObj [("path", .str p), ("first", toJson a), ("last", toJson b)]
  let pr (i : String) (b a : Bool) : Json := Json.mkObj [("id", .str i), ("base", .bool b), ("arm", .bool a)]
  let gains4 := ["g1", "g2", "g3", "g4"].map (pr · false true)
  let adoptReq (vsC vsX : List Json) (dropped traced : List String) : Json :=
    Json.mkObj [("arm", "t-sonnet"), ("vsC", .arr vsC.toArray), ("vsX", .arr vsX.toArray), ("dropped", strs dropped),
      ("traced", strs traced)]
  let item (i : String) (s t : Nat) : Json := Json.mkObj [("id", .str i), ("sends", toJson s), ("tokens", toJson t)]
  let pk (cs : List String) (p : Option String) : Json :=
    Json.mkObj [("candidates", strs cs), ("pick", match p with | some x => .str x | none => .null)]
  let ev (t d : String) : Json := Json.mkObj [("tool", .str t), ("decision", .str d)]
  let lines := "\n".intercalate ((List.range 12).map fun i => "line " ++ toString (i + 1))
  [("scope: a kept or over-cap file, or a drop for a word that is not a class id", "oracle.retrieveScope",
      Json.mkObj [("rows", .arr #[
        Json.mkObj [("id", "k"), ("files", .arr #[Json.mkObj [("verdict", "kept")]])],
        Json.mkObj [("id", "o"), ("files", .arr #[Json.mkObj [("verdict", "notAllowed")], Json.mkObj [("verdict", "overCap")]])],
        Json.mkObj [("id", "b"), ("files", .arr #[Json.mkObj [("verdict", "vocab"), ("word", "blocker")]])],
        Json.mkObj [("id", "c"), ("files", .arr #[Json.mkObj [("verdict", "vocab"), ("word", "c-quota")]])],
        Json.mkObj [("id", "n"), ("files", .arr #[])]])]),
   ("vocab: the class ids, the exact words and the row id", "oracle.retrieveVocab", Json.mkObj [("rowId", "inc-a")]),
   ("tree: allowlist, no text, vocabulary in the text any case, vocabulary in the path", "oracle.retrieveTree",
      Json.mkObj [("rowId", "inc-a"), ("blobs", Json.mkObj [("apps/a.ts", "ok"), ("docs/x.md", "ok"),
        ("lean/Fw/Oracle/Labels.lean", "ok"), ("scripts/n.mjs", .null), ("scripts/c.mjs", "// C-LATE-CHECK"),
        ("scripts/inc-a.mjs", "ok"), ("apps/s.ts", "a follow-up"), ("apps/u.ts", "ünïcode ok")])]),
   ("hook: a read in the tree", "oracle.retrieveHook", hookReq (call "Read" "/t/apps/a.ts" 100) 0 0),
   ("hook: a relative grep over a directory of the tree", "oracle.retrieveHook",
      hookReq (call "Grep" "scripts" 0 "*.mjs") 1 100),
   ("hook: a grep with no path searches the root", "oracle.retrieveHook", hookReq (call "Grep" "" 0) 0 0),
   ("hook: a read outside the root", "oracle.retrieveHook", hookReq (call "Read" "/etc/hosts" 10) 0 0),
   ("hook: a read of a file not in the tree", "oracle.retrieveHook", hookReq (call "Read" "/t/docs/x.md" 10) 0 0),
   ("hook: dot-dot leaves the tree", "oracle.retrieveHook", hookReq (call "Read" "/t/apps/../../x" 10) 0 0),
   ("hook: a glob that climbs", "oracle.retrieveHook", hookReq (call "Glob" "/t" 0 "../**") 0 0),
   ("hook: another tool", "oracle.retrieveHook", hookReq (call "Bash" "/t/apps/a.ts" 0) 0 0),
   ("hook: the ninth call", "oracle.retrieveHook", hookReq (call "Read" "/t/apps/a.ts" 1) 8 100),
   ("hook: the read that passes 32 KiB", "oracle.retrieveHook", hookReq (call "Read" "/t/apps/a.ts" 2000) 3 31000),
   ("trace: in budget", "oracle.retrieveTrace",
      traceReq [call "Glob" "/t" 0 "**/*.ts", call "Read" "/t/apps/a.ts" 900, call "Read" "scripts/b.mjs" 100]),
   ("trace: one call outside", "oracle.retrieveTrace", traceReq [call "Read" "/t/apps/a.ts" 900, call "Read" "/u/x" 1]),
   ("trace: nine calls", "oracle.retrieveTrace", traceReq ((List.range 9).map fun _ => call "Read" "/t/apps/a.ts" 1)),
   ("trace: over the bytes", "oracle.retrieveTrace",
      traceReq [call "Read" "/t/apps/a.ts" 30000, call "Read" "/t/scripts/b.mjs" 3000]),
   ("ranges: runs per path, sorted, overlaps merged", "oracle.retrieveRanges",
      Json.mkObj [("reads", .arr #[Json.mkObj [("path", "a"), ("lines", .arr ((([5, 1, 2, 3, 9, 10, 3] : List Nat).map toJson).toArray))],
        Json.mkObj [("path", "b"), ("lines", .arr #[toJson (7 : Nat)])],
        Json.mkObj [("path", "a"), ("lines", .arr #[toJson (4 : Nat)])]])]),
   ("evidence: inside a read range, past it, another file, line 0, reversed", "oracle.retrieveEvidence",
      Json.mkObj [("ranges", .arr #[rng "a" 1 6, rng "a" 9 10]),
        ("evidence", .arr #[rng "a" 2 4, rng "a" 5 9, rng "b" 1 1, rng "a" 0 1, rng "a" 4 3, rng "a" 9 10])]),
   ("evidence: absolute paths under the root count as relative; a path outside the root stays as given", "oracle.retrieveEvidence",
      Json.mkObj [("root", "/t"), ("ranges", .arr #[rng "a" 1 6]),
        ("evidence", .arr #[rng "/t/a" 2 4, rng "./a" 5 6, rng "/u/a" 2 4])]),
   ("pick1: candidates deduped, sorted, at most four", "oracle.retrievePick1",
      Json.mkObj [("row", row), ("paths", strs ["scripts/e.mjs", "apps/a.ts", "scripts/d.mjs", "apps/a.ts", "scripts/c.mjs",
        "apps/b.ts"])]),
   ("pick1: no candidate", "oracle.retrievePick1", Json.mkObj [("row", row), ("paths", strs [])]),
   ("pick: the top slot names a file, its excerpt joins the row", "oracle.retrievePick",
      Json.mkObj [("candidates", strs ["apps/a.ts", "scripts/b.mjs"]), ("probabilities", Json.mkObj [("f1", .num ⟨2, 1⟩),
        ("f2", .num ⟨7, 1⟩), ("none", .num ⟨1, 1⟩)]), ("row", row), ("texts", Json.mkObj [("scripts/b.mjs", "x\ny")])]),
   ("pick: none on top, the row stays", "oracle.retrievePick",
      Json.mkObj [("candidates", strs ["apps/a.ts"]), ("probabilities", Json.mkObj [("f1", .num ⟨4, 1⟩),
        ("none", .num ⟨6, 1⟩)]), ("row", row), ("texts", Json.mkObj [("apps/a.ts", "x")])]),
   ("pick: a tie goes to the earlier slot", "oracle.retrievePick",
      Json.mkObj [("candidates", strs ["apps/a.ts", "scripts/b.mjs"]), ("probabilities", Json.mkObj [("f1", .num ⟨5, 1⟩),
        ("f2", .num ⟨5, 1⟩)]), ("row", row), ("texts", Json.mkObj [("apps/a.ts", "x")])]),
   ("pick: no candidates, no send", "oracle.retrievePick",
      Json.mkObj [("candidates", strs []), ("row", row)]),
   ("pick: the excerpt stops at 8 KiB on a line end", "oracle.retrievePick",
      Json.mkObj [("candidates", strs ["apps/a.ts"]), ("probabilities", Json.mkObj [("f1", .num ⟨1, 1⟩)]), ("row", row),
        ("texts", Json.mkObj [("apps/a.ts", .str ("\n".intercalate ((List.range 400).map fun i => "line " ++ toString i ++ " of a.ts here")))])]),
   ("hybrid: the line ranges T-sonnet read, labelled", "oracle.retrieveHybrid",
      Json.mkObj [("row", row), ("ranges", .arr #[rng "apps/a.ts" 2 4, rng "scripts/b.mjs" 11 30, rng "apps/z.ts" 1 2]),
        ("texts", Json.mkObj [("apps/a.ts", .str lines), ("scripts/b.mjs", .str lines)])]),
   ("hybrid: no reads, the row stays", "oracle.retrieveHybrid", Json.mkObj [("row", row), ("ranges", .arr #[])]),
   ("plan: one run under the caps", "oracle.retrievePlan",
      Json.mkObj [("logged", toJson (49 : Nat)), ("items", .arr #[item "a" 2 1000, item "b" 1 1000, item "c" 0 0])]),
   ("plan: 60 sends close a run", "oracle.retrievePlan",
      Json.mkObj [("logged", toJson (0 : Nat)), ("items", .arr ((List.range 31).map fun i => item s!"r{i}" 2 1000).toArray)]),
   ("plan: the day's cap defers the rest", "oracle.retrievePlan",
      Json.mkObj [("logged", toJson (197 : Nat)), ("items", .arr #[item "a" 2 1000, item "b" 2 1000, item "c" 1 10])]),
   ("plan: the token cap closes a run", "oracle.retrievePlan",
      Json.mkObj [("logged", toJson (0 : Nat)), ("items", .arr #[item "a" 1 300000, item "b" 1 200000])]),
   ("adopt: four traced gains, X not worse", "oracle.retrieveAdopt", adoptReq gains4 [] [] ["g1", "g2", "g3", "g4"]),
   ("adopt: net 3 against C", "oracle.retrieveAdopt",
      adoptReq (gains4 ++ [pr "l1" true false]) [] [] ["g1", "g2", "g3", "g4"]),
   ("adopt: worse than X", "oracle.retrieveAdopt", adoptReq gains4 [pr "x1" true false] [] ["g1", "g2", "g3", "g4"]),
   ("adopt: a gain on a dropped row and an untraced gain", "oracle.retrieveAdopt",
      adoptReq gains4 [] ["g1"] ["g1", "g2", "g3"]),
   ("pickPos: one-candidate and empty rows add nothing; shares over rows with 2 or more candidates", "oracle.retrievePickPos",
      Json.mkObj [("rows", .arr #[pk ["a"] (some "a"), pk ["a"] (some "a"), pk [] none, pk ["a", "b"] (some "a"),
        pk ["a", "b"] (some "b"), pk ["a", "b", "c"] (some "c"), pk ["a", "b"] none])]),
   ("pickPos: only one-candidate rows, every share 0", "oracle.retrievePickPos",
      Json.mkObj [("rows", .arr #[pk ["a"] (some "a"), pk ["b"] none])]),
   ("pickPos: the D1 J-pick counts (26 single, 2 empty, f1 4 f2 5 f3 1 over 10)", "oracle.retrievePickPos",
      Json.mkObj [("rows", .arr ((List.replicate 26 (pk ["a"] (some "a"))) ++ (List.replicate 2 (pk [] none)) ++
        (List.replicate 4 (pk ["a", "b"] (some "a"))) ++ (List.replicate 5 (pk ["a", "b"] (some "b"))) ++
        [pk ["a", "b", "c"] (some "c")]).toArray)]),
   ("answer: forced, no read yet", "oracle.retrieveAnswer",
      Json.mkObj [("forced", true), ("log", .arr #[ev "Grep" "allow", ev "Read" "deny"])]),
   ("answer: forced, after one allowed read", "oracle.retrieveAnswer",
      Json.mkObj [("forced", true), ("log", .arr #[ev "Glob" "allow", ev "Read" "allow"])]),
   ("answer: not forced", "oracle.retrieveAnswer", Json.mkObj [("forced", false), ("log", .arr #[])])]

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
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "oracle" / "retrieve.jsonl"
  let n := cases.length
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"oracle retrieve golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/RetrieveGolden.lean)"
      return 1
    IO.println s!"oracle retrieve golden: {n} lines, up to date"
    return 0
  if let some d := p.parent then IO.FS.createDirAll d
  IO.FS.writeFile p text
  IO.println s!"oracle retrieve golden: {n} lines written"
  return 0
