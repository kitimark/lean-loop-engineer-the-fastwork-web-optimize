# gc-live-agent-cwd handoff
Branch worktree-wf_56018ca3-024-1, worktree .claude/worktrees/wf_56018ca3-024-1. No CI runs (accepted limit).
Rule additions in lean/Fw/Ops/DiskGc.lean:
- cwdHits (in `live`, so every class): a live process cwd c blocks x when c is inside x.path, or c is inside the
  worktrees root and contains x.path (agent in a worktree root keeps its idle node_modules). cwds unread (none) keeps all.
  Theorems: never_cwd, worktree_cwd_kept, cwd_unread_kept.
- remoteLand (inside landCommit): subject `land <task> <sha7>` + taskRuns (task, run) pair + runOwns run path; tip still
  must be on main. Theorems: remote_land_identity, remote_land_selects; landed_by_identity has the third disjunct.
- Facts: ops.diskGcFacts also returns taskRuns (from wfid-label events). Goldens regenerated (67 cases, 6 new).
TS (apps/runner/src/disk-gc.ts) gathers facts only: gatherCwds = `lsof -a -d cwd -Fn`. Limit: snapshot of now, same-user
processes only, null when lsof prints nothing (keeps everything). agent.spawn events carry no cwd, so the process table
is the source. Test: apps/runner/test/disk-gc.test.ts (cwd + remote land).
Live replay (scratchpad glac/replay.ts, main repo facts, classes 2,3): class 2 selects 0 worktrees. Class 3 (existing idle
rule) selects dependency dirs (node_modules, lean/.lake) of 4 parked worktrees (wf_3501c97f, 74c62bb3, ac1f31e3, aee66ce7),
never the worktree dirs; wf_c7f678ea, c8917a6a, df082d5f-ac9-3, e6df42ab selected nothing. Worktrees with a live cwd
(a3f3d112, e07fe309, 56018ca3, ada62af5, 9aacdd20) selected nothing.
Open: the idle class dropping parked worktrees' deps is the pre-existing idle rule, not changed here.
Read first: lean/Fw/Ops/DiskGc.lean (cwdHits, remoteLand).
