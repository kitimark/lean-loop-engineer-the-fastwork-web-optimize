# geom-image-model handoff (round 2: negative result)
Branch: worktree-wf_ade92fb6-57c-1. Worktree: .claude/worktrees/wf_ade92fb6-57c-1. CI branch ci/geom-image-model (1 push used in round 2). Last code commit a64179d20.
CI: breakpoint-gate 40608711529 success (flip cell 48/48 both engines, verify A3a/A4/A5 pass), lean 40608711677 success. Baseline main run 40599995604.
Verified: check.sh green, @fw/site, gate-breakpoints, premise-tests tests green, footprint --check ok; goldens regenerated from Lean after merge.
Result: picture rows shrink ~30 % at m in .25-.75 (both engines) but m=1 rises 17429 > 342419 (Chromium), 850 > 333261 (WebKit): lower column pictures absent in the flip arm; 641x700 footprint moved, not gone. Negative result, park, do not land.
Open: find why pictures vanish at m=1 (unloaded at enter: naturalWidth 0 fallback, or Kc clip padding 64 px); see diff PNGs in artifact flip-cell-chromium img/640x1000/m1.
Read first: research/notes/2026/10-2x-geom-image-model.md (Round 2 section).
