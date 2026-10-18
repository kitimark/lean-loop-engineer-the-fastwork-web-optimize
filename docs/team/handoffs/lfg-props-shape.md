# lfg-props-shape handoff

State: round 5 (mechanical fixes of the round-4 review) on branch worktree-wf_e0a87a2e-ff6-1, merged
worktree-wf_b82902f8-8e2-1 (9fcdd8c) and main. check.sh green; the `props lint` stage (~20-35 s) now runs the lint
once over every `lean_lib` (Fw, MathView, FwTest: 170 modules) plus the test cases and diffs the findings.

Round 5 (review blocker + major + 2 minors):
- `closure` follows `nextOf`: definition values; inductive type + constructors; the types of constructors, theorems,
  opaques, axioms. The signature types (`Sig.Dom s`, `Sig.Cod s`) count as vocabulary (else every property hits
  `LandDrySig.Out`).
- New rule `convention-wrapped`: a non-exempt definition whose value reaches `Convention` (least fixpoint,
  `wrappersOf`), and any type mentioning `Convention`/a wrapper except as the head of a theorem's result type or of
  `¬ …` there (`misplaced`, pure, `#guard`s). `Silly_not_convention : ¬ Convention …` stays legal.
- Scope: `libNames` parses `lakefile.toml`'s `[[lean_lib]]` names; `libModules` lints `L` and every module under
  `L/` whose `.olean` exists (unbuilt ones printed as a note). `lean_exe` roots are not scanned (each defines `main`).
- Test cases: `lean/scripts/props-lint-cases/Adv.lean` (the round-4 probe) and `Adv.expected.txt` (5 findings:
  Wrapped, wrapped, IsImpl_convention, IsImplS_convention, PinViaThm_convention).
- Minor: `emptyIncident` docstring marks the `fresh` conjunct INFERRED (stage order, LandDry.lean:78).
- Merge: `checkShReads` = main's list + `scripts/fwcore-build.sh` + the ledger (Lean, golden, land.ts).

Open items / stated limits (unchanged): inline restatement of impl and `TaskSensitive`-style properties are review
items; no checker spawned (no agent tool in this run), docstrings self-reviewed.
Read first: PropsLint.lean module doc, lean-first.md step 3, Incidents.lean, then Props.lean module doc.
