// The pure parts of the Chromium path-pix driver (pathpix.mjs runs on import, so these live apart and can be tested).
// Both are copies of measure-webkit twins; test/pathpix-lane.test.mjs checks them against those and the Lean golden vectors.

/** Search of the path-only arm: only `layer` forced onto its own compositing layer (site-layer-opts: `?fwl=<layer>:c`). */
export const pathSearch = (layer) => `?fwl=${encodeURIComponent(layer).replace(/%2C/gi, ',')}:c`;

/** Lean Fw.Gate.PathPix.offsets: nine scroll offsets, i * maxY / 8 with natural-number division. */
export const laneOffsets = (maxY) => Array.from({ length: 9 }, (_, i) => Math.floor((i * maxY) / 8));
