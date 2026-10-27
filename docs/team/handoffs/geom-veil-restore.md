# geom-veil-restore handoff
Branch: worktree-wf_30ae41a0-29d-1 (CI branch ci/geom-veil-restore, pushed). Worktree: .claude/worktrees/wf_30ae41a0-29d-1. CI run 40553185213 breakpoint-gate: complete (job success, readings in artifacts flip-cell-*, look-*). check.sh green.

State: veil track restored (site tracks.ts, tree.ts, geom.css; Lean layers/anims/Rect/Counts), golden regenerated (707 lines),
footprint regenerated, finding in research/notes/2026/10-2x-geom-veil-restore.md and findings ledger note (premises, geom-veil-restore).
Proved in lean/Fw/Parts/MorphGeomLook.lean: look_veil_x/y/sx/sy, veil_rect_base, veil_no_opacity. Memory: net_lvl0_veil_bytes in MorphGeomCounts.
Verified locally: lake build Fw, golden --check, apps/site vitest (after footprint --write).
Open: whole-page m=1 difference (5.6-42 %, cause not shown); WebKit timed arm 21 of 24.
Read first: research/notes/2026/10-2x-geom-veil-restore.md.

CI run 40553185213 (breakpoint-gate on ci/geom-veil-restore at the veil commit), MEASURED:
- flip cell morph.geom:on: 48 of 48 readings pass on Chromium and WebKit (artifacts flip-cell-chromium, flip-cell-playwright-webkit, out/flip/on).
  Timed arm: Chromium 24 of 24; WebKit 21 of 24 (430x932, 640x1000, 1920x1080 at m=0; pre-existing timed-arm leave issue, follow-up).
- look report vs base, share of pixels differing by more than 12, m=1: nav region 0.07-3.1 %, columns 0.05-2.9 % (before: 57-98 % for 0<m<=1);
  the whole-page region at m=1 is still 5.6-42 % (not the veil; cause not shown, follow-up). m=0 equal. Mid-morph (m .25/.5/.75) still
  differs (nav 27-78 %, columns 10-93 %): picture scaling, task geom-image-model.
Memory: one more backed layer (veil); net 5 of 12 inside the budget at level 0 (net_lvl0_flip, net_lvl0_veil_bytes; gross mem_bands 2 of 12), all 12 at level 2.
