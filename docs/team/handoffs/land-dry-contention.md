# land-dry-contention handoff

- Branch `worktree-wf_ce64bd7a-546-1`, worktree `.claude/worktrees/wf_ce64bd7a-546-1`; closing round 3, main merged.
- CI runs: none (accepted limit "no CI run").

## State
- The task closed as a finding. The round 1-2 code (Timing/Health/Obs/WritesClosure Lean, timing goldens) was reverted
  to main in one revert commit (bb035aecd); it stays in branch history. `git diff main...HEAD --stat` lists only the
  note and this handoff.
- Finding: `research/notes/2026/10-2x-land-dry-contention.md` (cutoff 1792808775650). Three of four alerts had no
  co-runner; the dry land's own land-inputs vitest and lake rebuilds grew; 133 of 760 local dry-land spans (first count
  186 of 808) ran with no land-slot acquire, because `slot.ts:556-561` skips acquire when `FW_SLOT_HELD` is set.
- Mechanisms are INFERRED; c4f662a's 9.0 s at 0 built modules is unexplained.
- No TS verdict logic, no TS stand-in.

## Re-plan (lead adds to work-graph.json)
land-inputs-growth, land-wt-lake-rebuilds, slot-held-identity, timing-contended-identity (optional, after the other three).
Follow-ups: one canonical alert key per dry-land nest; one land log per run.

## Open
- The note's counts re-derive with the pinned cutoff from timings.jsonl and locks.jsonl; they differ slightly from the
  lead's first counts (760/133/40 against 808/186/47; lake table 104/49/56 against 100/48/56).

## Read first
- The note.
