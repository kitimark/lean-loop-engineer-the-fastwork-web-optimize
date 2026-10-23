# Writes closure lint

- Branch `worktree-wf_29c7f846-55b-1`, worktree `.claude/worktrees/wf_29c7f846-55b-1`, main merged at 578e80911.
- Round 2 code commit e3dacea76; no CI runs. check.sh green in 1m37s, runner tests 2967/2967, ci-paths 54/54.

## Rule (lean/Fw/Plan/WritesClosure.lean)
- `Gap` = a literal `../<path>` read of a `lean/scripts/*.sh` that the lean.yml row lacks, the exact `leanInputProblems`
  refusal (scripts/ci-paths.mjs:846-859). `gapsOf` (plan-closure.ts) computes them with ci-paths' own functions.
- Trigger.lean + triggers.jsonl are required only when the row names a gap's path or script (`trigger_only_by_read`),
  or it adds a workflow (`trigger_required_iff`). A new workflow requires Trigger.lean, Intent.lean, Overflow.lean
  and their goldens (ci-paths.mjs:1076-1078, land-overflow-widths.test.ts). A new module requires lean/Fw.lean.
- Not derived: Pool/Caps.lean, scripts/ci-paths.test.mjs (only a macOS job; 6dbd68b6b), apps/runner/src/land.ts (no
  per-workflow table), check.sh for a golden (no check enforces it).
- `#guard`s: soundness (every error is in the case's `added`), completeness per kind (workflow, module, gap), and no
  Trigger error without a gap or a new workflow.

## Verified
- Per real pre-build row: r325 error on Trigger.lean when the lint reads the build branch f4743ef8a (check.sh reads
  the classpos golden, the lean row lacks it); r328 the same on its build branch 5599b944d; on main r322, r323, r325, r328, r330, r331, r334 give no finding (main's check.sh reads are all lean inputs). A closure
  of the writes cannot flag artefacts a row does not name. Differs from finding (1)'s text: design (3) removes the
  open-glob Trigger warnings and makes r328's branch an error too.
- Main graph 578e80911: 5 errors on 2 rows, each confirmed `outOfScope` by fwcore `console.landScope`:
  ci-offload-checks (Intent.lean, Overflow.lean for agent-checks.yml), touch-first-scroll-probe (Trigger, Intent,
  Overflow for webkit-lag-probe.yml). Was 38.

## Open
- `fw plan sync` does not run the lint (fw-main.ts outside writes).
- safari-macos-ci writes `lean/Fw/Pool/Caps.lean`; the file is `lean/Fw/Ci/Pool/Caps.lean` (lead graph fix).
- Read first: the case table at the end of WritesClosure.lean, then `gapsOf` in plan-closure.ts.
