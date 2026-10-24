import { PART_PROPS } from '../device-record.mjs';

export const SERIES = Object.freeze([
  { key: 'hero', part: 'hero.exit', prop: PART_PROPS.hero, golden: 'hero' },
  { key: 'people', part: 'people.card', prop: PART_PROPS.people, golden: 'people' },
  { key: 'commissionEnter', part: 'commission', prop: '--commission-enter-shrink', golden: null },
  { key: 'commission', part: 'commission', prop: '--commission-shrink', golden: null },
  { key: 'platform', part: 'platform.shrink', prop: '--platform-shrink', golden: null },
  { key: 'fade', part: 'morph.panel', prop: PART_PROPS.fade, golden: 'fade' },
]);

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

export const FETCH_JS = `(() => {
  const st = window.__fwParts;
  if (!st) return JSON.stringify({ err: 'parts recorder not started' });
  st.stop = true;
  const n = st.lastMove + 1;
  const v = {};
  for (const k of Object.keys(st.v)) v[k] = st.v[k].slice(0, n);
  return JSON.stringify({ start: st.start, found: st.found, frames: n, t: st.t.slice(0, n), y: st.y.slice(0, n), vh: st.vh.slice(0, n), v, total: st.t.length });
})()`;

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

export const scrollToJs = (y) => `(() => { window.scrollTo({ top: ${Math.max(0, Math.round(Number(y)))}, behavior: 'instant' }); return JSON.stringify({ y: scrollY }); })()`;

export const ANCHOR_MARGIN_PX = 60;
export const anchorY = (rampStart) => (rampStart === null ? null : Math.max(0, rampStart - ANCHOR_MARGIN_PX));
