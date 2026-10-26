export const EXTRA_START_JS = `(() => {
  const st = window.__fwFin;
  if (!st) return 'no base recorder';
  const x = window.__fwPcx = { rz: [], vvr: [], vvs: [] };
  addEventListener('resize', () => { x.rz.push(st.t.length); }, { passive: true });
  if (typeof visualViewport !== 'undefined' && visualViewport) {
    visualViewport.addEventListener('resize', () => { x.vvr.push(st.t.length); });
    visualViewport.addEventListener('scroll', () => { x.vvs.push(st.t.length); });
  }
  return 'started';
})()`;

export const EXTRA_FETCH_JS = `(() => JSON.stringify(window.__fwPcx || { rz: [], vvr: [], vvs: [] }))()`;
