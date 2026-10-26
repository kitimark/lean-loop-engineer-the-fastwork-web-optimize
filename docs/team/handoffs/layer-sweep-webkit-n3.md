branch: worktree-wf_84149416-e5b-1 | worktree: .claude/worktrees/wf_84149416-e5b-1 | last commit: see git log (handoff commits) | CI branch: ci/layer-sweep-webkit-n3 @9493a5ddb (push 1 of 2 used; dispatches need no push)
State: all four CI runs finished; WebKit stays UNDECIDED in every zone (minVms 3). Note, ledger row and notes entry are updated; dry land and review ready are the last steps.
CI runs (webkit-sim via `pnpm -s fw run --target rewrite --engines webkit --ref ci/layer-sweep-webkit-n3 --runs 3 --no-route [--fw platform.sweep:layer-sweep]`; --no-route because the Codemagic cell has no app id):
- round 1 base 40277969074: jobs r1, r2 lost (partial pass-1 kept), r3 ok
- round 1 arm  40277972324: jobs r2, r3 lost (no pass), r1 ok
- round 2 base 40284460392: jobs r2, r3 lost, r1 ok
- round 2 arm  40284464262: jobs r1, r2, r3 lost (r1 kept pass 1)
Result: 9 of 12 VM jobs lost. Complete sessions: base 2 VMs, arm 1 VM. With kept passes: base 5, arm 2. Reader packages/measure-webkit/src/offscreen-webkit-cli.mjs, zones z4500, z5000, finish, whole: all undecided.
Harness cause (INFERRED): first Runtime.evaluate times out at 120 s, reconnect finds no page target, host load average 157-970 on 3 CPUs; round-2 jobs queued 50-120 min. No variant effect. Follow-up: abort a VM early when its first warm-up times out.
Chromium t=0 x=526: original path CONFIRMED (background_image_geometry.cc:392-401,754; box_painter_base.cc:1492-1497,1569); variant path CONFIRMED (compositing_reasons.h:116; paint_property_tree_builder.cc:731-790); column pixel mechanism INFERRED (will-change:auto probe still gave 33). "Layer path not snapped" claim dropped.
verified: ledger tests (apps/runner ledger-merge, premises, land-inputs) pass; JSON parses.
open: merge main, plan lint, package tests, ci-paths test, dry land, review ready. Scratch (n3 build.mjs, VM dirs, reader outputs) is in the session scratchpad, not committed.
read first: research/notes/2026/10-2x-platform-sweep-layer.md (section "WebKit re-run at one commit" and "Look check"), docs/team/handoffs/platform-sweep-layer.md
