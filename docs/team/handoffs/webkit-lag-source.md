# Handoff: webkit-lag-source (round 2)

**State:** the note `research/notes/2026/10-20-webkit-lag-source.md` (status review) is rewritten with all 7 round-1 findings applied. Branch worktree-wf_7a7ac477-cb3-1, at this file's commit.

**Verified from source (WebKit 862f17dcae0a):**
- Mac wheel by input type: a trackpad gesture turns async after its first event (≤ 50 ms wait) unless that event is prevented; a mouse wheel is synchronous on every event (RemoteScrollingTreeMac.mm:333-395, ScrollingTree.cpp:118-150).
- Mac Safari uses RemoteLayerTree (PlatformEnableCocoa.h:817-818).
- iOS layers above 1280 CSS px are tiled (GraphicsLayerCA.cpp:100-106, 4843-4857).
- A blur radius change is a Layout diff, and Layout repaints the layer fully (RenderObjectInlines.h:87-97).
- Image draws (Q8): no cached scaled copy; a full-size synchronous decode when the drawn size grows.

**INFERRED, accepted limits:** GPU, render-server and CoreGraphics costs; per-layer areas (1440 × 900 and 390 × 844 viewports); Safari's shipped preference values; about 80 countdown face layers.

**Not run:** package tests and `lean/scripts/check.sh`, because this task changes notes only.

**Open, handed to:**
- **webkit-lag-probe:** repaint area per layer per frame (resized vs radius-changed); iPhone track tile coverage; layers created at morph start; image decodes per frame (async or sync, sized or full); wheel steps by input type, recorded per run; `pin()` scrollTo count; commit cadence.
- **image-audit:** for the 21 column images (1282px), natural vs drawn size per breakpoint and DPR, and decoded bytes (about 6.6 MB each); measure the drawn-size arm (C7) on track repaint and decode count.
- **lean-prover:** cost terms 1-13 in `Fw.Engine.WebKit`, first 1, 5, 7 and 10.
- C6 cites unlanded branch `ci/exit-scoped-inline` @071906af. Re-cite it once it lands.

**Conventions:** WC/, WK/ and WTF/ path prefixes. Files outside the sparse clone were fetched raw at the sha and are marked "(raw)".

**Read first:** the note's Answer, Q7, Q8 and per-layer table, then [10-18-engine-webkit-pipeline.md](../../../research/notes/2026/10-18-engine-webkit-pipeline.md).
