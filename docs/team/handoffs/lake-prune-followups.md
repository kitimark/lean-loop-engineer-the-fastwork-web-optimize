branch: worktree-wf_5dacc60e-792-1
worktree: .claude/worktrees/wf_5dacc60e-792-1
CI runs started by me: none (accepted limit: no dispatched CI run).

State: (1) job "lake-cache golden check" added to lean/scripts/check.sh after the oracle labels job. (2) none-yet recorded
with runs 40018133417, 40023506297, 40026419674 (each branch contained the newest main entry commit); legs unchanged, Lean row stays a followUp.
(3) note section 2 stripping claim is INFERRED with Lake file:line@lean4 eb6cafb (Build/Common.lean:719-721, 656-659, 217-218).
Verified: check.sh green (lake-cache golden equals the Lean output, 17 lines); fw land --dry prints VERDICT dry lake-prune-followups. (check.sh, dry land).
Open: the first leg whose Lean tree is behind the restored entry extends Fw.Ops.LakeCache.legs + golden.
Read first: research/notes/2026/10-2x-ci-setup-lean-slow.md section 2 and the "Branches behind main" paragraph.
