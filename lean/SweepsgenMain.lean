import Fw.Gate.SweepsGen
import Fw.Gate.ScopeGen
import Fw.Site.GenRoute

/-- `lake exe sweepsgen [--sweeps | --sweeps-golden] [--check <file>]` prints or checks the gate's `sweeps.gen.json`
(no flag or `--sweeps`) or `golden/gate/sweeps.jsonl` (`--sweeps-golden`) through `Fw.Gate.SweepsGen.run`;
`lake exe sweepsgen --scope [--check <file>]` prints or checks the gate's `scope.gen.json` (`Fw.Gate.ScopeGen.run`;
the compiled binary replaces the interpreted `lean --run` driver of `packages/gate-breakpoints/scripts/scopegen.mjs`).
Split out of `breakgen` (task `site-build-cache`) so the site build does not build the gate's import cone; the
routing is `Fw.Site.GenRoute.sweepsgenRoute`, and `split_agrees` proves each old `breakgen` gate flag reaches the
same generator with the same arguments. -/
def main (args : List String) : IO UInt32 :=
  match Fw.Site.GenRoute.sweepsgenRoute args with
  | .scope => Fw.Gate.ScopeGen.run (Fw.Site.GenRoute.argsFor .scope args)
  | g => Fw.Gate.SweepsGen.run (Fw.Site.GenRoute.argsFor g args)
