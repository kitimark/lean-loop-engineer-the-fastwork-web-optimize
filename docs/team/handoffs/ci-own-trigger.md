# Handoff: ci-own-trigger

State: round 3 (final design) on branch worktree-wf_6bd98862-798-1, commit: see `git log -1`. CI on ci/ci-own-trigger.
- Lean `Fw/Ci/Intent.lean`: `decision` per lane: record runs; main push keeps coarse paths on its own diff
  (`main_keeps_paths_rule`); ci/* push skips in order unwanted, stale (sha not the ls-remote tip), landed, unchanged
  (no effective file of merge-base..HEAD is an input). `tip_starts`, `tip_lean_always`, `tip_history_free`,
  `stale_guard_never_starts`, `no_unrequested_start`, `default_no_macos`. Job re-check model: `stale_never_works`,
  `tip_job_unchanged`. Golden `packages/contracts/golden/ci/intent.jsonl` (20 cases incl. the revert sequence).
- `Fw/Ci/Cancel.lean`: ci/* groups hold the run id, so nothing cancels (`ci_group_alone`, `ci_never_cancelled`).
- `Fw/Ci/Verdict.lean`: run verdict (`pass_iff`, `stale_never_pass`), skip tags (`Skip`), branch wait
  `combineRequested` (`combine_requested_never_pass`, `due_lane_never_pass`, `missing_never_pass`); ops ci.verdict
  (lanes mode) and ci.required in Wire.
- Glue: `.github/scripts/changed-inputs.mjs` (guard, `branchFiles`, `isTip`), `scripts/ci-paths.mjs` (writes no
  paths, job groups without cancel, `tip re-check` + `stale:` steps, status-step conjunct), `scripts/ci-push.mjs`
  (branch preview, refuses when HEAD is already the tip), `packages/gh-budget/src/wait.ts` (lanes mode, 300 s grace).
- Docs: docs/team/tools/fw-ci.md (wait, trigger); research/notes/2026/10-18-ci-own-trigger.md "Round 3".
CI (MEASURED, round 3): A 84e8d32 premise-tests 39113339224 verdict job stopped at `stale:` after B a84fead was pushed
(wait: not-run); B premise-tests 39113394803 pass; B lean 39113394772 ran (lint fail, fixed 567cc31); C1/C2 in note.
Conventions: no decision in YAML/TS; never write `[ci:` in prose in a commit message; probe commits net to zero
(probe A/B/C: lean/probe-x.txt, packages/premise-tests/probe-y.txt added and removed).
Open items:
- Land step should push main's tip to ci/landed so `landed` is fresh.
- fw land --dry needs --allow for scripts/ci-push*.mjs, scripts/ci-paths.test.mjs, packages/gh-budget/**.
- The docstring checker pass was a self-review (no helper-spawn tool in this session).
- Read first: the research note "Round 3", then lean/Fw/Ci/{Intent,Verdict,Cancel}.lean.
