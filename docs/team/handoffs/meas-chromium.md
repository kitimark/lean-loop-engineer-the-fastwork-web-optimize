# Handoff: meas-chromium (Chromium counts lane)

State at e01f9e5 (written by the lead from meas-chromium's report). Read packages/measure-chromium/README.md first.

- Linux container (Dockerfile, headless-shell) with BeginFrameControl, a clock shim and native rAF scheduling. The
  rAF callback *timestamp* is the virtual frame time: the native value uses another clock with a per-run origin, and
  mixing the two ended animations early (2,040 vs 2,459 callbacks). Profile `profiles/swipe-v1.json`: 503 frames,
  about 85 s per run; the first image build takes about 2 min.
- Commands: `pnpm --filter @fw/measure-chromium count -- --profile swipe-v1 --label a`; `… determinism` (two runs +
  compare). Output is raw per-frame counts `fw.counts/1` in out/ (gitignored). No decision logic in TS.
- Determinism over 3 runs (not byte-identical overall):
  - **Deterministic:** hasDamage, RecalcStyle, UpdateLayoutTree count, FireAnimationFrame, rAF requests,
    FunctionCall, EventDispatch, IO/RO, PaintImage, Animation.*, cc Activate/Commit/Draw, Layerize, ScrollLayer,
    ImageDecodeTask, …
  - **Stable:** 1–4 of 503 frames shift by one; totals within about 3. Covers LayoutCount/Layout sums, PrePaint,
    Paint, UpdateLayer, RasterTask, SynchronizeTrees, elementCount (≤ 24 of 48,300).
  - **Quarantined:** HitTest (98–119 frames differ by 1); GC-bound Nodes, LayoutObjects, Documents, Frames,
    Layer.deleted, Minor/MajorGC.
- Findings: `Network.enable` hangs beginFrame at navigation commit (in-flight requests are counted server-side); a
  100 ms real-time barrier after each frame removes the image-decode/raster shifts.
- Pure TS: `zoneSums` (src/reduce.mjs) needs a Lean spec + goldens (seed vectors in test/pure.test.mjs).
  trace.mjs is extraction only; compare.mjs is a self-check, not a verdict.
- Gaps: software raster only; programmatic scrollTo instead of touch input (hover recompute adds HitTest noise); no
  raster-invalidation rects or layer census; apt versions not pinned.
