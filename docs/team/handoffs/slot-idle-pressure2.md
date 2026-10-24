# slot-idle-pressure2 handoff
Branch: worktree-wf_f1365353-0cd-1. Worktree: .claude/worktrees/wf_f1365353-0cd-1. No CI runs pushed (local-only Lean task).
State: idleHead (lean/Fw/Sup/Adapt.lean) admits at press 1..2 with no live holder, no thrash, no swap; press >= 3 waits.
Theorems: idleHead_iff restated; idle_head_progress, idle_head_progress_alone, idleHead_waits_{thrash,swap,critical,holder};
admit_calm weakened (press 1, or empty slot at press 2); sim_not_starved gained hypothesis press = 1 (after a level-2 idle
admit the follower waits memLow; accepted). idle_head_at_most_one unchanged and still proved.
Goldens regenerated from Lean (packages/contracts/golden/sup/adapt.jsonl) with the two incident samples; slot-core.ts idleHead follows; slot.md has an Idle head paragraph.
Named exception: local checks ran with FW_SLOT_SELF=off (queue stalled). Runner test: 107 files / 3433 tests green.
Not touched: lean/Fw.lean, lean/scripts/check.sh, work-graph.json.
Open: lead wiring only.
