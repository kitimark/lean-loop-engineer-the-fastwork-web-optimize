# gc-landed-identity handoff (round 2)
Branch worktree-wf_b3ea803d-b49-1, worktree .claude/worktrees/wf_b3ea803d-b49-1. No CI runs (accepted limit).
Rule (lean/Fw/Ops/DiskGc.lean ruleLanded): dir, branch, (landCommit OR landedByTask), merged == some true (tip on main),
not usedByLive, clean. Unknown facts keep the worktree.
- landedRuns keeps a run only when EVERY task it labelled is done (landedRuns_spec all-of, landedRuns_undone).
- Theorems: fast_forward_kept, landed_never_live, landed_by_identity, land_commit_selects (needs tip on main),
  reopened_kept, rule_landed, liveRuns_spec, landedRuns_spec.
- Goldens (lean/scripts/DiskGcGolden.lean -> packages/contracts/golden/ops/diskgc.jsonl, regenerated): fast-forward, live,
  reopened, land commit with tip on main, wf_df082d5f-ac9-3 shape (landed run, tip not on main, kept), partly-done run facts.
- apps/runner/src/disk-gc.ts gathers facts only; test covers ff, live, reopened.
- Live replay (scratchpad gli-replay.py, same rule on .fw-console/events.jsonl + git): selects 0 worktrees, keeps 15, none
  of the 8 parked (wf_3501c97f, 74c62bb3, ac1f31e3, aee66ce7, c7f678ea, c8917a6a, df082d5f-ac9-3, e6df42ab).
- Incident inc-gc-landed-ff in docs/team/incidents/ledger.json.
Known gaps: (a) remote lands write "land <task> <sha7>", never matching "land <branch>" (safe: keeps); (b) a live agent
without a wfid label is not seen (follow-up); (c) the idle class has no live-agent guard (follow-up).
Read first: lean/Fw/Ops/DiskGc.lean (ruleLanded, landedRuns).
