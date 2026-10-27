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

/** A page-side stamp every 500 ms: a TimeStamp row `fwpc:<page ms>` in any running timeline, so a segment is synced without a host call (a host evaluate right after a cycle hung for 120 s in runs 40470960001 and 40479824329). */
export const STAMP_JS = "(() => { if (window.__fwStamp) return 'on'; window.__fwStamp = setInterval(() => { performance.mark('fwpc:' + performance.now().toFixed(1)); performance.clearMarks(); }, 500); return 'on'; })()";

