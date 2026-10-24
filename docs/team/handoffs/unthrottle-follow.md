# unthrottle-follow handoff

Branch: worktree-wf_4682f586-db0-1 (CI branch ci/unthrottle-follow). Worktree: .claude/worktrees/wf_4682f586-db0-1
Last commit: see `git log -1` (main merged at 95504f339; checks green at that tree: check.sh, site 7310 tests + typecheck, measure-webkit 669, runner 3463, ci-paths 56).

CI runs (ci/unthrottle-follow):
- 40109924058 (sha cf29b0739, dispatch 1 of 3) toolbar-throttle push: success (sim 1-3 + report). Arms rewrite, unthrottle, unthrottle-follow, original; 3 usable passes per arm; band runs 161 / 0 / 0 / 91; still runs per 1000 moving frames 123.7 (rewrite), 109.1 (unthrottle), 108.1 (follow), 117.8 (original). Follow = unthrottle (no gain).
- 40116376544 (sha dc1c93383, dispatch 2 of 3) toolbar-throttle push, adds a scroll-event counter to the recorder: success. Part still runs per 1000 mid-moving frames unthrottle 175.8, follow 90.5; scroll events per 1000 moving frames unthrottle 424, follow 422 (second throttle live in the Simulator).
No dispatch 3 used. Result: no steady gain on scrollY (pinned verdict); part-output gain on a post-hoc lens (INFERRED, 6 of 6 jobs); note research/notes/2026/10-2x-unthrottle-follow.md has the tables.
Wait with: pnpm -s fw ci wait --branch ci/unthrottle-follow --workflow toolbar-throttle (poll >= 120 s).
Verified (code c4d6d6f18 + regen): lean check.sh green (slot), site tests, typecheck, measure-webkit tests, runner tests (3437), ci-paths (56), plan lint clean for this task; main merged (780015dc9). Dry land: VERDICT dry unthrottle-follow (graph r436 added the writes).
Table of run 1: scratchpad/uf/run1-table.md (local, ignored; regenerate: gh run download 40109924058 -n toolbar-throttle-<1..3>, cli.mjs report).

Built: Lean model lean/Fw/Parts/EngineScrollFollow.lean (step, drive, theorems: frames_bounded, stops_after_still, idle_zero, drive_idle, moving_runs_every_update, follow_gt_event, follow_reads_newest, follow_same_look, plateau_survives, fine_never_requests), golden
packages/contracts/golden/parts/engine-scroll-follow.jsonl (EngineScrollFollowGolden.lean, check.sh job "unthrottle-follow golden check"),
site apps/site/src/parts/engine.scroll/follow.ts + follow.test.ts, variant engine.scroll:unthrottle-follow in part.json, mounted by index.tsx
(unthrottle css + follow loop), ScrollEngine.request() added in apps/site/src/engine/scroll.ts.
Lane (at cf29b0739/dc1c93383 only; main's toolbar-throttle.yml now runs parts-cli.mjs with fixed arms, so [throttle:follow] no longer exists here): message tag = drags with arms rewrite,unthrottle,unthrottle-follow,original, 1 round x 8 cycles, arm order rotated by VM;
cli.mjs --rotate, SEARCH entry; follow-report.mjs adds the moving-frame table (moving / mid-moving denominators, max step).

Gate PASSED, run 40125463870 on ci/unthrottle-follow-gate (head 8cb61aace). Open: trajectory probe/morph cell for v2-proved; look check of chasing parts.
Writes outside the graph task (dry without --allow: VERDICT scope; with --allow for them: VERDICT dry): apps/site/src/engine/scroll.ts (ScrollEngine.request), engine.scroll/index.tsx, throttle/{cli,report,recorder,follow-report}.mjs, measure-webkit test throttle-follow-report, FootprintData/FootprintRows, research/findings/ledger.json (row without n: lead assigns n); also lean/Fw.lean, check.sh, footprint(.diff).gen.json, v2-proved.decisions.jsonl (generated or wiring).
TS stand-ins: follow-report.mjs totals/ratios/max step; installFollow/windowFollowEnv glue (no decision logic).
