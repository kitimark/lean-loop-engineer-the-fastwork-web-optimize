import Fw.Ops.Golden

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/checkmap.jsonl`: one line per case,
`{"name", "request", "response"}` for `ops.checkMap` and `ops.checkVerdict` (Fw.Ops.CheckMap), the reply being what
`fwcore` answers (without the `id`). Consumer: `scripts/checkmap.mjs` (run by `scripts/hooks/pre-commit` and
`scripts/check.sh`); `node scripts/test-checkmap.mjs` replays every line through the built `fwcore`. Run from `lean/`:
`lake env lean --run scripts/CheckMapGolden.lean [--check]`. -/

open Lean Fw.Wire.Ops.Golden

/-- A `ops.checkMap` request for these paths. -/
def paths (ps : List String) : Json := Json.mkObj [("paths", .arr (ps.toArray.map .str))]

/-- The cases, `(op, name, request)`. -/
def checkCases : List (String × String × Json) := [
  ("ops.checkMap", "the c-late-check defect: a tracked .mjs gets node --check", paths ["apps/site/scripts/shell-measure.mjs"]),
  ("ops.checkMap", "one path per code kind, in plan order; exempt kinds get no command",
    paths ["apps/runner/src/fw.ts", "a.mjs", "b.js", "c.cjs", "x.json", "y.jsonl", ".github/workflows/lean.yml",
      "scripts/wt-prep.sh", "scripts/hooks/pre-commit", "tool.py", "packages/gate-breakpoints/a.swift", "app.webmanifest",
      "docs/plan/PLAN.md", "apps/site/src/a.css", "img.png", "LICENSE"]),
  ("ops.checkMap", "Lean: modules and the lakefile build once (lake build); a script elaborates alone",
    paths ["lean/Fw/Ops/CheckMap.lean", "lean/lakefile.toml", "lean/scripts/OpsGolden.lean", "lean/Main.lean"]),
  ("ops.checkMap", "tsx: one tsc run per package", paths ["apps/site/src/a.tsx", "apps/console-web/src/b.tsx", "apps/site/src/c.tsx"]),
  ("ops.checkMap", "snapshot and research sketches are exempt, research JSON is not",
    paths ["snapshot/site/__vendor/x/gtm.js.__q_141790bd5c", "snapshot/site/a.js", "research/kickoff/05-lean-sketch/Fw.lean",
      "research/kickoff/05-lean-sketch/lean-toolchain", "research/kickoff/a.json"]),
  ("ops.checkMap", "unmapped: an unknown extension and an unknown extensionless name", paths ["x.unknownext", "Makefile", "a.mjs"]),
  ("ops.checkMap", "the work graph gets the graph schema check, the findings ledger the preset check, other JSON a parse",
    paths ["docs/team/work-graph.json", "research/findings/ledger.json", "docs/team/incidents/ledger.json"]),
  ("ops.checkMap", "workflow bodies get the body parse, not node --check; other .claude files keep their kind",
    paths [".claude/workflows/build-review.js", ".claude/workflows/fable-refusals.js", "a.mjs", ".claude/agents/checker.md"]),
  ("ops.checkMap", "each other input of the preset generator also runs the preset check, once; a look-alike does not",
    paths ["packages/contracts/golden/preset/v2-proved.trajectory.jsonl", "apps/site/src/registry/presets/v2-proved.json",
      "apps/site/src/parts/hero/part.json", "lean/Fw/Preset/Gen.lean", "lean/Fw/Preset/V2Proved.lean", "lean/Fw/Gate/Trajectory.lean",
      "apps/site/src/registry/presets/original.json"]),
  ("ops.checkMap", "a staged deletion of a generator input runs the preset check; a deletion of anything else adds nothing",
    Json.mkObj [("paths", .arr #[.str "a.mjs"]), ("deleted", .arr #[.str "apps/site/src/parts/hero/part.json", .str "packages/contracts/golden/preset/v2-proved.json", .str "old.mjs"])]),
  ("ops.checkMap", "deletions that are not generator inputs: no command",
    Json.mkObj [("paths", .arr #[]), ("deleted", .arr #[.str "old.mjs", .str "apps/site/src/parts/hero/index.tsx"])]),
  ("ops.checkMap", "the findings ledger also gets the ledger-notes check (task ledger-note-check); the incident and mistake ledgers only a parse",
    paths ["research/findings/ledger.json", "research/mistakes/ledger.json", "docs/team/incidents/ledger.json"]),
  ("ops.checkMap", "the findings ledger among other files: the ledger-notes check is planned once, after the preset check",
    paths ["a.mjs", "docs/x.md", "research/findings/ledger.json", "x.json"]),
  ("ops.checkMap", "a staged deletion of the findings ledger runs the preset check but not the ledger notes",
    Json.mkObj [("paths", .arr #[]), ("deleted", .arr #[.str "research/findings/ledger.json"])]),
  ("ops.checkMap", "no paths: no commands", paths []),
  ("ops.checkMap", "paths missing: refused", Json.mkObj []),
  ("ops.checkVerdict", "all passed: ok", lit "{\"codes\":[0,0,0]}"),
  ("ops.checkVerdict", "a failed command fails", lit "{\"codes\":[0,1,0]}"),
  ("ops.checkVerdict", "a missing tool (127) is forgiven by default", lit "{\"codes\":[0,127]}"),
  ("ops.checkVerdict", "a missing tool fails in strict mode", lit "{\"codes\":[0,127],\"strict\":true}"),
  ("ops.checkVerdict", "no commands: ok", lit "{\"codes\":[]}"),
  ("ops.checkVerdict", "an unmapped path fails the run even when every command passed", lit "{\"codes\":[0],\"unmapped\":2}"),
  ("ops.checkVerdict", "codes missing: refused", lit "{}")]

/-- The golden text. -/
def text : String :=
  String.join (checkCases.map fun (op, name, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- Write the golden file, or with `--check` exit 1 when it differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "checkmap.jsonl"
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"checkmap golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/CheckMapGolden.lean)"
      return 1
    IO.println s!"checkmap golden: {checkCases.length} cases, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"checkmap golden: {checkCases.length} cases written"
  return 0
