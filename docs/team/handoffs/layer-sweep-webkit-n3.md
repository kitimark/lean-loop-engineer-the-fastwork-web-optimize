branch: worktree-wf_84149416-e5b-1 | worktree: .claude/worktrees/wf_84149416-e5b-1 | last commit: see git log (handoff commits) | CI branch: ci/layer-sweep-webkit-n3 @9493a5ddb (push 1 of 2 used; dispatches need no push)
CI runs (webkit-sim via `pnpm -s fw run --target rewrite --engines webkit --ref ci/layer-sweep-webkit-n3 --runs 3 --no-route [--fw platform.sweep:layer-sweep]`; --no-route because the Codemagic cell has no app id):
- round 1 base 40277969074: FAILED jobs r1 (stalled 728 s at pass 2/2, partial pass-1 kept), r2 (exit 124, partial pass-1 kept), r3 ok (2 passes)
- round 1 arm  40277972324: FAILED jobs r2 (inspector dead, exit 4, no pass), r3 (same, no pass), r1 ok (2 passes)
- round 2 base 40284460392 (nonce fdf54228958bda64): running (dispatched 07:13Z)
- round 2 arm  40284464262 (nonce 62d84c03b9639537): running
verified: Chromium t=0 trace done (note once written): original path background_image_geometry.cc:392-401,754, box_painter_base.cc:1492-1497,1569-1597; layer path paint_property_tree_builder.cc:728-808 + compositing_reasons.h:116. Column pixel values stay INFERRED.
harness evidence (all 6 round-1 jobs): first warm-up Runtime.evaluate times out at 120 s, reconnect finds "no page target", runner host load1 811-937 and "event loop blocked 30 s tick came 165-392 s late" (logs in scratchpad n3/job-*.log, artifacts webkit-sim-r<k> keep .pass-N.part).
open: read all rounds with packages/measure-webkit/src/offscreen-webkit-cli.mjs (VM dirs copied under unique webkit-sim-r<k> names); note + ledger webkit field; ledger tests; dry land; review ready.
read first: research/notes/2026/10-2x-platform-sweep-layer.md, docs/team/handoffs/platform-sweep-layer.md
