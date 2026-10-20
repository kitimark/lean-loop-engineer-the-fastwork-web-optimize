# Handoff: webkit-lag-source (round 3, final design round)

**State:** the note `research/notes/2026/10-20-webkit-lag-source.md` (status review) has fix items 1-8 of the round-3 design applied inside its existing sections. Branch worktree-wf_7a7ac477-cb3-1, at this file's commit; main is merged.

**Verified:**
- Column images (MEASURED, `sips` on the `snapshot/site/selling/` files that morph.columns/data.ts:14-18 names): 5 role PNGs are 1282 × 1282 or 1282 × 1281, and the other 16 are 341-960 × 270-1042. Decoded (Σ w·h·4): 61.66 MB desktop (21), 30.07 MB phone (13 painted; the 8 in hidden columns load eager, not painted).
- Scale ratios natural/drawn = 1/max(dW/nW, dH/nH) at the end state (INFERRED, track width from CSS): Mac 2x, 286.8 CSS px track: 0.38-2.24, 9 of 21 upscaled. iPhone 3x, 124.0 CSS px track: 0.25-1.91.
- Sync full-size decode only for images whose natural size exceeds the first-painted size and whose drawn size grows (width-dominated). End state: none on the phone; 5 width-dominated on Mac.
- Phone geometry from nav.module.css:251-257: nav and panel 366 × 820 (2.70 Mpx at 3x), tracks ≤ 4.80 Mpx, total ≤ about 10.2 Mpx.
- Latching (C3, Q7, term 10): ScrollingTree.cpp:136, 144-148; ScrollingTreeLatchingController.cpp:59-73, 91-128; PlatformWheelEvent.h:221-229 (raw).
- Earn button transitions restart every frame (Styleable.cpp:742-758); compositing path INFERRED (RenderLayerCompositor.cpp:3842-3853 vs RenderLayerFilters.cpp:160-235).

**Differs from the round-3 spec (my recompute wins):** Mac max ratio is 2.24, not 2.23 (track 286.78, not rounded to 287). Phone tracks are 124.0 · 4300 · 9 = 4.80 Mpx, not 4.85, so the total is about 10.2, not 10.3. The no-DOM AsyncScrolling return is ScrollingTree.cpp:136, not :135.

**Not run:** lean/scripts/check.sh and package tests, because only notes changed. The ci-paths and land-inputs tests were run.

**Open, handed to:**
- **image-audit (pending, no note yet):** per-image drawn size per breakpoint and DPR, which images get a full-size sync decode (Mac candidates: work-a, architect, work-e, service-kitchen, avatar-cat), waste ranking, and the C7 arm.
- **webkit-lag-probe:** repaint area per layer, layers created at morph start, decodes per frame, wheel steps by input type, and a C3 latching probe case.
- **lean-prover:** cost terms 1-13 in `Fw.Engine.WebKit` and the C3 arm decision (L8).
- C6 cites unlanded branch `ci/exit-scoped-inline` @071906af.

**Read first:** the note's Answer, Images section and per-layer table.
