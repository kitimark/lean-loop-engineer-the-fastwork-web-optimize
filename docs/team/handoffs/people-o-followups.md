Branch: worktree-wf_825e6ce6-888-1 (CI branch ci/people-o-followups)
Worktree: .claude/worktrees/wf_825e6ce6-888-1
Last commit: 9b056d92c (pushed to ci/people-o-followups)
CI runs: none finished yet (dispatches below are filled in as they start).

## State
- Code: run.mjs (load diagnostics behind FW_LOAD_TRACE; probe pass for profile.probe), host.mjs (FW_LOAD_TRACE passed into the container),
  profile people-o-hover (css text-wrap workaround from desktop-1280, probe selector `[role="tooltip"]`),
  preview.golden.test.ts (snapDev case dropped: no site function computes it; rows are Lean-only), results/.../probe-compare.mjs.
- Verified so far: node --test test/profile.test.mjs (6 pass) locally; nothing measured yet.

## Open
- people-o-hover counts, base vs `--fw people.o:preview-translate`, 3 runs each, Chromium (fw run, at most 6 dispatches).
- Probe compare (rect and PNG hash of the open card per frame) from the stored counts.json of both arms.
- Ledger row n 53 chromium verdict; note and results; land dry run.
