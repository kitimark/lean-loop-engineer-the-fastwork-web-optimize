import Fw.Ops.PathCheck

/-! # Mutant killers for `Fw.Ops.PathCheck` (task m0-mutants)

`parseScope` was only checked through `inScope`, where a `!glob` that leaks into the includes
matches nothing; its exact split is pinned here. -/

namespace FwTest.Mutants.PathCheck
open Fw.Ops.PathCheck

-- parseScope: includes keep their order and lose nothing; excludes lose exactly the leading `!`
#guard parseScope ["lean/**", "!lean/.lake/**", "docs/*.md"] ==
  ⟨[["lean", "**"], ["docs", "*.md"]], [["lean", ".lake", "**"]]⟩
#guard parseScope [] == ⟨[], []⟩
#guard parseScope ["!a"] == ⟨[], [["a"]]⟩
#guard parseScope ["a"] == ⟨[["a"]], []⟩

end FwTest.Mutants.PathCheck
