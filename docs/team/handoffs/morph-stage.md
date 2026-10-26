branch: worktree-wf_f50338a2-351-1 (CI branch ci/morph-stage)
worktree: .claude/worktrees/wf_f50338a2-351-1
last commit: see git log -1. Pushes: 13b09467c (1), 808fffbdc (2, no lane markers), toolbar push (3, last).
CI runs (state when written): none of round 2 filed yet; round 1 (13b09467c): gate flag run 40339272935 FAIL (anchors unmounted), chromium base/flag 40339630528 / 40339622735 (old tail, end windows noData).
Round 2 state: main merged; Lean ReplacedPart entries stage-mount/stage-tween (premise Fw.Parts.MorphStage.stage_unmounts_anchors, anchors morph-mount and morph-tween); flag-delta.jsonl, triggers, footprint-diff regenerated; flag-delta.test.mjs pin updated; toolbar lane arm `stage` added (measure-webkit toolbar.mjs, test). check.sh green at 1b9a5902e.
Open: gate rerun with fw=morph.stage:on; Chromium base vs flag 3 runs each with the new tail, read with offscreen-windows-cli.mjs and minFrames 34/20/40/60/20/174; webkit-sim zones minVms 3; toolbar lane stage arm; T and class L in note and ledger; user look review (class L, never a preset).
Read first: research/notes/2026/10-2x-morph-stage.md, lean/Fw/Parts/MorphStage.lean, lean/Fw/Gate/Replaced.lean.
