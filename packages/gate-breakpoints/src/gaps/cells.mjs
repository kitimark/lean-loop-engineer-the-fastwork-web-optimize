// The 8 gap cells of Q33 and how each engine is asked to build them. Data shaping only; the pass/fail/unreachable rule
// is in judge.mjs. The probes themselves come from the Lean-generated matrix (apps/site/src/breakpoints.gen.json).
//
// Cells: block `fractional-gaps` (widths 600.5, 640.5, 860.5, 1000.5) and block `hover-pointer-cross`
// (1024x768 and 1200x900, each with (hover none, pointer fine) and (hover hover, pointer coarse)).

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
 * STAND-IN (until the Lean probes move from dpr 5/4 to dpr 2, research note 10-17-gate-gaps-fractional.md):
 * the environment the lane can build for a matrix probe. A browser makes media width = P / (DSF x zoom) with P whole, so
 * width 600.5 at dpr 5/4 (P = 750.625) cannot occur. DPR enters no condition (Lean MQ.eval_indep_height_dpr), so the
 * expected vectors do not change. A fractional width w gets zoom 2 and dpr 2 (P = 2w whole); other probes are unchanged.
 */
export function realizeEnv(p) {
  const env = {
    width: p.width, height: p.height, deviceWidth: p.deviceWidth, deviceHeight: p.deviceHeight, dpr: p.dpr,
    hover: p.hover, pointer: p.pointer, reducedMotion: p.reducedMotion, colorScheme: p.colorScheme,
  };
  if (Number.isInteger(p.width)) return env;
  if (!Number.isInteger(2 * p.width)) throw new Error(`${p.id}: width ${p.width} x zoom 2 is not whole`);
  return { ...env, dpr: 2, zoom: 2 };
}

/**
 * Mechanism per (kind, engine): what the lane does, and what the research says the engine can do.
 * `reach: 'reachable'` = the lane builds the environment and compares with Lean; `'unreachable'` = no mechanism exists
 * and the lane records the measured evidence instead (judge.mjs checks it).
 */
export const MECHANISMS = Object.freeze({
  'fractional/chromium': {
    reach: 'reachable',
    how: 'Chromium browser zoom 200% (profile Preferences partition.default_zoom_level.x = log(2)/log(1.2)) + CDP setDeviceMetricsOverride width 2N+1, DSF 1',
    page: 'media width N + 1/2; neither (width<=N) nor (width>=N+1) matches',
  },
  'fractional/playwright-webkit': {
    reach: 'unreachable',
    how: 'none: WebKit media width is an int (MediaQueryFeatures.cpp:716-728@862f17d); Playwright has no zoom, fractional DPR gives whole px',
    page: 'media width is a whole number at every DPR and zoom tried',
  },
  'cross/chromium': {
    reach: 'reachable',
    how: '--blink-settings primaryHoverType/primaryPointerType (one browser per pair)',
    page: 'the requested (hover, pointer) pair',
  },
  'cross/playwright-webkit': {
    reach: 'unreachable',
    how: 'none: every Apple WebKit derives primary hover and pointer from one platform constant (WebPageIOS.mm:4233-4246, WebPageMac.mm:762-780@862f17d); Playwright hasTouch flips both',
    page: 'primary pair is (hover, fine) or (none, coarse) only',
  },
});

/**
 * STAND-IN for Lean `webkitPrimaryPairs` (research note 10-17-gate-gaps-hover-pointer.md, to be defined and proved in
 * Fw/Site first): the (hover, pointer) pairs an Apple WebKit page can see.
 */
export const WEBKIT_PRIMARY_PAIRS = Object.freeze([['hover', 'fine'], ['none', 'coarse']]);
