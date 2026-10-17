// Code that runs inside the page for the gaps lane. Self-contained functions (serialised with toString(), like page.mjs).
// The page only reports what it sees; every decision is in judge.mjs. Reports: the exact media width (bisection on the
// strict `(width > Xpx)`, which has no comparison slack), the window sizes, the gap queries around each edge, and the
// 15 pointer queries.

/**
 * arg: { edges: number[] }  (the N of the gap edges, e.g. 600, 640, 860, 1000)
 * Returns raw facts. `mediaWidth` is the bisected media width on the 1/64 grid (exact for every width the lane builds:
 * Chromium P/z with z in {1, 2}, WebKit whole numbers); an `error` field if the query never flips inside [0, 8192].
 */
export function gapFacts(arg) {
  const mm = (q) => { try { return window.matchMedia(q).matches; } catch { return null; } };
  let lo = 0, hi = 8192;
  if (!mm(`(width > ${lo}px)`) || mm(`(width > ${hi}px)`)) return { error: 'width outside [0, 8192]' };
  for (let i = 0; i < 48; i++) {
    const mid = (lo + hi) / 2;
    if (mm(`(width > ${mid}px)`)) lo = mid; else hi = mid;
  }
  // WebKit turns the query length into a LayoutUnit (1/64 px) before comparing, so the flip point of the bisection is only
  // known to 1/64: report the nearest multiple of 1/64 (exact for 600.5, and for every whole width).
  const mediaWidth = Math.round(hi * 64) / 64;
  const vv = window.visualViewport;
  const edges = {};
  for (const n of arg.edges) {
    edges[n] = {
      le: mm(`(width<=${n}px)`), ge1: mm(`(width>=${n + 1}px)`),
      maxWidth: mm(`(max-width: ${n}px)`), minWidth1: mm(`(min-width: ${n + 1}px)`),
    };
  }
  const pointer = {
    hover: mm('(hover: hover)'), hoverNone: mm('(hover: none)'),
    pointerFine: mm('(pointer: fine)'), pointerCoarse: mm('(pointer: coarse)'), pointerNone: mm('(pointer: none)'),
    anyHoverHover: mm('(any-hover: hover)'), anyHoverNone: mm('(any-hover: none)'),
    anyPointerFine: mm('(any-pointer: fine)'), anyPointerCoarse: mm('(any-pointer: coarse)'), anyPointerNone: mm('(any-pointer: none)'),
    noneFine: mm('(hover: none) and (pointer: fine)'), hoverCoarse: mm('(hover: hover) and (pointer: coarse)'),
    noneCoarse: mm('(hover: none) and (pointer: coarse)'), hoverFine: mm('(hover: hover) and (pointer: fine)'),
    touchArm: mm('(hover: none) and (pointer: coarse) and (width<=1200px)'),
  };
  return {
    mediaWidth,
    innerWidth: window.innerWidth, innerHeight: window.innerHeight,
    clientWidth: document.documentElement.clientWidth,
    vvWidth: vv ? Math.round(vv.width * 64) / 64 : null,
    screenWidth: window.screen.width, dpr: window.devicePixelRatio,
    edges, pointer,
  };
}
