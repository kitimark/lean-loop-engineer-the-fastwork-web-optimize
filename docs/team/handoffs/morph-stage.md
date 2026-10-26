branch: worktree-wf_f50338a2-351-1 (CI branch ci/morph-stage)
worktree: .claude/worktrees/wf_f50338a2-351-1
last commit: see git log -1 (code at b877a0454, ci request 13b09467c). Push 1 of 3 done, no more pushes.
CI runs at 13b09467c (state when written: all running/queued):
- lean 40339107915 completed (push)
- breakpoint-gate push (default flags) 40339108228; dispatch fw=morph.stage:on both engines 40339272935
- chromium-counts push (swipe-v1, no flag) 40339108179 success; dispatches swipe-touch-v1 x3: flag 40339622735, base 40339630528 (both filed)
- results: gate push default 40339108228 success; gate fw=morph.stage:on 40339272935 FAIL (morph.mount and morph.tween anchors unmounted: count 0 vs 1; follow-up count delta in Fw.Gate.FlagDelta); Chromium base vs flag: approach noGain, end windows noData (end frame 670 vs 574). See the note.
Verified: lake build MorphStage*; Lean theorems (trackT_ge/least, progress_*, range_*, scene_held, armed_from_range_start, keyframes_end, key_eq_tween, stage_start/end_eq_tween, write_at_crossing, no_scrollTo, no_nonpassive, jack_off_iff); goldens regenerated from Lean (morph-stage, ci triggers, footprint, footprint-diff); site vitest morph.stage 41 pass; local Playwright WebKit (not a result): ?fw=morph.stage:on, ScrollTimeline present, --morph 0.93 at maxY-50, 1 at maxY, nav width 1240 (1280) and 366 (390).
Open: gate verdicts, Chromium base vs flag (Lean reader offscreen-windows-cli.mjs), WebKit Simulator lanes WAIT for wk-sim-hang (not on main at start): dispatch afterwards: pnpm -s fw run --target rewrite --fw morph.stage:on --engines webkit ... (zones 3 VMs) and the toolbar-throttle lane; user look review + T choice; no preset.
Ledger row n 90 morph.stage (look-change, L, pending). Note research/notes/2026/10-2x-morph-stage.md.
Read first: the note, then lean/Fw/Parts/MorphStage.lean.
