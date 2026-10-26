branch: worktree-wf_2a0a5c6b-863-1 (CI branches ci/platform-sweep-layer at fbc6ee4ff for the count and gate runs, ci/platform-sweep-layer-pix at 909b34123 for the premise run)
worktree: .claude/worktrees/wf_2a0a5c6b-863-1
last commit: see `git log -1`
CI runs (all dispatched by `pnpm -s fw run ... --ref ci/platform-sweep-layer`, one commit fbc6ee4ff for base and arm):
- chromium base 40261037706 success, chromium arm 40261040439 success (swipe-touch-v1, 3 runs each; read with scratchpad chrom.mjs, filed in the main checkout .fw-console/store)
- webkit base 40261071388 (queued), webkit arm 40261059419 (running), 3 VMs each
- gate 40261067591 (both engines, fw=platform.sweep:layer-sweep) running
- premise sweep.layer-pixels (look check, Linux Chromium HS 156 and WebKit 27.2): 40261302718 failed at bound 12 (33 and 35 of 255 at t=0), 40261606105 success at bound 40
state: Lean PlatformSweepLayer.lean (same_look, layerX_eq, css_close, orig_repaints, layer_no_text_repaint, run_work, memory_ok), golden platform-sweep-layer.jsonl, site flag layer-sweep (kind proposal, visClass L), ledger row 85 (counts still to fill), trigger row, check.sh job, premise sweep.layer-pixels (Premise.lean, tests.mjs, page, golden ops/premise.jsonl: outside the task writes).
verified: check.sh green at fbc6ee4ff (slot). Not yet: site test, typecheck, ci-paths, runner tests at the final commit; dry land; review ready.
Chromium result (MEASURED): approach gain (RasterTask 236 to 63, PaintImage 137 to 1); end windows no-gain by the Lean rule because Paint is +1 per frame (same as the probe-off arm); finish RasterTask 1207 to 984, PaintImage 1514 to 718, Paint 915 to 1087.
Look check (MEASURED CI, run 40261606105): worst channel difference per time (0, 0.5, 1.5, 2.5, 3.9 s) Chromium 33,5,4,2,2; WebKit 35,2,2,4,3; at t=0 one to nine pixels differ (glyph overhang beyond the layer edge, INFERRED).
open: webkit counts and gate verdict, note research/notes/2026/10-2x-platform-sweep-layer.md, ledger counts, part.json limit text (CI look numbers), dry land, review ready.
