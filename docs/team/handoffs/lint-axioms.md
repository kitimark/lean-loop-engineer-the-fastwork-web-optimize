# Handoff: lint-axioms

State: branch worktree-wf_f4119fe3-e43-2, merged with main df97be28. Land and `lean/scripts/check.sh` now run the
axiom check in place of the mathview export.

What changed
- `lean/scripts/axiom-check.sh` builds the probe `scripts/axiom-check-cases/AxProbe.lean` into a tmp dir. It then
  pipes `import AxProbe`, `import Fw`, an import of every `Fw/**/*.lean`, `scripts/AxiomCheck.lean` and
  `run_cmd AxiomCheck.check` into `lake env lean --stdin`. A header import is required: imported modules carry their
  exported axiom tables only then (Lean/Util/CollectAxioms.lean:113-140 @ v4.35.0). A runtime
  `importModules (loadExts := false)` leaves those tables empty and makes `collectAxioms` walk everything.
- `AxiomCheck.findings` plus theorems `sorry_refuses`, `nonstandard_refuses`, `standard_passes`, `findings_nil_iff`
  and `#guard`s. `check` fails on: any `Fw` finding, any module under `Fw/` that is not imported, or probe findings
  that differ from `probeWant`. The probe therefore checks the refusal path on every run.
- `Fw/Console/LandDry.lean`: `Lint.mathview` is now `Lint.axioms`. Theorems `axioms_mem_plan` and
  `no_axioms_without_lean`. `lintStages = ["lake build", "axiom check"]`. The land-dry golden was regenerated.
- TS: `land-verdict.ts` (LINT_ARGV, lintPlan, LINT_STAGES) and `land.ts` (`dryLintArgv` probes `axiom-check.sh`),
  plus their tests. check.sh has a job "axiom check". In lean.yml only the comment changed.

Measured (local, load 150-210)
- axiom-check.sh: 2.8 to 4.5 s wall, about 1.05 s user.
- mathview-cached.sh --build: 30.6 s wall and 8.2 s user (8 of 245 modules missed); 25.9 s and 6.35 s (all hits).

Open
- The mathview-differential job in lean.yml is kept. It guards the module cache that the on-demand
  docs/plan/tools/build-math-view.mjs uses, and LandSpeed.lean:896-900, LakeJobsGen.lean:22 and ConeMiss name it.
  Drop it together with lean-latex-removal.
- docs/plan/math-view.html (on-demand artifact) still names the old theorems until its next regeneration.
- The mathview exe, mathview-cached.sh and the MathView fields stay as they are (accepted limit).

Read first: lean/scripts/AxiomCheck.lean, lean/scripts/axiom-check.sh, LandDry.lean (`Lint`).
