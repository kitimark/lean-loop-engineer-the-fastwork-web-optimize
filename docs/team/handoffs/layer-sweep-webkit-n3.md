branch: worktree-wf_84149416-e5b-1 | worktree: .claude/worktrees/wf_84149416-e5b-1 | last commit: 9493a5ddb (+ this handoff) | CI branch: ci/layer-sweep-webkit-n3 @9493a5ddb (push 1 of 2 done)
CI runs: (dispatching) webkit-sim base 3 VMs and webkit-sim --fw platform.sweep:layer-sweep 3 VMs via `pnpm -s fw run --target rewrite --engines webkit --ref ci/layer-sweep-webkit-n3 --runs 3 [--fw platform.sweep:layer-sweep]`; run ids below once printed.
verified: nothing yet (dry plans: base key 6f9f3ffe45f8, arm key 5777dec336e4, both cache miss, vms=3).
open: read both with packages/measure-webkit/src/offscreen-webkit-cli.mjs; trace Chromium t=0 x=526 to background_image_geometry.cc; update note + ledger webkit field; ledger tests; dry land.
read first: research/notes/2026/10-2x-platform-sweep-layer.md, docs/team/handoffs/platform-sweep-layer.md
