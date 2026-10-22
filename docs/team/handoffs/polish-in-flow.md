# polish-in-flow handoff

State (round 2): branch `worktree-wf_882335de-ca7-1`, merged with main (incl. f86ed22a build-review gate report file); check.sh green, apps/runner test green,
`fw land --dry` prints `VERDICT dry polish-in-flow`. Read first: `docs/team/tools/polish.md`.

What was built
- Lean `lean/Fw/Plan/Polish.lean`: classes code/shell/prose/skip (`classify`; skip from generator outputs, a `GENERATED`
  first line, `.gen.` names, golden/snapshot/fixture trees), marks, stages and scopes, kept vs restored edits, cut verdicts
  (`judge`, `cutSafe`, `applyAll`). One theorem per branch; the three 10-22 over-cuts are `#guard`s and golden rows.
- Wire `lean/Fw/Wire/Plan.lean` (outside the graph writes): ops `plan.polishPlan`, `plan.polishCuts`, `plan.roster`.
- TS `apps/runner/src/polish.ts`, `fw polish plan|cuts|commit|--staged` (wired in `fw.ts`); generator outputs come from
  `scripts/ci-paths.mjs` (`loadGolden` workflows plus `LAKE_GEN`).
- Tests: `apps/runner/test/polish.test.ts` (golden `packages/contracts/golden/plan/polish.jsonl`,
  `FW_WRITE_POLISH_GOLDEN=1`), `apps/runner/test/spawn-guard-roster.test.ts` (agent files vs `plan.roster`, hook ROLES).
- `.claude/workflows/build-review.js`: phase Polish after an accepting review (plan, comment-sicko, slop-checker cuts,
  `fw polish cuts --apply yes`, `fw polish commit`, dry land again); returns `polish` to the lead.
- Docs: `docs/team/token-policy.md`, `.claude/agents/comment-sicko.md`, `docs/team/tools/polish.md`.

Open
- Measuring the stage over 5 builds is a follow-up (pinned unit excludes it).
- `fw polish` in the workflow needs this branch on main and fwcore rebuilt in the main checkout (post-land routine).
- The runner helper runs `fw polish commit`, which writes git through fw; runner.md forbids only direct git writes.
- Round 2: `polarWords` (not/no/never/without/unless) are facts in `facts` (Polish.lean), so all three 10-22 over-cuts are
  `dropsFacts`; build-review.js runs Polish when the review's only refusals are fix-before-land/follow-up (`onlyFixes`).
- Accepted limits: a cut that keeps every token and polarity word but drops other meaning applies; kept edits are chosen
  by path (a comment-only hunk check is a follow-up, with findings 5-8 of round 1).
- Commit note: the pre-commit checkmap runs `node --check` on .claude/workflows/build-review.js, which has top-level
  return/await and fails with a current fwcore; the merge commit needs the lead (land token) or a CheckMap rule for it.
