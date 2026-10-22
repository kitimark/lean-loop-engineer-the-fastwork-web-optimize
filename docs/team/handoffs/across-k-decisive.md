branch: worktree-wf_09e70282-75a-1
worktree: .claude/worktrees/wf_09e70282-75a-1
last commit: see `git log -1` on the branch
CI runs: none dispatched (offline re-reduction of the artifacts of 39729682403, 39744983394, 39754568950)

# across-k-decisive: done

Rule: the verdict over jobs is `acrossDecisive vs = across (agreeNeeded (decisive vs)) vs`
(lean/Fw/Gate/Smooth.lean:646); an `insufficient` job counts as absent.

Verified: `sh lean/scripts/check.sh` green; @fw/gate-breakpoints (635) and @fw/measure-webkit (402) tests pass;
scripts/ci-paths.test.mjs and apps/runner land-inputs.test.ts pass.
- Theorems: `acrossDecisive_insufficient`, `_first`, `_second`, `_split`, `_same` (one per branch),
  `_first_two_thirds`, `_second_two_thirds` (a first/second needs >= 3 decisive jobs, >= two thirds agreeing, none
  against), `_filter` (dropping insufficient jobs never changes the verdict), `_swap`, `_ne_all_jobs` (the old
  all-jobs k gives `same` where the decisive k gives `first`). `minSamples` got the docstring the title asked for.
- Golden op `acrossDecisive` (8 cases) in packages/contracts/golden/gate/smooth.jsonl; `smooth.test.mjs` checks the
  twin `acrossDecisive`/`decisive` in reduce.mjs against it.
- Twins: report.mjs `acrossJobs` uses `acrossDecisive` (new field `need`); cadence-table.mjs `summary` uses it
  (`need` split into `needRate`/`needHitch`, table column "need rate / hitch").
- Re-reduction (`node packages/measure-webkit/src/profile/cli.mjs report --runs <dir>/<runid>/<artifact> --out ...`):
  11 jobs, 12 verdicts, 0 changed; results/smoothness-webkit/summary.json 36 verdicts, 0 changed;
  results/smoothness-probe/cadence.table.json 24, 0 changed. Recorded in research/notes/2026/10-2x-earn-gpu.md
  section "The agreement threshold counts decisive jobs"; the note's Smooth.lean line citations were refreshed.

Open (outside the task writes, edited because the tests check the twins):
- packages/gate-breakpoints/test/smooth.test.mjs, packages/measure-webkit/test/profile-report.test.mjs.
- results/smoothness-probe/cadence.table.json keeps the old field `need` (no verdict changes, so not regenerated).
