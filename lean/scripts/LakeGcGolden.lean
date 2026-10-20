import Fw.Ops.Golden

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/lakegc.jsonl`: one line per case,
`{"name", "request", "response"}` for `ops.lakeGc` (Fw.Ops.LakeGc), the reply being what `fwcore` answers (without the
`id`). Consumer: `scripts/lake-gc.mjs`; `node --test scripts/lake-gc.test.mjs` replays every line through the built
`fwcore`. Run from `lean/`: `lake env lean --run scripts/LakeGcGolden.lean [--check]`. -/

open Lean Fw.Wire.Ops.Golden

/-- The artifacts root of the cases. -/
def root : String := "/h/.elan/toolchains/t/lake/cache/artifacts"

/-- A fact as JSON (ctime equal to mtime). -/
def fact (name : String) (file : Bool) (links mtime size : Nat) : Json :=
  Json.mkObj [("name", .str name), ("file", .bool file), ("links", toJson links), ("mtime", toJson mtime),
    ("ctime", toJson mtime), ("size", toJson size)]

/-- A checkout as JSON. -/
def checkout (path : String) (refs : List String) : Json :=
  Json.mkObj [("path", .str path), ("refs", .arr (refs.toArray.map .str))]

/-- A process as JSON. -/
def proc (pid start : Nat) (exe args : String) (cwd : Option String) : Json :=
  Json.mkObj [("pid", toJson pid), ("start", toJson start), ("exe", .str exe), ("args", .str args),
    ("cwd", match cwd with | some s => .str s | none => .null)]

/-- The identity facts with nothing gathered in them: no checkout, no process, an empty outputs map. -/
def idle : List (String × Json) := [("checkouts", .arr #[]), ("procs", .arr #[]), ("outputs", .arr #[])]

/-- A request: root, now, extra fields, facts. -/
def req (r : String) (now : Nat) (extra : List (String × Json)) (fs : List Json) : Json :=
  Json.mkObj ([("root", .str r), ("now", toJson now)] ++ extra ++ [("files", .arr fs.toArray)])

/-- The `lake` executable of the cases. -/
def lake : String := "/h/.elan/toolchains/t/bin/lake"

/-- The cases, `(name, request)`. -/
def gcCases : List (String × Json) := [
  ("fallback noCheckoutList: an old unlinked file is listed; linked and young files are kept",
    req root 10000 [] [fact "a.o" true 1 2800 50, fact "b.olean" true 2 0 70, fact "c.c" true 1 2801 10]),
  ("a name given twice, once linked, is kept",
    req root 10000 idle [fact "x" true 1 0 5, fact "x" true 3 0 5]),
  ("not a regular file, or a disallowed name: kept",
    req root 10000 idle [fact "d" false 1 0 5, fact ".hidden" true 1 0 5, fact "a b" true 1 0 5]),
  ("a root outside the allowlist lists nothing but still counts the bytes",
    req "/tmp/x" 10000 ([("budget", toJson 9)] ++ idle) [fact "a.o" true 1 0 10]),
  ("a root with .. lists nothing", req "/h/../artifacts" 10000 idle [fact "a.o" true 1 0 10]),
  ("identity, no writer: a file modified now is listed", req root 500 idle [fact "a.o" true 1 500 10]),
  ("identity: a trace output or a hash file names the entry, so it is kept",
    req root 10000 [("checkouts", .arr #[checkout "/r" ["a.olean"], checkout "/r/.claude/w" ["b1"]]),
      ("procs", .arr #[]), ("outputs", .arr #[])]
      [fact "a.olean" true 1 0 5, fact "b1.c" true 1 0 7, fact "b1" true 1 0 9, fact "z.o" true 1 0 11]),
  ("identity, a live lake build: entries changed since it started or named by the outputs map are kept",
    req root 10000 [("checkouts", .arr #[checkout "/r" []]),
      ("procs", .arr #[proc 7 9000 lake s!"{lake} build" (some "/r/lean"), proc 8 1 lake s!"{lake} serve --" none,
        proc 9 1 "/h/bin/lean" "/h/bin/lean --server" none]),
      ("outputs", .arr #[.str "m.olean"])]
      [fact "new.o" true 1 9000 5, fact "m.olean" true 1 0 7, fact "old.o" true 1 8999 9]),
  ("fallback noProcessTable: the age floor decides",
    req root 10000 [("checkouts", .arr #[checkout "/r" ["k.o"]])]
      [fact "a.o" true 1 2800 5, fact "y.o" true 1 2801 5, fact "k.o" true 1 0 5]),
  ("fallback noOutputsMap: a writer is live and the map was not read",
    req root 10000 [("checkouts", .arr #[]), ("procs", .arr #[proc 7 9000 lake s!"{lake} build" none])]
      [fact "a.o" true 1 2800 5, fact "y.o" true 1 2801 5]),
  ("alert: cache bytes above the budget",
    req root 10000 ([("budget", toJson 100)] ++ idle) [fact "a" true 2 0 60, fact "b" true 2 0 41]),
  ("no alert at exactly the budget",
    req root 10000 ([("budget", toJson 100)] ++ idle) [fact "a" true 2 0 60, fact "b" true 2 0 40]),
  ("no files: empty list, no alert", req root 10000 idle []),
  ("files missing: refused", Json.mkObj [("root", .str root), ("now", toJson 1)]),
  ("a fact without ctime: refused", req root 1 idle [Json.mkObj [("name", .str "a"), ("file", .bool true),
    ("links", toJson 1), ("mtime", toJson 0), ("size", toJson 1)]]),
  ("a process without a start: refused", req root 1 [("checkouts", .arr #[]), ("procs", .arr #[Json.mkObj
    [("pid", toJson 1), ("exe", .str lake), ("args", .str "lake build")]])] [])]

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
