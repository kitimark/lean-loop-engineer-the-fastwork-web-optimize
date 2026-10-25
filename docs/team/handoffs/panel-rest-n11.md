Branch: worktree-wf_8a06f29a-d26-1 (CI branch ci/panel-rest-n11, pushed once at ab3b3248f; no further push)
Worktree: .claude/worktrees/wf_8a06f29a-d26-1 (under the main checkout)
Last commit: see `git log -1` (verdict note and this handoff, on top of d1af634d5).
CI runs, all complete: lean 40174060322 success; WebKit Simulator base 40174475566 and flag 40174472900 (3 VMs each); Chromium swipe-touch-v1 base 40174480097 and flag 40174482844 (3 runs each); gate 40179231272 passed (both engines; 40174477871 failed only on the intended `filter blur(0px) -> none`, now excused by `Fw.Gate.FlagDelta`).

Verdict (research/notes/2026/10-2x-panel-rest-n11.md, section "Per-engine verdict"): the flag stays a CURATED EXCLUSION, `Fw.Preset.Gen` unchanged.
* Chromium = trade. Lean cells: Paint WIN (y04500 -46 deterministic; <= in y05000 and finish), tiles and drawing area WIN; PrePaint, invalidation area/rects, RasterTask, Layout.dirtyObjects COST. Toggle frame 575 (y 5342): PrePaint 32 vs 6, Paint 109 vs 88, RasterTask 57 vs 11; no layout change on any frame.
* WebKit: Lean engineCheck has no WebKit lane. Cells classify: only Composite is certified (equal); Paint/Layout/RecalculateStyles quarantined in both arms. Raw Paint is x2.4 in z10/finish (6 of 6 flag passes above 6 of 6 base). Memory WIN -21.19 MB at finish (deterministic), -28.15 MB at 4500 (not certifiable), layers -1 inside noise. Flag VMs ran 30-40% higher on probe `loadCenti`.
* So "WebKit win with memory-only cost" does not hold: the cost is Paint, not memory.

Open (follow-ups, accepted limits): interleaved WebKit rerun for a Paint class, then correct `wk_toggle_eqv` in MorphPanelOpt.lean; fractional-edge premise in Lean; Chromium run-level mixed theorem; toggle-in-layout-frame decision (moot as stated: toggle frame has no layout). The per-zone verdict was computed with scratch glue (fwcore classify + engineCheck over frame slices); no code committed.
Shipped: flag `morph.panel:rest` (rest.logic.ts setRest from morph.tween driver updateFade; Lean MorphPanelRest.lean; golden morph.panel.rest.jsonl; check.sh job; trigger row). RG10: 54 abs / 0 fixed descendants. Pixel check: only 721 px width differs beyond noise.
Conventions: FootprintRows.lean and footprint-diff.gen.json come from `lake env lean --run scripts/ContractsGolden.lean --rows|--diff`.
Dry land at the merge of main (cd97fbc5e): VERDICT dry panel-rest-n11. check.sh green, runner tests 3533 pass, ci-paths test 56 pass, plan lint 0 errors.
Read first: research/notes/2026/10-2x-panel-rest-n11.md.
