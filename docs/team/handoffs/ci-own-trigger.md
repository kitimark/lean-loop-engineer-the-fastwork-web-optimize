# Handoff: ci-own-trigger

State: round 4 on branch worktree-wf_b4b76cde-a4b-3 (merged round-3 head 5e499ac and main), commit: see `git log -1`.
- Lean `Fw/Ci/Intent.lean`: `decision` per lane (record runs; main push keeps coarse paths; ci/* skips in order
  unwanted, stale, landed, unchanged). Round 4: push preview `pushOk` (`push_full_starts`, `skipped_named_refused`,
  `partial_starts_one`), 170 push vectors in `packages/contracts/golden/ci/intent.jsonl` (kind `push`).
- `Fw/Ci/Verdict.lean`: run verdict, `combineRequested`; round 4 `waitVerdict` (`unknown_request_never_pass`,
  `wait_pass_iff`). `Fw/Ci/Wire.lean`: `ci.required` / `ci.verdict` with `msg` null or absent answer not-run.
- `Fw/Ci/Trigger.lean`: the lean row now lists the five files `lean/scripts/check.sh` reads via `../`.
- Glue: `packages/gh-budget/src/cli.ts` (`messageOf`: null on a git failure), `wait.ts` (stops at once on an unknown
  request), `scripts/ci-push.mjs` (`pushOk`, `--partial`), `scripts/ci-paths.mjs` (`leanInputProblems` lint).
- Docs: docs/team/tools/fw-ci.md; research/notes/2026/10-18-ci-own-trigger.md "Round 4".
Verified (local, round 4): `sh lean/scripts/check.sh` green; gh-budget 33/33, ci-push 5/5, ci-paths 32/32,
changed-inputs 11/11; `#print axioms` of the 5 new theorems: propext, Quot.sound only. No CI push this round.
Conventions: no decision in YAML/TS; never write `[ci:` in prose in a commit message; probe commits net to zero.
Open items:
- The lane request is read from the tip only; CLAUDE.md still names a raw `git push origin ci/<name>` (lead/user edit
  to `pnpm fw ci push`).
- The lean-input lint reads literal `../` paths in `lean/scripts/*.sh` only.
- Land step should push main's tip to ci/landed so `landed` is fresh.
- The docstring checker pass was a self-review (no helper-spawn tool in this session).
- Read first: the research note "Round 4", then lean/Fw/Ci/{Verdict,Intent}.lean.
