# Handoff: ci-own-trigger

State: branch worktree-wf_d4f5d370-7de-1 (round 2 on top of round 1 74ea297 and main), commit: see `git log -1`. CI on ci/ci-own-trigger.
- Lean `Fw/Ci/Intent.lean`: start iff wanted (`[ci:<lane>]`, any case; the default lane lean ALWAYS wanted:
  `lean_always_when_changed`, `default_no_macos`) and changed and not superseded (by a newer push that wants the lane:
  `unwanted_never_supersedes`) and not landed. Golden gate vectors (`gateVectors`, every lane x event x ref x message)
  pin each workflow's written guard `if:` (scripts/ci-paths.test.mjs). Job-level `groupExpr`/`cancelExpr`.
- `Fw/Ci/Cancel.lean`: job-level groups lose no requested run (`no_requested_lost`); a cancel needs a newer STARTED job
  (`cancel_needs_newer_start`); workflow-level groups did lose one (`wf_level_loses`, measured round 1).
- `Fw/Ci/Verdict.lean` + op `ci.verdict` (Wire): pass iff guard decided run, a job ran, all that ran succeeded
  (`pass_iff`, `skipped_never_pass`, `shown_skip_never_pass`); not-run = exit 4 with the guard's reason.
- `packages/gh-budget/src/wait.ts`: one charged `gh run view <id> --json jobs` per finished decisive run (cached
  meta/<id>.jobs.json, lock), then `ci.verdict`. cli prints code 4 on stdout; apps/runner `decided()` names not-run.
- Workflows: `node scripts/ci-paths.mjs --write` writes guard `if:` (none for lean), `decision: run` /
  `decision: skip: <reason>` steps, job-level concurrency before runs-on; checks macOS runs-on vs Lean, status fns.
- Guard `.github/scripts/changed-inputs.mjs`: `reason=` output; supersede only by a tip that wants the lane (`tipMsg`).
- `scripts/ci-push.mjs`: default lanes count as asked; refuses only when no REQUESTED lane starts.
CI (MEASURED, round 2): see research/notes/2026/10-18-ci-own-trigger.md "Round 2" (run ids, exit codes).
Past false passes (MEASURED, 13 charged gh calls): 0 of 12 cited guard-era `success` runs had their heavy jobs skipped.
Conventions: no decision in YAML/TS; never write `[ci:` in prose in a commit message; probe commits net to zero.
Open items:
- Land step should push main's tip to ci/landed so guardBase/isLanded are fresh.
- fw land --dry needs --allow for scripts/ci-push*.mjs, scripts/ci-paths.test.mjs, packages/gh-budget/**.
- Supersede reads only the tip's push diff (research note, Limits).
- Read first: the research note, then lean/Fw/Ci/{Intent,Cancel,Verdict}.lean.
