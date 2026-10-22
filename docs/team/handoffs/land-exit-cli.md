# land-exit-cli handoff

Branch: worktree-wf_786e8317-25b-1. Worktree: .claude/worktrees/wf_786e8317-25b-1. CI runs: none (local gates only).
Last code commit: see git log.

## Done
- fw-main.ts: dropped the `dry && kind === install` branch; dry path uses `dryLandReport` (land.ts); real land exit is `landExit(res)`.
- land.ts: `dryLandReport`; `checkoutLandWt` cleans once per path (reused worktree no longer cleaned after prep).
- apps/runner/test/land-exit-cli.test.ts (5 tests); land.md paragraph.

## Open
- TS only; no Lean change (verdict kinds untouched; land-rebuild-flake is its own task).
