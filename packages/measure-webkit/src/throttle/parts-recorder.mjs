// Page-side recorder of the per-part throttle measure (I/O glue, no decision): one more native requestAnimationFrame callback per frame
// next to the hero recorder (recorder.mjs) or the finish recorder (finish-page.mjs). It stores the frame time, scrollY and the visual
// viewport height (tenth px) and, for every series in SERIES, the inline custom property the part writes (per mille, as device-record.mjs
// reads it). Recording starts at the first scroll event; the fetch returns the frames up to the last frame in which scrollY or any value
// changed. Lean (via parts.mjs, golden-checked) does every reduction afterwards.
import { PART_PROPS } from '../device-record.mjs';

/**
 * The part series the page can show as a number: the inline custom property each part writes. `part` is the id of the part in the Lean
 * golden (throttle-parts.jsonl). Parts not listed here write a class, a transform or a compositor value: the recorder stores nothing
 * for them (parts.mjs names each one no-data).
 */
export const SERIES = Object.freeze([
  { key: 'hero', part: 'hero.exit', prop: PART_PROPS.hero, golden: 'hero' },
  { key: 'people', part: 'people.card', prop: PART_PROPS.people, golden: 'people' },
  { key: 'commissionEnter', part: 'commission', prop: '--commission-enter-shrink', golden: null },
  { key: 'commission', part: 'commission', prop: '--commission-shrink', golden: null },
  { key: 'platform', part: 'platform.shrink', prop: '--platform-shrink', golden: null },
  { key: 'fade', part: 'morph.panel', prop: PART_PROPS.fade, golden: 'fade' },
]);

/** The anchor of a rest pass per round (0-based, cycling): the property whose ramp the drags are placed on. */
export const ANCHORS = Object.freeze(['people', 'commissionEnter', 'platform']);

const SERIES_JSON = JSON.stringify(SERIES.map((s) => ({ key: s.key, prop: s.prop })));

export const START_JS = `(() => {
  const series = ${SERIES_JSON};
  const st = window.__fwParts = { t: [], y: [], vh: [], v: {}, found: {}, armed: false, stop: false, lastMove: -1, start: null };
  for (const s of series) { st.v[s.key] = []; st.found[s.key] = false; }
  const vv = typeof visualViewport !== 'undefined' ? visualViewport : null;
  st.start = { vh: vv ? vv.height : innerHeight, y: scrollY, scale: vv ? vv.scale : 1 };
  addEventListener('scroll', () => { st.armed = true; }, { passive: true, once: true, capture: true });
  const els = {}, last = {};
  for (const s of series) last[s.key] = 0;
  const read = (s) => {
    let el = els[s.key];
    if (!el || !el.isConnected) el = els[s.key] = document.querySelector('[style*="' + s.prop + '"]');
    if (!el) return last[s.key];
    const v = parseFloat(el.style.getPropertyValue(s.prop));
    if (!Number.isNaN(v)) { last[s.key] = Math.round(Math.min(1, Math.max(0, v)) * 1000); st.found[s.key] = true; }
    return last[s.key];
  };
  let prevY = null;
  const prevV = {};
  const f = (ts) => {
    if (st.stop) return;
    if (st.armed || scrollY !== st.start.y) {
      st.armed = true;
      const y = Math.round(scrollY * 10);
      let changed = prevY !== null && y !== prevY;
      prevY = y;
      st.t.push(Math.round(ts * 100) / 100); st.y.push(y); st.vh.push(Math.round((vv ? vv.height : innerHeight) * 10));
      for (const s of series) {
        const v = read(s);
        if (s.key in prevV && prevV[s.key] !== v) changed = true;
        prevV[s.key] = v;
        st.v[s.key].push(v);
      }
      if (changed) st.lastMove = st.t.length - 1;
    }
    requestAnimationFrame(f);
  };
  requestAnimationFrame(f);
  return 'started';
})()`;

/** Stop and return the record as a JSON string: frames [0, lastMove], the start state, which series were found. */
export const FETCH_JS = `(() => {
  const st = window.__fwParts;
  if (!st) return JSON.stringify({ err: 'parts recorder not started' });
  st.stop = true;
  const n = st.lastMove + 1;
  const v = {};
  for (const k of Object.keys(st.v)) v[k] = st.v[k].slice(0, n);
  return JSON.stringify({ start: st.start, found: st.found, frames: n, t: st.t.slice(0, n), y: st.y.slice(0, n), vh: st.vh.slice(0, n), v, total: st.t.length });
})()`;

/**
 * Scan the page from the top in steps of `stepPx` (instant scrolls, two frames each) and return, for every series, the first scrollY at
 * which its value is strictly between 0.02 and 0.98 (the ramp start), or null when it never is or the property is never written.
 * Runs in an async page expression (c.runAsync). It leaves the page at the top.
 */
export const discoverJs = (stepPx = 40) => `(async () => {
  const series = ${SERIES_JSON};
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const maxY = document.documentElement.scrollHeight - innerHeight;
  const at = {};
  for (const s of series) at[s.key] = null;
  for (let y = 0; y <= maxY; y += ${Number(stepPx)}) {
    scrollTo({ top: y, behavior: 'instant' });
    await raf(); await raf();
    for (const s of series) {
      if (at[s.key] !== null) continue;
      const el = document.querySelector('[style*="' + s.prop + '"]');
      const v = el ? parseFloat(el.style.getPropertyValue(s.prop)) : NaN;
      if (!Number.isNaN(v) && v > 0.02 && v < 0.98) at[s.key] = y;
    }
  }
  scrollTo({ top: 0, behavior: 'instant' });
  await raf();
  return JSON.stringify({ maxY, at });
})()`;

/** Scroll to `y` without animation and report where the page stands. */
export const scrollToJs = (y) => `(() => { window.scrollTo({ top: ${Math.max(0, Math.round(Number(y)))}, behavior: 'instant' }); return JSON.stringify({ y: scrollY }); })()`;

/** The anchor scrollY of a rest pass: a margin above the ramp start, never above the top. */
export const ANCHOR_MARGIN_PX = 60;
export const anchorY = (rampStart) => (rampStart === null ? null : Math.max(0, rampStart - ANCHOR_MARGIN_PX));
