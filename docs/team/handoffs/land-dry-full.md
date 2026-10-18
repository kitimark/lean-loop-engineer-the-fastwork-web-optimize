# land-dry-full handoff (builder, round 2)

State: branch worktree-wf_64b49155-762-2, code commit 8c8b9b0 (then merges of main; the handoff commit is the head). check.sh green,
land-verdict/land-dry/land-inputs tests 235 pass, tsc clean, `fw land --dry` on this branch: VERDICT dry (with --allow for land-verdict.ts).

Round 2 (reviewer refusal)
- Lean `Fw.Console.LandDry`: `Outcome` (seven stage outcomes), `Outcome.first/kind/log`, `dryRun` = every stdout line of a dry run.
  Proved: `dryRun_one_verdict` (exactly one VERDICT line, last), `first_spec`/`kind_spec` (kind = first failing stage in the order
  exception, stale, empty, scope, conflict, reads, lint), `kind_ofStages` (= `dryKind`). The old vacuous `dry_prints_one_verdict` is gone.
- `lintPlan` (Lean) decides which lints run (`ciPaths_mem_plan`, `mathview_mem_plan`, `no_mathview_without_lean`); TS `lintPlan` in
  land-verdict.ts, `dryLintArgv` only reads which scripts exist.
- Real vs dry kind: `checkFailKind` (Lean) + `dry_kind_is_real_kind`, `lint_stages_are_lint`; the real land now prints `lint` when failed
  checks report only the check.sh stages `lake build` / `mathview lint` (`failedStages` parses `check: FAILED stage:` lines), else reads, else checks.
- Glue: `land.ts` returns `outcome` for a dry land (kind = `outcomeKind(outcome)`; refusals outside the stages = `threw`, kind unknown);
  `fw.ts` prints `dryRun(outcome, task)` on stdout, prose on stderr. Goldens: land-dry.jsonl 187 rows (all 128 outcomes, lint plans,
  check kinds); `land-verdict.test.ts` checks each row against the TS.
- Timing (this Mac, MEASURED): dry on this branch with a warm store 12.8 s end to end; the math-view lint alone cold (own whole-tree
  cache removed, MATHVIEW_STORE a fresh scratch dir, 146 modules all miss) 13.3 s, so a cold dry is about 12.8 + 13 s (the sum is not measured end to end).

Not proved / open: that `land.ts` computes the outcomes truthfully (tests only); the TS is a stand-in, not an fwcore op; the real land has
no ci-paths check, so a ci-paths dry failure has no real counterpart; a lint failure in a real land is recognised from check.sh text (regex).
Scope: the task writes lack apps/runner/src/land-verdict.ts and apps/runner/src/fw.ts (lead: allow them or land with --allow).
Read first: lean/Fw/Console/LandDry.lean (section "The dry run as a function of its stage outcomes"), apps/runner/src/land-verdict.ts.
