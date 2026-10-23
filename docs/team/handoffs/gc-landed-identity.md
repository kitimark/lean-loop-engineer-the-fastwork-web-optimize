# gc-landed-identity handoff
Branch worktree-wf_b3ea803d-b49-1, worktree .claude/worktrees/wf_b3ea803d-b49-1. No CI runs (accepted limit).
State: Lean landed class by identity done and checked (lean/scripts/check.sh green, apps/runner tests 3269 green).
- lean/Fw/Ops/DiskGc.lean: ruleLanded cfg x = dir, branch, (landCommit || landedByTask), not usedByLive, clean.
  Facts: Config.landSubjects (main subjects "land ..."), liveRuns, landedRuns (from events, ops.diskGcFacts).
  Unknown facts (none) keep the worktree. Theorems: fast_forward_kept, landed_never_live, landed_by_identity,
  land_commit_selects, liveRuns_spec, landedRuns_spec. `merged` stays only for the idle class.
- Goldens: lean/scripts/DiskGcGolden.lean -> packages/contracts/golden/ops/diskgc.jsonl (regenerate, never hand-edit).
- apps/runner/src/disk-gc.ts: gathers landSubjects (git log main) and liveRuns/landedRuns; emits every worktree for Lean.
- Incident inc-gc-landed-ff appended to docs/team/incidents/ledger.json.
Open: a run owning a worktree is mapped by dir name prefix `<run>-`; an agent with no wfid label is not seen
(accepted). Idle class has no live-agent guard (follow-up). Lead lesson: start a dependent only after its dependency is on main.
Read first: lean/Fw/Ops/DiskGc.lean (ruleLanded, landed_never_live).
