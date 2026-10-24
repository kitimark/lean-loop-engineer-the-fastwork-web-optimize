# Handoff: sweep-offscreen-pause
Branch: worktree-wf_72c42085-d84-1 (ci branch ci/sweep-offscreen-pause). Worktree: .claude/worktrees/wf_72c42085-d84-1.
Last commit: see git log (work commit f81536c0b, then merge of main). CI runs: none yet (filled after the first push).
Verified: Lean PlatformSweepPause.lean compiles (shown_same, visible_same, visible_phase, reported_no_tick, reported_run,
offscreen_ticks_le_one under the named premise Lag); golden platform-sweep-pause.jsonl --check ok; site vitest 6575 pass, tsc clean.
Open: CI runs; Fw.lean import and check.sh line (lead); offscreen rendering-update counts have no CI lane for the rewrite.
