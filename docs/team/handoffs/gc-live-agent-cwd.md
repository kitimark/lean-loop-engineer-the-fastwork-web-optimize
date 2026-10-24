# gc-live-agent-cwd handoff
Branch worktree-wf_56018ca3-024-1, worktree .claude/worktrees/wf_56018ca3-024-1. No CI runs (accepted limit).
Rule additions in lean/Fw/Ops/DiskGc.lean:
- cwdHits (in `live`, so every class): a live process cwd c blocks x when c is inside x.path, c is the
  worktrees root and contains x.path, or c is inside worktree W (wtOf) and x.path is anywhere under W. cwds unread (none) keeps all.
  Theorems: never_cwd, worktree_cwd_kept, root_cwd_kept, cwd_unread_kept.
- remoteLand (inside landCommit): subject `land <task> <sha7>` + taskRuns (task, run) pair + runOwns run path; tip still
  must be on main. Theorems: remote_land_identity, remote_land_selects; landed_by_identity has the third disjunct.
- Facts: ops.diskGcFacts also returns taskRuns (from wfid-label events). Goldens regenerated (68 cases, 7 new).
TS (apps/runner/src/disk-gc.ts) gathers facts only: gatherCwds = `lsof -a -d cwd -Fn`. Limit: snapshot of now, same-user processes only, null when lsof prints nothing, times out (60 s) or exits other than 0/1 (keeps everything). agent.spawn events carry no cwd, so the process table is the source. Test: apps/runner/test/disk-gc.test.ts (cwd + remote land).
Round 1 live replay: nothing under the live-cwd worktrees (a3f3d112, e07fe309, 56018ca3, ada62af5, 9aacdd20) was selected.
Round 2: wtOf + third disjunct; #guards and golden row for cwd=<wt>/w1/apps (class 3); golden case renamed; lsof status.
Live replay (glac/replay.mts, main repo, classes 2,3): class 2 selects 0. Class 3 selects only dependency dirs of 4 parked
worktrees (3501c97f, 74c62bb3, ac1f31e3, aee66ce7); nothing under the worktrees with a live cwd (4 in that snapshot), incl. 56018ca3 (cwd apps/runner).
Verified: lean check green, @fw/runner test 3294 pass. Open: none. Read first: lean/Fw/Ops/DiskGc.lean (cwdHits, wtOf).
