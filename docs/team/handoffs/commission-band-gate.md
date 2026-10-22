branch: worktree-wf_a2056a82-d7a-1 (CI branch ci/commission-band-gate)
worktree: .claude/worktrees/wf_a2056a82-d7a-1 (under the repo root)
last commit measured: 2a74101e1 (pushed to ci/commission-band-gate); later commits only ledger, note, handoff

Design history: v1 (9997b62) skipped all writes in the band; the breakpoint gate FAILED (run 39836996121: section custom props
orig "0" vs rewrite "1" at rest; runway/title rows because the media-change handler ran a body the original does not run).
v2 (2a74101): skip only while the follower moves; write on settle, on the first ungated body, and on a media change by
writing the follower's pair without running a body. Gate v2 passes.

CI runs (2a74101 unless noted):
- lean 39843527891 success (v1 push run 39836959930 failed on init-cost lint, fixed)
- breakpoint-gate `--fw commission:band-gate` both engines: 39843552595 success (v1: 39836996121 failure)
- breakpoint-gate base (no flag, 9997b62): 39840038549 success
- chromium-counts swipe-v1 x3: base 39837044649 (9997b62, faithful path unchanged), flag v2 39843560957 (v1 39837049981)
- webkit-sim: base 39837001915 (9997b62) success; flag v2 39843567401 running; flag v1 39837008165 failed (no artifact)
MEASURED chromium window scrollY 3070-3530 (430x932, commission bottom 0.85h..0.35h, INFERRED from the class-toggle spike):
RecalcStyleCount per frame 5.02 -> 3.07, elementCount 127.3 -> 60.1, layers/tiles/Paint/Layout/FunctionCall equal.

Done: Lean `lean/Fw/Parts/CommissionOpt.lean` (look_gated, look_const_iff, inl_written/ungated/settled, exit_catchup,
media_catchup, media_look_agree, fol_cls_agree, commission_visSame, writes_orig, writes_le, moving_run, stepV_writes);
goldens `packages/contracts/golden/parts/commission-gate.jsonl`; flag `commission:band-gate`; test bandgate.test.ts.
Open: webkit flag run, ledger row n46 final + preset regenerate, note research/notes/2026/10-2x-commission-band-gate.md,
check.sh at final commit, dry land, review ready.
Outside the task writes: lean/Fw.lean, lean/Fw/Parts/Golden.lean, lean/Fw/Parts/FootprintData.lean,
packages/contracts/golden/parts/footprint.gen.json, packages/contracts/golden/preset/v2-proved.decisions.jsonl,
research/findings/ledger.json.
