export const EXTRA_START_JS = `(() => {
  const st = window.__fwFin;
  if (!st) return 'no base recorder';
  const x = window.__fwPcx = { rz: [], vvr: [], vvs: [], raf: [] };
  const native = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) => {
    if (cb !== st.cb) x.raf.push(Math.round(performance.now() * 10) / 10);
    return native(cb);
  };
  addEventListener('resize', () => { x.rz.push(st.t.length); }, { passive: true });
  if (typeof visualViewport !== 'undefined' && visualViewport) {
    visualViewport.addEventListener('resize', () => { x.vvr.push(st.t.length); });
    visualViewport.addEventListener('scroll', () => { x.vvs.push(st.t.length); });
  }
  return 'started';
})()`;

export const EXTRA_FETCH_JS = `(() => JSON.stringify(window.__fwPcx || { rz: [], vvr: [], vvs: [], raf: [] }))()`;

export const STAMP_JS = "(() => { if (window.__fwStamp) return 'on'; window.__fwStamp = setInterval(() => { performance.mark('fwpc:' + performance.now().toFixed(1)); performance.clearMarks(); }, 500); return 'on'; })()";

/** Task cols-probe: the geom-timed driver calls window.__fwTakeTrace on a push and on a take (apps/site morph.tween/index.tsx); log each with is-on-dark at the push. */
export const COLS_LOG_JS = "(() => { window.__fwColsLog = []; window.__fwTakeTrace = (e) => { try { window.__fwColsLog.push({ kind: e.kind, dark: e.kind === 'push' ? document.querySelector('nav.is-on-dark') !== null : null }); } catch (_) {} }; return 'on'; })()";

export const COLS_LOG_FETCH_JS = "(() => JSON.stringify(window.__fwColsLog || []))()";

