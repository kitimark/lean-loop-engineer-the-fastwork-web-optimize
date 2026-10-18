# mathview-ci-fix (lean-prover)

State: branch ci/mathview-ci-fix (worktree commit, see git log). Fixes the `mathview-differential` job of
.github/workflows/lean.yml, red on every branch since task mathview-module-cache (8bcc503).

Cause (MEASURED, run 39088367481): not the diff. Step "mutation 1" asserted `misses 2` (LandSpeed + Fw, "a leaf
imported only by Fw"); Fw.Ci.Trigger and Fw.Console.LandPool began to import Fw.Console.LandSpeed, so the cache
correctly recomputed 4 modules and `grep -qx 'misses 2'` exited 1. On main today the cone has 16 dependents.

Fix: the expected miss set comes from Lean, not a constant.
- lean/Fw/Spec/ConeMiss.lean: `Reach`, `topoFrom`, `dependents` (one pass over a topological order) and
  `mem_dependents`: y in dependents iff y in order and x in cone(y). Self-contained (linked into mathview).
- lean/Fw/Console/LandSpeed.lean: `inCone_iff_reach` links `InCone` to `Reach`.
- lean/MathViewMain.lean: `mathview --dependents <Mod>` (`dependentsOf`; throws if the module order is not
  topological or the module is unknown). Not in `toolSources` (does not affect lint/export).
- lean.yml mutations 1 and 3: `diff` sorted `--dependents` output against the `miss` lines of cached.stats.

Open: dry land says VERDICT scope; the lead must add lean/Fw/Spec/ConeMiss.lean, lean/Fw/Console/LandSpeed.lean, lean/MathViewMain.lean to the task scope. CI run 39102129898 green (mathview-differential success). Read first: ConeMiss.lean module doc, then the mutation steps in lean.yml.
