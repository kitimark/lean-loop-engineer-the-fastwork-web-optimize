# geom-image-model handoff
Branch: worktree-wf_ade92fb6-57c-1. Worktree: .claude/worktrees/wf_ade92fb6-57c-1. CI branch ci/geom-image-model (2 pushes used; first untagged and skipped).
CI: breakpoint-gate run 40566917070 success at fa1a0d8a1 (flip cell 48/48 both engines); lean run 40566916768 success.
Verified locally: check.sh green, @fw/site tests (8459), gate-breakpoints (56), ci-paths (56 of node tests), runner land-inputs (73), footprint --check.
Proved: lean/Fw/Parts/MorphGeomPic.lean pic_rect_eq, pic_crop_eq, pic_eq (all m in [0,1]), flip_covers, pic_end. No sorry.
Finding: the look report mid-morph shares (nav 27-78 %, columns 10-93 %) did not move (within 0.2 points); picture scaling was not their cause. m=1 rose slightly.
Open: cause of the mid-morph look difference (save per-region PNGs from look.mjs for both arms at m=0.5); task geom-look-fade; plan lint warns longTitle for this task.
Read first: research/notes/2026/10-2x-geom-image-model.md.
