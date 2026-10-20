# ci-push-render-guard handoff
State: branch worktree-wf_806a9816-134-2; round 1 f9f1417c, round 2 commit is the branch tip (git log -1).
- `scripts/hooks/pre-push` (sh): pipes stdin of every push to `node apps/runner/src/ci-push.ts`.
- `apps/runner/src/ci-push.ts`: `ciPushRefusals(stdin, cwd, base="origin/main")` skips refs/heads/main and deletions, reuses land.ts `renderGuard` (fwcore `console.landRenderGuard`) for every other ref (branches, tags). No new Lean.
- land.ts: one read declared, `scripts/hooks/**` in the apps/runner reads (TS list only; no Lean/golden mirror of it exists, checkShReads is a different list).
- Test `apps/runner/test/ci-push-render-guard.test.ts` (4 cases, temp repo + bare origin, incl. tag and non-ci branch).
- Doc: docs/team/tools/land.md, last section.
- Limits: extension-only; `--no-verify` bypasses; worktrees on branches predating this land have no hook file until they merge main (lead tells them).
Checks: runner suite, lean/scripts/check.sh, scripts/ci-paths.test.mjs (see report).
Writes outside the list: none.
Read first: apps/runner/src/ci-push.ts.
