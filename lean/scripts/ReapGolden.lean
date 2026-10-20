import Fw.Ops.Golden

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/lspreap.jsonl`: `ops.lspReap` (Fw.Ops.Reap) cases.
Consumer: `apps/runner/src/reap.ts`, replayed by `apps/runner/test/reap.test.ts`. Run from `lean/`:
`lake env lean --run scripts/ReapGolden.lean [--check]`. -/

open Lean Fw.Wire.Ops.Golden

/-- A row as JSON. -/
def row (pid ppid pgid start : Nat) (cwd : Option Nat) (kind : String) : Json :=
  Json.mkObj [("pid", toJson pid), ("ppid", toJson ppid), ("pgid", toJson pgid), ("start", toJson start),
    ("cwd", match cwd with | some n => toJson n | none => .null), ("kind", .str kind)]

/-- A request. -/
def req (rows : List Json) (live : List Nat) (mcp : Option Nat) : Json :=
  Json.mkObj [("rows", .arr rows.toArray), ("live", toJson live), ("mcps", match mcp with | some n => toJson [n] | none => toJson ([] : List Nat))]

/-- The cases, `(name, request)`. -/
def reapCases : List (String × Json) := [
  ("a lake serve under the mcp whose cwd inode is in no live checkout is selected as a group leader",
    req [row 500 400 500 9 (some 11) "lspServe"] [1, 2] (some 400)),
  ("a lake serve in a live checkout (a reused path has a new inode, the old one is dead) is kept",
    req [row 500 400 500 9 (some 1) "lspServe", row 501 400 501 9 (some 11) "lspServe"] [1, 2] (some 400)),
  ("a row whose pgid differs from its pid is selected without a group signal",
    req [row 500 400 77 9 (some 11) "lspServe"] [1] (some 400)),
  ("a lake serve of another parent is kept", req [row 500 123 500 9 (some 11) "lspServe"] [1] (some 400)),
  ("no mcp pid: no lake serve is selected", req [row 500 400 500 9 (some 11) "lspServe"] [1] none),
  ("an orphan console of a removed worktree is selected; a console with a live parent is kept",
    req [row 600 1 600 9 (some 12) "console", row 601 55 601 9 (some 12) "console"] [1] none),
  ("the main console (cwd inode live) is kept", req [row 600 1 600 9 (some 1) "console"] [1] none),
  ("an unreadable cwd is kept", req [row 600 1 600 9 none "console", row 500 400 500 9 none "lspServe"] [1] (some 400)),
  ("an unnamed kind is kept", req [row 700 1 700 9 (some 12) "other", row 701 1 701 9 (some 12) "chrome"] [1] (some 1)),
  ("pid 1 is never selected", req [row 1 1 1 9 (some 12) "console"] [] none),
  ("no rows", req [] [] none)]

/-- The golden text. -/
def text : String :=
  String.join (reapCases.map fun (name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp "ops.lspReap" r), ("response", respond "ops.lspReap" r)]).compress
      ++ "\n")

/-- Write the golden file, or with `--check` exit 1 when it differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "lspreap.jsonl"
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"lspreap golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/ReapGolden.lean)"
      return 1
    IO.println s!"lspreap golden: {reapCases.length} cases, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"lspreap golden: {reapCases.length} cases written"
  return 0
