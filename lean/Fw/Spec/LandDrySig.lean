import Fw.Console.LandDry
/-!
# The signature of a `fw land --dry` implementation

Task `lfg-props-shape`. The types a dry-run implementation has, shared by the incident registry
(`Fw.Spec.Incidents`, which holds the replay of `inc-land-dry-no-verdict`) and the worked example
(`Fw.Spec.Props.LandDryDemo`, which states the properties and proves them of the real run). No implementation lives
here.
-/
namespace Fw.Spec.LandDrySig
open Fw.Console.LandDry

/-- What a dry run hands to the process: its stdout lines and its exit code. -/
structure Out where
  lines : List String
  exit : Nat

/-- The signature of a dry-run implementation: the stage outcomes and the task name in, the output out. -/
abbrev DryImpl := Outcome → String → Out

/-- Is a line a verdict line? It starts with `VERDICT ` (with the space). -/
def isVerdict (l : String) : Bool := l.startsWith "VERDICT "

/-- The number of verdict lines in a list of lines. -/
def verdictCount (ls : List String) : Nat := (ls.filter isVerdict).length

#guard isVerdict "VERDICT dry x"
#guard !isVerdict "VERDICTdry"
#guard verdictCount ["dry: exception ok", "VERDICT dry x"] == 1
#guard verdictCount [] == 0

end Fw.Spec.LandDrySig
