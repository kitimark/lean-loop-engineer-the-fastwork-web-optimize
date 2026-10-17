// N0 census events -> windows and per-frame counts. Pure functions (extraction, no decisions): the page side is
// src/n0-census.js, which stamps each event with the virtual time of the shim's clock.
//
// A virtual-time event belongs to the first frame whose frame time is >= the event time: rAF callbacks run with the
// frame time itself, and a timer due between two frames fires at the start of the next one (clock-shim advanceTo).
// Windows: load (event time < startVt), preroll (up to and including the last pre-roll frame), then one bucket per
// recorded frame, then `after` (later than the last recorded frame).
export const N0_KEYS = ['n0.events', 'n0.cssom', 'n0.sheetNode'];
const EPS = 1e-3;
const kindKey = (kind) => (kind.startsWith('cssom.') || kind === 'adoptedStyleSheets' ? 'n0.cssom' : 'n0.sheetNode');

export function n0Windows(events, frameVts, startVt, dt) {
  const win = { load: [], preroll: [], after: [] };
  const perFrame = frameVts.map(() => []);
  const lastPreroll = frameVts.length ? frameVts[0] - dt : startVt;
  const last = frameVts.length ? frameVts[frameVts.length - 1] : startVt;
  for (const e of events) {
    if (e.vt < startVt - EPS) win.load.push(e);
    else if (e.vt <= lastPreroll + EPS) win.preroll.push(e);
    else if (e.vt > last + EPS) win.after.push(e);
    else {
      let lo = 0, hi = frameVts.length - 1; // first frame with frameVts[n] >= e.vt - EPS
      while (lo < hi) { const m = (lo + hi) >> 1; if (frameVts[m] >= e.vt - EPS) hi = m; else lo = m + 1; }
      perFrame[lo].push(e);
    }
  }
  return { win, perFrame };
}

export function n0FrameCounts(list) {
  const c = { 'n0.events': list.length, 'n0.cssom': 0, 'n0.sheetNode': 0 };
  for (const e of list) c[kindKey(e.kind)]++;
  return c;
}

export function byKind(list) {
  const o = {};
  for (const e of list) o[e.kind] = (o[e.kind] ?? 0) + 1;
  return Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : 1)));
}
