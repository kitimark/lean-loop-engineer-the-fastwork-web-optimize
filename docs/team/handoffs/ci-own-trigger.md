# Handoff: ci-own-trigger

State: branch worktree-wf_82acc4e9-d33-3, work at 74ea297, main merged at e2830bb, then this note. CI proof on ci/ci-own-trigger, 2 pushes.
- Lean `lean/Fw/Ci/Intent.lean`: a ci push starts lane l iff the head commit wants it (`[ci:<lane>]`, any case; no `[ci:`
  at all = only `lean`) and Trigger.starts on the effective diff and not superseded and not landed. Proved:
  no_unrequested_start, requested_and_changed_starts, default_no_macos, superseded_never_runs_heavy,
  landed_never_runs_heavy, start_ci_iff (starts_iff restated), no_lane_lost (coarse_sound end to end), gate_eq,
  start_gate, tok_infix_inj, unsuperseded_replays. Golden `packages/contracts/golden/ci/intent.jsonl`
  (`lake test -- --write-ci-trigger-golden`).
- Guard `.github/scripts/changed-inputs.mjs`: decide(lane,msg,newer,landed), guardBase (origin/ci/landed if it contains
  origin/main), isLanded, newerFiles (ls-remote tip, GUARD_TOKEN). Guard job `if:` = Lean ifExpr, written by
  `node scripts/ci-paths.mjs --write` (reconcile checks if:, GUARD_TOKEN, the comment).
- Helper `scripts/ci-push.mjs` = `pnpm fw ci push --branch ci/<t> --lanes a,b|none [--dry]` (route in apps/runner/src/fw.ts).
- Tests: scripts/ci-paths.test.mjs (Lean replay of start and of the if: via a mini evaluator), changed-inputs.test.mjs
  (git fixtures: landed, base, newer), scripts/ci-push.test.mjs; all run by apps/runner/test/ci-triggers.test.ts.
- Docs: research/notes/2026/10-18-ci-own-trigger.md (design, forensics replay), docs/team/token-policy.md,
  docs/team/tools/fw-ci.md (new agent rule).
CI (MEASURED, 2 pushes; a 3rd was not needed):
- push 1 3da2c3d `[ci:engine-premises]`: only engine-premises 39106170371 started (guard run=true, "2 of 56"); the 12
  other runs were created and skipped at the guard if: (e.g. lean 39106170390, wktr 39106170405).
- push 2 74ea297, no token: only lean 39106360843 started and passed (ubuntu, about 3.5 min); 12 skipped. It
  superseded push 1: run 39106170371 was cancelled 2 s later and its queued macOS jobs webkit j2/j3 never ran (j1 had
  run 3.3 min). The newer engine-premises run 39106360862 was skipped (not requested).
Conventions: no decision in YAML/TS; never write `[ci:` in prose in a commit message. Read first: the research note.
Open items:
- Workflow-level concurrency cancels in-flight runs on any newer push whose paths match, before the guard if: (cause d);
  fix = job-level concurrency on heavy jobs.
- Land step should push main's tip to ci/landed (agents may push ci/*) so guardBase/isLanded are fresh.
- fw land --dry needs --allow scripts/ci-paths.test.mjs, scripts/ci-push.mjs, scripts/ci-push.test.mjs (task writes list).
- No checker helper was available in this agent (no Agent tool); docstrings self-checked against the 6-point list.
