# Handoff: latex-mathview-b2

State: branch worktree-wf_76a43ad0-1d2-1 (step B2 of lean-latex-removal). Commits are on this branch only.

What changed
- Retired: the mathview-differential job in lean.yml (the whole job, its negative probe included),
  `lean/scripts/mathview-cached.sh`, `docs/plan/tools/build-math-view.mjs`, the job's LakeJobsGen row, LandSpeed
  section (b) "cone skip" and its premise rows `land.coneLocal` and `land.lintOrder` (7 premises, 34 golden cases).
  check-fast.sh runs `scripts/axiom-check.sh`.
- MathView export: the fields english, math, mathHash and binders are gone, and so are the quantifier lint,
  ShadowLint, WhereLint, the module-cache keys, `--store`/`--stats` and `--dependents`. New: `MathView.Filter`
  (`keeps`, `ofArgs`, `missing`; theorems `keeps_iff`, `keeps_default`, `keeps_listed`, `keeps_unlisted`,
  `keeps_other_module`, `mem_missing`; plus #guards). CLI: `lake exe mathview --decl <name>... --module <M> [--lint]
  [--out f]`. An unknown `--decl` exits 1. `--lint` checks only sorry, the axioms and export failures.
- Signoff (Fw.Ops.LeanFirst): `docHash` was dropped from Signoff and PropFact, so `matches` is
  (decl, stmtHash, role). The fault `staleDoc` became `staleStmt`. Regenerated: wire, Golden.lean,
  `golden/ops/lean-first.jsonl` and `golden/console/land-speed.jsonl`.
- `scripts/math-pending.mjs` (a TS stand-in) reads stmtHash rows from both `-math-review-` and `-math-artifact-`
  notes. Artifact notes rank after every review round. It exports through `lake exe mathview --out`.
- `docs/team/tools/math-artifact.md` is the procedure. The math-reviewer and page-writer files point to it.
  `docs/plan/math-view.html` is frozen and carries a header line that says so.

Verified: lake build (Fw, mathview, FwTest via the commit hook), runner land-inputs/land-prelock/incidents,
ci-paths tests and `--check`, test-math-pending, check.sh at the final commit.

Open
- Fw.Spec.ConeMiss is kept. Incident inc-ci-hardcoded-expect cites the file, and the incident lint needs it to exist.
- Item (6) said to keep the lean.yml:195 probe, but it sat inside the retired job, so it went with the job.
- PLAN.md, loop-plan.html and the docs `$$` strip belong to other steps (C/D, latex-generators).

Read first: lean/MathView.lean (`Filter`), lean/MathViewMain.lean (`main`), docs/team/tools/math-artifact.md.
