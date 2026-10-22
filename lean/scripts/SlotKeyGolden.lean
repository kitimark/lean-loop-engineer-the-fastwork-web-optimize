import Fw.Obs.Timing
import Fw.Console.LandDry

namespace Fw.Wire.Obs.DryStep
open Lean Fw.Console.LandDry

def cases : List (String × List String × Bool × Bool × Bool × Bool) :=
  [("site change only", ["apps/site/src/main.tsx"], true, true, true, false),
   ("lean change", ["lean/Fw/X.lean"], true, true, true, false),
   ("lean change, no axiom-check script", ["lean/Fw/X.lean"], true, false, true, false),
   ("no lean change, fwcore build", ["apps/runner/src/land.ts"], true, true, true, true),
   ("lean change and fwcore build", ["lean/Fw/X.lean", "scripts/fwcore-build.sh"], true, true, true, true),
   ("lean-like prefix is not lean", ["leanx/a"], true, true, true, false),
   ("nothing changed", [], true, true, true, false),
   ("footprint input only", ["apps/site/src/App.tsx"], true, true, true, false)]

def caseJson (n : String) (ch : List String) (c a f b : Bool) : Json :=
  Json.mkObj [("name", n), ("request", Json.mkObj [("changed", toJson ch), ("hasCiPaths", c), ("hasAxioms", a), ("hasFootprint", f),
    ("fwcoreBuild", b)]), ("response", Json.mkObj [("step", dryTotalStep (lintPlan ch c a f) b)])]

def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, ch, c, a, f, b) => (caseJson n ch c a f b).compress ++ "\n")

#guard cases.map (fun (_, ch, c, a, f, b) => dryTotalStep (lintPlan ch c a f) b) ==
  ["dry total", "dry total lake", "dry total", "dry total lake", "dry total lake", "dry total", "dry total", "dry total"]

def goldenPath : System.FilePath := "../packages/contracts/golden/obs/dry-step.jsonl"

def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Wire.Obs.DryStep

def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if (← Fw.Wire.Obs.SlotKey.checkGolden) && (← Fw.Wire.Obs.DryStep.checkGolden) then
      IO.println "slot-key golden: up to date"; return 0
    else
      IO.eprintln "slot-key golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Wire.Obs.SlotKey.writeGolden
    Fw.Wire.Obs.DryStep.writeGolden
    IO.println "slot-key golden: written"; return 0
