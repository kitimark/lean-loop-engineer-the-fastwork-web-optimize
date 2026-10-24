# unthrottle-follow handoff

Branch: worktree-wf_4682f586-db0-1 (CI branch ci/unthrottle-follow). Worktree: .claude/worktrees/wf_4682f586-db0-1
Last commit: see `git log -1` (code at c4d6d6f18; later commits are handoff/notes only).

CI runs: none yet (first push is the tip commit tagged [ci:toolbar-throttle] [throttle:follow]; run id below once read).

Built: Lean model lean/Fw/Parts/EngineScrollFollow.lean (step, drive, theorems: frames_bounded, stops_after_still, idle_zero, drive_idle, moving_runs_every_update, follow_gt_event, follow_reads_newest, follow_same_look, plateau_survives, fine_never_requests), golden
packages/contracts/golden/parts/engine-scroll-follow.jsonl (EngineScrollFollowGolden.lean, check.sh job "unthrottle-follow golden check"),
site apps/site/src/parts/engine.scroll/follow.ts + follow.test.ts, variant engine.scroll:unthrottle-follow in part.json, mounted by index.tsx
(unthrottle css + follow loop), ScrollEngine.request() added in apps/site/src/engine/scroll.ts.
Lane: toolbar-throttle.yml [throttle:follow] message tag = drags with arms rewrite,unthrottle,unthrottle-follow,original, 1 round x 8 cycles, arm order rotated by VM;
cli.mjs --rotate, SEARCH entry; follow-report.mjs adds the moving-frame table (moving / mid-moving denominators, max step).

Open: CI result and the note research/notes/2026/10-2x-unthrottle-follow.md; dry land; review ready.
TS stand-ins: follow-report.mjs totals/ratios/max step; installFollow/windowFollowEnv glue (no decision logic).
