# site-layer-opts-followups (part-builder)

Branch `worktree-wf_4dc1280f-1ad-1`, worktree `.claude/worktrees/wf_4dc1280f-1ad-1`. No CI push, CI runs: none.
Code commit: f93f02fc (round 2 fixes plus merge of main).

Done (round 2):
- `resolve.ts` guard is `new URLSearchParams(search).has('fwl')`: an encoded key (`?f%77l=...`) is refused like Lean.
- Lean general theorems `validate_percent` and `validate_plus` (from `validate_charset` + `okChar_percent`/`okChar_plus`) replace the single instance.
- Golden rows (regenerated with `lake build Fw.Ops.Golden` then `lake env lean --run scripts/OpsGolden.lean`): encoded fwl key, encoded key and value, and the two-layer URL-order row `?fwl=nav_earn:s,hero_copy:c` (canonical keeps input order).
- Mutation check: sorting `layerOpts` by layer in resolve.ts makes the URL-order row fail (1 failed, 28 passed); reverted.
- Round 1: order-exact replay. Reap tests on main tip 7fd1d23d (reap code untouched): `vitest run reap` in apps/runner, 5 files,
  126 tests, all pass in 41 s; the 10 failures did not reproduce; no task filed.

Verified: lean/scripts/check.sh green; `pnpm --filter site test` 114 files pass; ci-paths test 54 pass.
Open follow-ups: UTF-16 vs code-point length reasons; non-fwl searches still decoded on the site.
Read first: BuildsOpen.lean (validate_percent), resolve.ts top.
