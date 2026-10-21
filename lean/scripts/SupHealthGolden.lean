import Fw.Obs.Health
import Lean.Data.Json

/-!
# Golden vectors of the resource baseline

`packages/contracts/golden/obs/sup-health.jsonl`: one line per case, `{"name", "request", "response"}`. The kind classifier and
the sample verdict (`Fw.Obs.Health.Res`) are the Lean side; `apps/runner/src/watch-collect.ts` is checked against these lines.
Run from `lean/`: `lake env lean --run scripts/SupHealthGolden.lean [--check]`.
-/
open Lean
open Fw.Obs.Health.Res

def kindJson (k : ProcKind) : Json := .str k.name

def obsJson (o : Obs) : Json :=
  Json.mkObj [("procs", .arr (o.procs.map kindJson).toArray), ("loadCenti", o.loadCenti), ("swapUsedMB", o.swapUsedMB),
    ("swapTotalMB", o.swapTotalMB), ("compressorMB", o.compressorMB), ("ramMB", o.ramMB), ("freePct", o.freePct)]

def paramsJson (p : Params) : Json :=
  Json.mkObj [("swapPct", p.swapPct), ("cmprsPct", p.cmprsPct), ("freePct", p.freePct), ("quietCenti", p.quietCenti)]

def verdictName : Verdict → String
  | .quiet => "quiet" | .busy => "busy" | .pressured => "pressured"

def line (name : String) (req resp : Json) : String :=
  (Json.mkObj [("name", .str name), ("request", req), ("response", resp)]).compress ++ "\n"

def kindsLine : String :=
  line "kinds" (Json.mkObj [("op", "sup.kinds")])
    (Json.mkObj [("kinds", .arr (ProcKind.all.map kindJson).toArray),
      ("heavy", .arr ((ProcKind.all.filter ProcKind.heavy).map kindJson).toArray)])

def classifyLine (name comm : String) : String :=
  line name (Json.mkObj [("op", "sup.classify"), ("comm", .str comm)]) (Json.mkObj [("kind", kindJson (classify comm))])

def tableLines : List String :=
  kindTable.map fun (n, _) => classifyLine s!"listed name {n}" s!"/opt/tool/bin/{n}"

def extraLines : List String := [
  classifyLine "node with a long versioned path" "/Users/x/.nvm/versions/node/v24.22.0/bin/node",
  classifyLine "a name with spaces inside an app path"
    "/Applications/Chromium.app/Contents/Frameworks/Chromium Helper (Renderer).app/Contents/MacOS/Chromium Helper (Renderer)",
  classifyLine "a retitled process keeps its first word" "node server.js",
  classifyLine "a retitled process, other first word" "npm exec thing",
  classifyLine "a directory named like a kind does not count" "/Users/x/node/not-node",
  classifyLine "an unlisted tool is other" "/usr/bin/top",
  classifyLine "a bare listed name" "lake",
  classifyLine "case matters" "/usr/bin/Node",
  classifyLine "the empty command" ""]

def verdictLine (name : String) (o : Obs) (p : Params := {}) : String :=
  line name (Json.mkObj [("op", "sup.verdict"), ("params", paramsJson p), ("obs", obsJson o)])
    (Json.mkObj [("verdict", .str (verdictName (verdict p o)))])

def verdictLines : List String := [
  verdictLine "an idle machine is quiet" {},
  verdictLine "light kinds do not make it busy" { procs := [.node, .pnpm, .fwcore, .other] },
  verdictLine "a lean process makes it busy" { procs := [.lean] },
  verdictLine "a chromium process makes it busy" { procs := [.chromium] },
  verdictLine "a simulator process makes it busy" { procs := [.simulator] },
  verdictLine "a webkit process makes it busy" { procs := [.webkit] },
  verdictLine "load 2.00 is busy" { loadCenti := 200 },
  verdictLine "load 1.99 is quiet" { loadCenti := 199 },
  verdictLine "swap at 90 percent is pressured" { swapUsedMB := 900, swapTotalMB := 1000 },
  verdictLine "swap at 89.9 percent is quiet" { swapUsedMB := 899, swapTotalMB := 1000 },
  verdictLine "no swap total never trips the swap branch" { swapUsedMB := 900 },
  verdictLine "compressor at half of RAM is pressured" { compressorMB := 50, ramMB := 100 },
  verdictLine "compressor just below half is quiet" { compressorMB := 49, ramMB := 100 },
  verdictLine "no RAM size never trips the compressor branch" { compressorMB := 50 },
  verdictLine "free memory at 15 percent is pressured" { freePct := 15 },
  verdictLine "free memory at 16 percent is quiet" { freePct := 16 },
  verdictLine "pressure wins over a heavy process" { procs := [.lean], freePct := 10 },
  verdictLine "pressure wins over load" { loadCenti := 4000, swapUsedMB := 95, swapTotalMB := 100 },
  verdictLine "a looser swap limit lets 90 percent pass" { swapUsedMB := 900, swapTotalMB := 1000 } { swapPct := 95 },
  verdictLine "a stricter load limit makes load 1.00 busy" { loadCenti := 100 } { quietCenti := 100 },
  verdictLine "a stricter free limit trips at 30 percent" { freePct := 30 } { freePct := 30 }]

def goldenText : String := String.join ([kindsLine] ++ tableLines ++ extraLines ++ verdictLines)

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "sup-health.jsonl"

def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
    if cur == goldenText then
      IO.eprintln s!"sup-health golden: {goldenPath} is up to date"
      return 0
    IO.eprintln s!"sup-health golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/SupHealthGolden.lean)"
    return 1
  IO.FS.writeFile goldenPath goldenText
  return 0
