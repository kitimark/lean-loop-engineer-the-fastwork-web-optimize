import Fw.Ops.Golden

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/lakegc.jsonl`: one line per case,
`{"name", "request", "response"}` for `ops.lakeGc` (Fw.Ops.LakeGc), the reply being what `fwcore` answers (without the
`id`). Consumer: `scripts/lake-gc.mjs`; `node --test scripts/lake-gc.test.mjs` replays every line through the built
`fwcore`. Run from `lean/`: `lake env lean --run scripts/LakeGcGolden.lean [--check]`. -/

open Lean Fw.Wire.Ops.Golden

/-- The artifacts root of the cases. -/
def root : String := "/h/.elan/toolchains/t/lake/cache/artifacts"

/-- A fact as JSON. -/
def fact (name : String) (file : Bool) (links mtime size : Nat) : Json :=
  Json.mkObj [("name", .str name), ("file", .bool file), ("links", toJson links), ("mtime", toJson mtime),
    ("size", toJson size)]

/-- A request: root, now, optional floor and budget, facts. -/
def req (r : String) (now : Nat) (extra : List (String × Json)) (fs : List Json) : Json :=
  Json.mkObj ([("root", .str r), ("now", toJson now)] ++ extra ++ [("files", .arr fs.toArray)])

/-- The cases, `(name, request)`. -/
def gcCases : List (String × Json) := [
  ("an old unlinked file is listed; linked and young files are kept",
    req root 10000 [] [fact "a.o" true 1 2800 50, fact "b.olean" true 2 0 70, fact "c.c" true 1 2801 10]),
  ("a name given twice, once linked, is kept",
    req root 10000 [] [fact "x" true 1 0 5, fact "x" true 3 0 5]),
  ("not a regular file, or a disallowed name: kept",
    req root 10000 [] [fact "d" false 1 0 5, fact ".hidden" true 1 0 5, fact "a b" true 1 0 5]),
  ("a root outside the allowlist lists nothing but still counts the bytes",
    req "/tmp/x" 10000 [("budget", toJson 9)] [fact "a.o" true 1 0 10]),
  ("a root with .. lists nothing", req "/h/../artifacts" 10000 [] [fact "a.o" true 1 0 10]),
  ("ageFloor 0 lists a file modified now", req root 500 [("ageFloor", toJson 0)] [fact "a.o" true 1 500 10]),
  ("alert: cache bytes above the budget", req root 10000 [("budget", toJson 100)] [fact "a" true 2 0 60, fact "b" true 2 0 41]),
  ("no alert at exactly the budget", req root 10000 [("budget", toJson 100)] [fact "a" true 2 0 60, fact "b" true 2 0 40]),
  ("no files: empty list, no alert", req root 10000 [] []),
  ("files missing: refused", Json.mkObj [("root", .str root), ("now", toJson 1)]),
  ("a fact without links: refused", req root 1 [] [Json.mkObj [("name", .str "a"), ("file", .bool true),
    ("mtime", toJson 0), ("size", toJson 1)]])]

/-- The golden text. -/
def text : String :=
  String.join (gcCases.map fun (name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp "ops.lakeGc" r), ("response", respond "ops.lakeGc" r)]).compress
      ++ "\n")

/-- Write the golden file, or with `--check` exit 1 when it differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "lakegc.jsonl"
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"lakegc golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/LakeGcGolden.lean)"
      return 1
    IO.println s!"lakegc golden: {gcCases.length} cases, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"lakegc golden: {gcCases.length} cases written"
  return 0
