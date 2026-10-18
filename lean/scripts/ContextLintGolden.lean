import Fw.Ops.Golden

/-! Write (or with `--check`, verify) `lean/golden/lint.context.jsonl`: one line per case, `{"name", "request",
"response"}` for `lint.context` (Fw.Lint.Context), the reply being what `fwcore` answers (without the `id`). Consumer:
`scripts/context-lint.mjs`. Run from `lean/`: `lake env lean --run scripts/ContextLintGolden.lean [--check]`. -/

open Lean Fw.Wire.Ops.Golden

/-- One file of a request. -/
def file (path : String) (bytes : Nat) (lines : List String) : Json :=
  Json.mkObj [("path", .str path), ("bytes", toJson bytes), ("lines", .arr (lines.toArray.map .str))]

/-- A request for these files. -/
def files (fs : List Json) : Json := Json.mkObj [("files", .arr fs.toArray)]

/-- `n` numbered lines. -/
def numbered (n : Nat) : List String := (List.range n).map fun k => s!"line {k}"

/-- The cases, `(name, request)`. -/
def lintCases : List (String × Json) := [
  ("handoff: 30 lines is ok, 31 is over the line budget",
    files [file "docs/team/handoffs/a.md" 300 (numbered 30), file "docs/team/handoffs/b.md" 310 (numbered 31)]),
  ("CLAUDE.md: over 5000 bytes is over budget even with slop; at 5000 a dated note is slop",
    files [file "CLAUDE.md" 5001 ["Rule (user decision 2026-10-17)."], file "CLAUDE.md" 5000 ["Rule (user decision 2026-10-17)."]]),
  ("agent: a SHA in the body is slop; the description budget is 300 bytes",
    files [file ".claude/agents/a.md" 200 ["---", "name: a", "description: short", "---", "Read src at 5b3d632."],
      file ".claude/agents/b.md" 400 ["---", "name: b", "description: " ++ "".pushn 'x' 301, "---", "Body."]]),
  ("team doc: a heading named after a task is slop; a plain heading is ok",
    files [file "docs/team/tools/land.md" 100 ["# land", "## Output (task land-dry)"],
      file "docs/team/tools/x.md" 100 ["# x", "## Output (JSON)"]]),
  ("skill: an AI tell (em dash, inflated word, filler) is slop, the first hit's line is reported",
    files [file ".claude/skills/s/SKILL.md" 100 ["---", "description: d", "---", "Plain line.", "We leverage — it."]]),
  ("handoffs and other files get no SHA or date check; other files have no budget",
    files [file "docs/team/handoffs/c.md" 50 ["state: 5b3d632 on 2026-10-17"], file "research/notes/n.md" 999999 ["delve"]]),
  ("no files: zero counts", files []),
  ("files missing: refused", Json.mkObj []),
  ("a file without lines: refused", Json.mkObj [("files", .arr #[Json.mkObj [("path", .str "CLAUDE.md"), ("bytes", toJson 1)]])])]

/-- The golden text. -/
def text : String :=
  String.join (lintCases.map fun (name, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp "lint.context" req),
      ("response", respond "lint.context" req)]).compress ++ "\n")

/-- Write the golden file, or with `--check` exit 1 when it differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := "golden" / "lint.context.jsonl"
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"context lint golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/ContextLintGolden.lean)"
      return 1
    IO.println s!"context lint golden: {lintCases.length} cases, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"context lint golden: {lintCases.length} cases written"
  return 0
