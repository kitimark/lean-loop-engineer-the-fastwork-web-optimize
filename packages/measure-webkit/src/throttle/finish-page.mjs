// Page-side code of the finish pass (I/O glue, no decision): scroll near the page end, then one native requestAnimationFrame callback per
// frame stores the frame time, scrollY and the largest scrollY (tenth px), whether the end-of-page morph is open (the nav's inline --morph
// above 0.001, as touchlock-page.mjs reads it) and the viewport heights. Recording starts at the first scroll event and the fetch returns
// the frames up to the last frame whose scrollY or open flag changed. Lean (via finish.mjs, golden-checked) does every reduction.

/** Scroll to `gapPx` above the page end without animation and report where the page stands. */
export const nearEndJs = (gapPx) => `(() => {
  const maxY = document.documentElement.scrollHeight - innerHeight;
  window.scrollTo({ top: Math.max(0, maxY - ${gapPx}), behavior: 'instant' });
  return JSON.stringify({ maxY, y: scrollY, vh: innerHeight });
})()`;

export const START_JS = `(() => {
  const sel = 'header.start-selling-top-nav, [data-fw="nav"]';
  const st = window.__fwFin = { t: [], y: [], mx: [], o: [], ih: [], vh: [], armed: false, stop: false, last: -1, start: null, nav: !!document.querySelector(sel) };
  const vv = typeof visualViewport !== 'undefined' ? visualViewport : null;
  st.start = { ih: innerHeight, vh: vv ? vv.height : innerHeight, y: scrollY, scale: vv ? vv.scale : 1 };
  addEventListener('scroll', () => { st.armed = true; }, { passive: true, once: true, capture: true });
  let nav = null, py = null, po = null;
  const open = () => {
    if (!nav || !nav.isConnected) nav = document.querySelector(sel);
    return nav && Number(nav.style.getPropertyValue('--morph')) > 0.001 ? 1 : 0;
  };
  const f = (ts) => {
    if (st.stop) return;
    if (st.armed || scrollY !== st.start.y) {
      st.armed = true;
      const y = Math.round(scrollY * 10), o = open();
      if (py !== null && (y !== py || o !== po)) st.last = st.t.length;
      py = y; po = o;
      st.t.push(Math.round(ts * 100) / 100); st.y.push(y); st.o.push(o);
      st.mx.push(Math.round((document.documentElement.scrollHeight - innerHeight) * 10));
      st.ih.push(Math.round(innerHeight * 10)); st.vh.push(Math.round((vv ? vv.height : innerHeight) * 10));
    }
    requestAnimationFrame(f);
  };
  requestAnimationFrame(f);
  return 'started';
})()`;

/** Stop and return the record as a JSON string: frames [0, last], the start state, whether the nav was found. */
export const FETCH_JS = `(() => {
  const st = window.__fwFin;
  if (!st) return JSON.stringify({ err: 'recorder not started' });
  st.stop = true;
  const n = st.last + 1;
  return JSON.stringify({
    start: st.start, nav: st.nav, frames: n,
    t: st.t.slice(0, n), y: st.y.slice(0, n), mx: st.mx.slice(0, n), o: st.o.slice(0, n), ih: st.ih.slice(0, n), vh: st.vh.slice(0, n),
    total: st.t.length,
  });
})()`;
