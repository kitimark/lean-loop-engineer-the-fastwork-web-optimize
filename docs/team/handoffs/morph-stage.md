branch: worktree-wf_f50338a2-351-1 (CI branch ci/morph-stage)
worktree: .claude/worktrees/wf_f50338a2-351-1
last commit: 8324e9f89 (main merged incl. wk-loop-freeze) + handoff commit after
Round 3 CI: push 4 = 8324e9f89; webkit-sim flag fw=morph.stage:on run 40429988675 (running, 3 VMs); base 40366306645 (3 VMs, older harness). Earlier: gate 40366243322 SUCCESS, chromium flag 40366262655 / base 40366273179.
Round 3 step 1 finding: flag run 40366323523 loss is runner-side. r1 log: event loop blocked 41 s with host calls [] at 22:48:38, simctl openurl ETIMEDOUT, 'no tab after 60-115 s' (page never attached, so the flag page could not have run), warm-up evaluate timeout; r2/r3 cancelled at the 58 min limit. The base run shows the same signature (r3: warm-up evaluate timeout, tick 273 s late, host calls []). Not page-side; no local reproduction needed.
State 02:12Z: run 40429988675 job r1 cancelled (58 min limit again), r2 running, r3 queued; logs readable only after the run ends.
Open: read zones from 40429988675 with offscreen-webkit-cli.mjs vs base 40366306645, minVms 3.
---
branch: worktree-wf_f50338a2-351-1 (CI branch ci/morph-stage)
worktree: .claude/worktrees/wf_f50338a2-351-1
last commit: see git log -1. Pushes: 13b09467c (1), 808fffbdc (2, no lane markers), toolbar push (3, last).
CI runs at 8f2f726bf (push 3): gate fw=morph.stage:on 40366243322 SUCCESS (excused only target/scroller count items of morph.mount/tween, 196 each Chromium, 188 each WebKit); chromium-counts swipe-touch-v1 base 40366273179 and flag 40366262655 filed (windows read: approach noGain; end 0-19, 20-59, 60-119, 120+, finish all gain); webkit-sim (zones UNDECIDED, minVms 3: base 3 VMs after reruns, flag 0 with a result; flag reruns queued) dispatches base 40366306645 (flag-less) and flag 40366323523 still in macOS queue after 3 h with cancelled/failed VM jobs (reruns queue); toolbar-throttle push run 40365940148 same (3 sim jobs, 2 cancelled so far). Read with offscreen-webkit-cli.mjs (--arm base=dirs --arm stage=dirs) and toolbar-cli report.
Round 1 notes: round 1 (13b09467c): gate flag run 40339272935 FAIL (anchors unmounted), chromium base/flag 40339630528 / 40339622735 (old tail, end windows noData).
Round 2 state: main merged; Lean ReplacedPart entries stage-mount/stage-tween (premise Fw.Parts.MorphStage.stage_unmounts_anchors, anchors morph-mount and morph-tween); flag-delta.jsonl, triggers, footprint-diff regenerated; flag-delta.test.mjs pin updated; toolbar lane arm `stage` added (measure-webkit toolbar.mjs, test). check.sh green at 1b9a5902e.
Open: gate rerun with fw=morph.stage:on; Chromium base vs flag 3 runs each with the new tail, read with offscreen-windows-cli.mjs and minFrames 34/20/40/60/20/174; webkit-sim zones minVms 3; toolbar lane stage arm; T and class L in note and ledger; user look review (class L, never a preset).
Read first: research/notes/2026/10-2x-morph-stage.md, lean/Fw/Parts/MorphStage.lean, lean/Fw/Gate/Replaced.lean.
Final state: toolbar stage arm 0 usable passes (restartFailed), undecided; T 696 px (1280x800) / 768 px (390x844), class L, no preset. Round 2 ended at commit see git log; ledger row n 90 and the note hold the same.
Toolbar arm files (toolbar.mjs and its test) are at CI commit 8f2f726bf only; reverted at the tip because they are outside the task writes (dry scope refusal).
