branch: worktree-wf_2a0a5c6b-863-1 (CI branch ci/platform-sweep-layer, pushed fbc6ee4ff)
worktree: .claude/worktrees/wf_2a0a5c6b-863-1
last commit: see `git log -1`
CI runs (dispatched by `pnpm -s fw run ... --ref ci/platform-sweep-layer` at fbc6ee4ff, all running at first write): chromium base 40261037706, chromium arm 40261040439 (swipe-touch-v1, 3 runs), webkit base 40261071388, webkit arm 40261059419 (3 VMs), gate 40261067591 (both engines, fw=platform.sweep:layer-sweep). Look check: premise sweep.layer-pixels pushed on ci/platform-sweep-layer-pix with [ci:premise-tests] (run id not read yet).
state: Lean PlatformSweepLayer.lean (same_look, layerX_eq, css_close, orig_repaints, layer_no_text_repaint, run_work, memory_ok), golden platform-sweep-layer.jsonl, site flag layer-sweep (kind proposal, visClass L), ledger row 85, trigger row, check.sh job. check.sh and site test not yet run at final commit.
verified: Lean files compile, site golden test green, lake test green.
Debug run (local Playwright, one word, page in scratchpad): Chromium max diff 3/255 (2/255 mostly, 6 at one edge pixel), WebKit 8/255, only when the parent has no will-change (with will-change on the parent Chromium differed by up to 93 on edge pixels: the composited parent snaps its origin).
open: counts per engine and zone, gate verdict, look check (frame hashes at fixed times on CI), note research/notes/2026/10-2x-platform-sweep-layer.md, ledger update, dry land, review ready.
