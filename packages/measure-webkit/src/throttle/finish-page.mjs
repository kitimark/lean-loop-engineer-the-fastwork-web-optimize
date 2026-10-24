// Page-side code of the finish pass (I/O glue, no decision): scroll near the page end, then one native requestAnimationFrame callback per
// frame stores the frame time, scrollY and the largest scrollY (tenth px), whether the end-of-page morph is open (the nav's inline --morph
// above 0.001, as touchlock-page.mjs reads it) and the viewport heights. Recording starts at the first scroll event and the fetch returns
// the frames up to the last frame whose scrollY, open flag or morph value changed. Lean (via finish.mjs, golden-checked) does every reduction.
// Task morph-end-measure adds three reads per frame: the morph value r (thousandths), the finger direction d of the last touchmove of the
// current touch (-1 finger up the screen, scrolls toward the end; 1 finger down; 0 none yet; moves under 1 px are ignored, as the driver
// ignores them), and the pin writes (scrollTo with behavior instant, with the index of the next frame). wobble counts direction flips inside one touch.

/** Scroll to `gapPx` above the page end without animation and report where the page stands. */
export const nearEndJs = (gapPx) => `(() => {
  const maxY = document.documentElement.scrollHeight - innerHeight;
  window.scrollTo({ top: Math.max(0, maxY - ${gapPx}), behavior: 'instant' });
  return JSON.stringify({ maxY, y: scrollY, vh: innerHeight });
})()`;

export const START_JS = `(() => {
  const sel = 'header.start-selling-top-nav, [data-fw="nav"]';
  const st = window.__fwFin = { t: [], y: [], mx: [], o: [], r: [], d: [], ih: [], vh: [], ca: [], wobble: 0, moves: 0, armed: false, stop: false, last: -1, start: null, nav: !!document.querySelector(sel) };
  const vv = typeof visualViewport !== 'undefined' ? visualViewport : null;
  st.start = { ih: innerHeight, vh: vv ? vv.height : innerHeight, y: scrollY, scale: vv ? vv.scale : 1 };
  addEventListener('scroll', () => { st.armed = true; }, { passive: true, once: true, capture: true });
  let nav = null, py = null, po = null, pr = null, fd = 0, ly = null;
  addEventListener('touchstart', (e) => { fd = 0; ly = e.touches[0] ? e.touches[0].clientY : null; }, { capture: true, passive: true });
  addEventListener('touchmove', (e) => {
    const t = e.touches[0];
    if (!t || ly === null) return;
    const dy = t.clientY - ly;
    if (Math.abs(dy) < 1) return;
    const nd = dy < 0 ? -1 : 1;
    st.moves++;
    if (fd !== 0 && nd !== fd) st.wobble++;
    fd = nd; ly = t.clientY;
  }, { capture: true, passive: true });
  const scrollTo = window.scrollTo.bind(window);
  window.scrollTo = function (...a) {
    const o = a[0];
    if (st.armed && o && typeof o === 'object' && typeof o.top === 'number' && o.behavior === 'instant') st.ca.push([Math.round(o.top * 10), open(), st.t.length]);
    return scrollTo(...a);
  };
  const morph = () => (nav && nav.isConnected ? Math.round(Number(nav.style.getPropertyValue('--morph') || 0) * 1000) : 0);
  const open = () => {
    if (!nav || !nav.isConnected) nav = document.querySelector(sel);
    return nav && Number(nav.style.getPropertyValue('--morph')) > 0.001 ? 1 : 0;
  };
  const f = (ts) => {
    if (st.stop) return;
    if (st.armed || scrollY !== st.start.y) {
      st.armed = true;
      const y = Math.round(scrollY * 10), o = open(), r = morph();
      if (py !== null && (y !== py || o !== po || r !== pr)) st.last = st.t.length;
      py = y; po = o; pr = r;
      st.t.push(Math.round(ts * 100) / 100); st.y.push(y); st.o.push(o); st.r.push(r); st.d.push(fd);
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
    r: st.r.slice(0, n), d: st.d.slice(0, n), ca: st.ca.filter((c) => c[2] <= n), wobble: st.wobble, moves: st.moves,
    total: st.t.length,
  });
})()`;
