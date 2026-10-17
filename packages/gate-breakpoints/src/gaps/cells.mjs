// The 8 gap cells of Q33 and how each engine is asked to build them. Data shaping only: every verdict (pass, fail,
// not-comparable, unreachable and its reason) is Lean's, through verdict.mjs (Fw.Gate.State, Fw.Gate.Reach). The probes
// come from the Lean-generated matrix (apps/site/src/breakpoints.gen.json).
//
// Cells: block `fractional-gaps` (widths 600.5, 640.5, 860.5, 1000.5 at DPR 2) and block `hover-pointer-cross`
// (1024x768 and 1200x900 at DPR 2, each with (hover none, pointer fine) and (hover hover, pointer coarse)).
import { probeEnv } from '../spec.mjs';

export const GAP_BLOCKS = Object.freeze(['fractional-gaps', 'hover-pointer-cross']);

/** The cells in matrix order: { id, block, kind, probe }. */
export function gapCells(gen) {
  return gen.matrix.probes.filter((p) => GAP_BLOCKS.includes(p.block))
    .map((p) => ({ id: p.id, block: p.block, kind: p.block === 'fractional-gaps' ? 'fractional' : 'cross', probe: p }));
}

/** The N of the four gaps (N, N+1), from the Lean-generated `fractionalGaps` (open interval [N, N+1]). */
export const gapEdges = (gen) => gen.fractionalGaps.map((g) => g.open[0]);

/** Chromium's zoom level for a zoom factor z: log(z) / log(1.2) (kPresetZoomFactor base; Chrome writes this to the profile). */
export const zoomLevel = (z) => Math.log(z) / Math.log(1.2);

/**
 * The browser setup that makes Chromium load exactly Lean's environment (width, height, device width, DPR, hover, pointer,
 * motion, scheme; nothing is rewritten). A fractional width w at DPR d is built as browser zoom d (profile preference) with
 * a CDP metrics override of w x d (whole: Lean's `widthDpr` reach condition) and DSF 1; the page then sees media width
 * w, window.devicePixelRatio d and innerHeight height. A whole width needs no zoom (zoom 1, DSF d). The result is Lean's
 * environment plus the mechanism fields `zoom` and `override`; the run record keeps Lean's as `env` and this as `realized`.
 */
export function realizeChromium(p) {
  const env = probeEnv(p);
  const zoom = Number.isInteger(p.width) ? 1 : p.dpr;
  const w = p.width * zoom, h = p.height * zoom;
  if (!Number.isInteger(w) || !Number.isInteger(h)) throw new Error(`${p.id}: override ${w}x${h} (width x zoom ${zoom}) is not whole`);
  return { ...env, zoom, override: { width: w, height: h, deviceScaleFactor: zoom > 1 ? 1 : p.dpr } };
}

/** WebKit: no mechanism changes the environment; the launcher is asked for Lean's environment as is and the page reports what it got. */
export const realizeWebkit = (p) => ({ ...probeEnv(p) });

/** What each (kind, engine) does, for the report. Display only: reachability is Lean's (Fw.Gate.Reach), not this table. */
export const HOW = Object.freeze({
  'fractional/chromium': 'Chromium browser zoom (profile Preferences partition.default_zoom_level.x = log(d)/log(1.2)) + CDP setDeviceMetricsOverride width w*d, DSF 1',
  'fractional/playwright-webkit': 'Lean environment as is (Playwright viewport = ceil(width)); WebKit media width is an int (MediaQueryFeatures.cpp:716-728@862f17d)',
  'cross/chromium': '--blink-settings primaryHoverType/primaryPointerType (one browser per pair)',
  'cross/playwright-webkit': 'Lean environment as is; WebKit derives primary hover and pointer from one platform value (WebPageIOS.mm:4233-4246, WebPageMac.mm:762-780, WebPageGLib.cpp:229-258@862f17d)',
});

/**
 * Probe-page variants for the iOS rounding path (Simulator and phone): the meta viewport asks for a fractional layout width and
 * WebKit rounds it (ViewportConfiguration::layoutWidth, ViewportConfiguration.cpp:598-631@862f17d). `vp=` sets the content
 * string; `aim=W` sets `width=device-width, initial-scale=<screen.width / W>` from a script in the page head, so the same URL
 * aims at W on any device width. The page reports the media width it got.
 */
export function probeVariants(gen) {
  const targets = gen.fractionalGaps.map((g) => g.probe);
  return [
    ...targets.map((w) => ({ id: `vp-width-${w}`, query: `vp=${encodeURIComponent(`width=${w}`)}`, aimed: w })),
    ...targets.map((w) => ({ id: `aim-${w}`, query: `aim=${w}`, aimed: w })),
  ];
}
