// Extra page recorder of the push-cycle lane (I/O glue, runs after finish-page.mjs START_JS): the frame index of every window `resize`, of every
// visualViewport `resize` and `scroll`, so a toolbar change (H1) can be placed between frames. The frame index is the length of the base recorder's
// time array when the event fires, the same index its other arrays use.

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
