import Fw.Ops.Usage

/-! # Mutant killers for `Fw.Ops.Usage` (task m0-mutants)

The rejected "last line wins" rule was only checked for order dependence; its exact result is pinned
here, as is the documented example `exLines`. -/

namespace FwTest.Mutants.Usage
open Fw.Ops.Usage

-- lastWins keeps one record per id: the last one, the survivors in line order
#guard lastWins exLines == [("m1", { output := 5 })]
#guard lastWins exLines.reverse == [("m1", { output := 3 })]
#guard lastWins [("a", { input := 1 }), ("b", { input := 2 }), ("a", { input := 3 })] ==
  [("b", { input := 2 }), ("a", { input := 3 })]
-- the documented example lines l₀
#guard exLines == [("m1", { output := 3 }), ("m1", { output := 5 })]

end FwTest.Mutants.Usage
