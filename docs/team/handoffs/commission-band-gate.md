branch: worktree-wf_a2056a82-d7a-1 (CI branch ci/commission-band-gate)
worktree: .claude/worktrees/wf_a2056a82-d7a-1 (under the repo root)
state: complete; measured commit 2a74101e1; later commits are the note, ledger row 48, the merge of main and this file

Result: flag `commission:band-gate` (variant `band-gate`, T0, class E). Win on style recalculation in both engines, same
look (Lean + gate), layer budget 0. Ledger row 48 `partly-proved` (promotion to the preset is the lead's call).
Design: v1 (skip every write) failed the breakpoint gate (run 39836996121); v2 skips only while the follower moves, writes at
settle and on the first ungated body, and on a media change writes the follower's pair without a body.

CI runs: lean 39843527891 success; breakpoint-gate flag 39843552595 success (v1 39836996121 failure), base 39840038549 success;
chromium-counts swipe-v1 x3 base 39837044649, flag 39843560957 (v1 39837049981); webkit-sim base 39837001915, flag 39843567401
(v1 flag 39837008165 failed, no artifact).
MEASURED chromium window scrollY 3070-3530: RecalcStyleCount 5.02 -> 3.07, elements 127.3 -> 60.1 per frame.
MEASURED webkit y 2500-3500: RecalculateStyles 124/127 -> 99/92. Details: research/notes/2026/10-2x-commission-band-gate.md.

Land: needs `--allow lean/Fw/Parts/FootprintData.lean --allow lean/Fw/Parts/Golden.lean --allow research/findings/ledger.json`
(the dry with them ends `VERDICT dry commission-band-gate`; without them `VERDICT scope`).
Outside the task writes: lean/Fw.lean, lean/Fw/Parts/Golden.lean, lean/Fw/Parts/FootprintData.lean,
packages/contracts/golden/parts/footprint.gen.json, research/findings/ledger.json.
Open: frame-time replay of the scroll-in; unexplained WebKit saving at y 3500-4500; the commission window is INFERRED.
Read first: the note, then `CommissionOpt.lean` section "The event sequence".
