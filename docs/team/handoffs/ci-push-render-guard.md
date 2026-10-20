# ci-push-render-guard handoff
State: branch worktree-wf_806a9816-134-2; r1 f9f1417c, r2 f5fd637e, follow-up is the tip.
- `scripts/hooks/pre-push` (sh): pipes stdin of every push to `node apps/runner/src/ci-push.ts`.
- `apps/runner/src/ci-push.ts`: `ciPushRefusals(stdin, cwd, base="origin/main")` skips refs/heads/main and deletions, reuses land.ts `renderGuard` (fwcore `console.landRenderGuard`) for every other ref (branches, tags). No new Lean.
- land.ts: one read declared, `scripts/hooks/**` in the apps/runner reads (TS list only; no Lean/golden mirror of it exists, checkShReads is a different list).
- Test `apps/runner/test/ci-push-render-guard.test.ts` (4 cases, temp repo + bare origin, incl. tag and non-ci branch).
- Doc: docs/team/tools/land.md, last section.
- Limits: extension-only; `--no-verify` bypasses; worktrees on branches predating this land have no hook file until they merge main (lead tells them).
Checks (r2, f5fd637e): runner 1622/1622 pass (dist/aot absent; with it present 2 land-inputs cases failed, fixed on main by land-inputs-dist), lean/scripts/check.sh green, ci-paths.test.mjs 49/49.
Writes outside the list: none.
TS stand-in: the ref filter in apps/runner/src/ci-push.ts (skip refs/heads/main, skip deletions) is unproved TS; follow-up: a Lean ref decision with a golden vector.
Read first: apps/runner/src/ci-push.ts.
