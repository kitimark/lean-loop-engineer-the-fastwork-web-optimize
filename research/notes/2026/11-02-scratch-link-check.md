# scratch-link-check: fw land --dry refuses an added symlink that leaves the worktree

Incident inc-scratch-symlink-wait: a builder linked the session scratchpad into its worktree and a `cp` through the link waited
for a permission answer (cause INFERRED in the ledger).

## What was built (CONFIRMED by the tests named)

- Lean `Fw.Ops.LandLink` (`lean/Fw/Ops/LandLink.lean`): a link (path, target) is resolved against its directory; `..` pops, `.` and
  empty segments change nothing. Refused: empty target (`check_empty`), target starting with `/` (`check_absolute`), a `..` that pops
  below the worktree root (`check_escapes`); every other link passes (`check_inside`); `mem_refused` ties the list to `check`.
- Wire op `ops.landLink` (`lean/Fw/Ops/Wire.lean`); golden rows `packages/contracts/golden/ops/land-link.jsonl` written by
  `lean/Fw/Ops/Golden.lean`.
- TS `apps/runner/src/land-link.ts`: `git diff --raw -z --no-renames --diff-filter=AMT <merge-base> <tip>`, entries with new mode
  120000, target by `git cat-file blob`; Lean decides through fwcore (no TS copy of the rule). `land.ts` runs it after the render
  guard, before any check: kind `scope`, line `REFUSED: land-link: ...`, so `VERDICT scope <task>`.
- Preamble sentence in `.claude/workflows/build-review.js`: `scratchpad/<agent-name>/` is the only scratch place; never symlink.

## Limits

- Only links the branch adds or changes are checked; a link already on main is not.
- Tracked symlinks only; untracked ones never reach a land.
- A link that stays inside the worktree can still point at a file the agent should not write; the rule checks the path boundary only.
- The VERDICT kind is the existing `scope` (exit 12); a new kind would change the Lean exit table.
