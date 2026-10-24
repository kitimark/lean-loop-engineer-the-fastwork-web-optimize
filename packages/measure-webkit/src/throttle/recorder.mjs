// Page-side recorder of the toolbar-throttle probe (I/O glue, no decision): one native requestAnimationFrame callback per frame
// stores the frame time, scrollY (tenth px), the hero's inline --exit-opacity (per mille, as device-record.mjs reads it) and the
// layout and visual viewport heights (tenth px). Recording starts at the first scroll event and the fetch returns the frames up
// to the last frame whose scrollY changed, so the idle time before and after the touches is not in the record. Lean (via
// stillruns.mjs, golden-checked) does every reduction afterwards.
import { PART_PROPS } from '../device-record.mjs';

export const START_JS = `(() => {
  const prop = ${JSON.stringify(PART_PROPS.hero)};
  const st = window.__fwThr = { t: [], y: [], v: [], ih: [], vh: [], ev: [], evn: 0, armed: false, stop: false, lastMove: -1, start: null, hero: false };
  const vv = typeof visualViewport !== 'undefined' ? visualViewport : null;
  st.start = { ih: innerHeight, vh: vv ? vv.height : innerHeight, y: scrollY, scale: vv ? vv.scale : 1 };
  addEventListener('scroll', () => { st.armed = true; }, { passive: true, once: true, capture: true });
  addEventListener('scroll', () => { st.evn++; }, { passive: true, capture: true });
  let el = null, last = 0, prev = null;
  const read = () => {
    if (!el || !el.isConnected) el = document.querySelector('[style*="' + prop + '"]');
    if (!el) return last;
    const v = parseFloat(el.style.getPropertyValue(prop));
    if (!Number.isNaN(v)) last = Math.round(Math.min(1, Math.max(0, v)) * 1000);
    st.hero = true;
    return last;
  };
  const f = (ts) => {
    if (st.stop) return;
    if (st.armed || scrollY !== st.start.y) {
      st.armed = true;
      const y = Math.round(scrollY * 10);
      if (prev !== null && y !== prev) st.lastMove = st.t.length;
      prev = y;
      st.t.push(Math.round(ts * 100) / 100); st.y.push(y); st.v.push(read());
      st.ev.push(st.evn);
      st.ih.push(Math.round(innerHeight * 10)); st.vh.push(Math.round((vv ? vv.height : innerHeight) * 10));
    }
    requestAnimationFrame(f);
  };
  requestAnimationFrame(f);
  return 'started';
})()`;

/** Stop and return the record as a JSON string: frames [0, lastMove], the start state, whether the hero value was found. */
export const FETCH_JS = `(() => {
  const st = window.__fwThr;
  if (!st) return JSON.stringify({ err: 'recorder not started' });
  st.stop = true;
  const n = st.lastMove + 1;
  return JSON.stringify({
    start: st.start, hero: st.hero, frames: n,
    t: st.t.slice(0, n), y: st.y.slice(0, n), v: st.v.slice(0, n), ev: st.ev.slice(0, n), ih: st.ih.slice(0, n), vh: st.vh.slice(0, n),
    maxY: Math.max(0, ...st.y) / 10, total: st.t.length,
  });
})()`;
