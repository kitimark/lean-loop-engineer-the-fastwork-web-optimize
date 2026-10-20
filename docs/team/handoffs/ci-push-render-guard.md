# ci-push-render-guard handoff
State: branch worktree-wf_806a9816-134-2.
- `scripts/hooks/pre-push` (sh): for pushes to refs/heads/ci/* pipes stdin to `node apps/runner/src/ci-push.ts`.
- `apps/runner/src/ci-push.ts`: `ciPushRefusals(stdin, cwd, base="origin/main")` reuses land.ts `renderGuard` (fwcore `console.landRenderGuard`); prints `REFUSED: ci push render guard: ...`. land.ts untouched. No new Lean.
- Test `apps/runner/test/ci-push-render-guard.test.ts` (3 cases, temp repo + bare origin) passes.
- Doc: docs/team/tools/land.md, last section.
- Hook point rationale: hook beats a `fw ci push` command (agents use plain git push; hooksPath already set by wt-prep).
Open: bypass by --no-verify or a worktree without wt-prep (accepted); fw.ts `ci` docs may mention the hook later.
Read first: apps/runner/src/ci-push.ts.
Writes outside the list: none.
