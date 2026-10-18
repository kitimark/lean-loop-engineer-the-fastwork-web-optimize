# Handoff: ci-own-trigger

State: round 5 (final design round) on branch worktree-wf_7cfa8fa7-bf1-1 (merged round-4 head 866474b and main);
commit: see `git log -1`.
- Lean `Fw/Ci/Intent.lean`: `decision` per lane. On ci/* a default lane (lean, `default_iff_lean`) never skips as
  `unchanged` (`lean_never_unchanged`, `tip_lean_always`); other lanes keep it. `waitLanes`, `wait_needs_default_pass`,
  `wait_needs_requested_pass`. Push preview `pushOk` (round 4).
- `Fw/Ci/Verdict.lean`: `laneOk` is "passed" (`laneOk_iff`), `LaneRun` has no `dflt`; `combine_requested_never_pass`
  covers every lane; `waitVerdict`, `unknown_request_never_pass`.
- `Fw/Ci/Wire.lean`: `ci.verdict` / `ci.required` read `waitLanes`; every def of the ci.verdict section has `$$`.
- Glue: `.github/scripts/changed-inputs.mjs` (`decide`: a default lane runs on every ci tip not landed),
  `packages/gh-budget/src/cli.ts` (`--msg` removed: the message comes from git only), workflow guard comments
  rewritten by `node scripts/ci-paths.mjs --write`.
- Docs: docs/team/tools/fw-ci.md; research/notes/2026/10-18-ci-own-trigger.md "Round 5" and "Limits".
Verified (local, round 5): `sh lean/scripts/check.sh` green; gh-budget 34/34, changed-inputs + ci-paths + ci-push
48/48; `#print axioms` of the new or changed theorems: propext, Classical.choice, Quot.sound only. No CI push.
Conventions: no decision in YAML/TS; never write `[ci:` in prose in a commit message; probe commits net to zero.
Open items:
- The lane request is read from the tip only; CLAUDE.md still names a raw `git push origin ci/<name>`.
- Land step should push main's tip to ci/landed so `landed` is fresh.
- `leanInputProblems` is hygiene for the main-push paths rule only now.
- The docstring checker pass was a self-review (no helper-spawn tool in this session).
- Dry land: `VERDICT scope`; scripts/ci-paths.test.mjs, scripts/ci-push.mjs, scripts/ci-push.test.mjs (rounds 3-4)
  lie outside the task globs: widen them or land with `--allow`.
- Read first: the research note "Round 5", then lean/Fw/Ci/{Intent,Verdict}.lean.
