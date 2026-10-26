branch: worktree-wf_84149416-e5b-1 | worktree: .claude/worktrees/wf_84149416-e5b-1 | last commit: 25b819db2 (+ this handoff) | CI branch: ci/layer-sweep-webkit-n3 @9493a5ddb (push 1 of 2 done)
CI runs (webkit-sim, dispatched by `pnpm -s fw run --target rewrite --engines webkit --ref ci/layer-sweep-webkit-n3 --runs 3 [--fw platform.sweep:layer-sweep]`, 3 VMs each, created 06:07Z):
- base 40277969074 (nonce 0e18c3cc85e79f10): running
- arm  40277972324 (nonce 4433a4d2669a9463, fw platform.sweep:layer-sweep): running
verified: Chromium t=0 trace done in my head (cited in the note once written): original path background_image_geometry.cc:392-401,754, box_painter_base.cc:1569-1597 (mask_rect and dest rect pixel-snapped); layer path paint_property_tree_builder.cc:728-808 + compositing_reasons.h:116 (will-change: transform drops subpixel accumulation). Column pixel values stay INFERRED.
open: read both runs with packages/measure-webkit/src/offscreen-webkit-cli.mjs; note + ledger webkit field; ledger tests; dry land; review ready.
read first: research/notes/2026/10-2x-platform-sweep-layer.md, docs/team/handoffs/platform-sweep-layer.md
