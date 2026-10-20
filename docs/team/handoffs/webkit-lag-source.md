# Handoff: webkit-lag-source (round 2)

**State:** the note `research/notes/2026/10-20-webkit-lag-source.md` (status review) is rewritten with all 7 round-1 findings applied. The branch is worktree-wf_7a7ac477-cb3-1; the commit is the one this file lands in.

**Verified from source (WebKit 862f17dcae0a):**
- The Mac wheel path depends on the input type.
  - Trackpad: the gesture turns async after its first event (≤ 50 ms wait) unless that event is prevented.
  - Mouse wheel: synchronous on every event.
  - Citations: RemoteScrollingTreeMac.mm:333-395 and ScrollingTree.cpp:118-150.
- Mac Safari uses RemoteLayerTree (PlatformEnableCocoa.h:817-818).
- iOS layers above 1280 CSS px are tiled (GraphicsLayerCA.cpp:100-106, 4843-4857).
- A blur radius change is a Layout diff, and Layout repaints the layer fully (RenderObjectInlines.h:87-97).
- The image draw path is in the note's Q8. WebKit does not cache a scaled copy. When the drawn size grows, the image gets a full-size synchronous decode.

**INFERRED, accepted limits:** GPU, render-server and CoreGraphics costs; the per-layer areas, which assume 1440 × 900 and 390 × 844 viewports; Safari's shipped preference values; the count of about 80 countdown face layers.

**Not run:** package tests and `lean/scripts/check.sh`. This task changes notes only, with no package or Lean changes.

**Open, handed to:**
- **webkit-lag-probe:**
  - repaint area per layer per frame, split resized vs radius-changed;
  - tile coverage for the iPhone tracks;
  - layers created at morph start;
  - image decodes per frame (async or sync, sized or full);
  - wheel processing steps split by trackpad and mouse wheel, with the input type recorded per run;
  - `pin()` scrollTo count;
  - commit cadence.
- **image-audit:**
  - for the 21 column images (1282px): natural vs drawn size per breakpoint and DPR;
  - decoded bytes, about 6.6 MB each;
  - the drawn-size arm (C7) measured on track repaint and decode count.
- **lean-prover:** cost terms 1-13 in `Fw.Engine.WebKit`. Do 1, 5, 7 and 10 first.
- C6 cites branch `ci/exit-scoped-inline` @071906af, which is not landed. Re-cite it once it lands.

**Conventions:** the note uses WC/, WK/ and WTF/ path prefixes. Files outside the sparse clone were fetched raw at the sha and are marked "(raw)".

**Read first:** the note's Answer section, Q7, Q8 and the per-layer table, then [10-18-engine-webkit-pipeline.md](../../../research/notes/2026/10-18-engine-webkit-pipeline.md).
