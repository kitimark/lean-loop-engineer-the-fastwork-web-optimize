// Functions that run inside the page (serialised by Playwright's evaluate; they must not close over anything).

/** Start one rAF loop that records every callback timestamp in window.__fw.raf. `repaint`: also change the body colour each frame. */
export function installRaf(repaint) {
  const fw = (window.__fw = { raf: [], on: true });
  let n = 0;
  const tick = (ts) => {
    if (!fw.on) return;
    fw.raf.push(ts);
    if (repaint) document.body.style.background = `hsl(${(n++ * 37) % 360} 60% 80%)`;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/** Zone boundary: the page clock now, plus a TimeStamp in the Inspector Timeline (performance.mark and console.timeStamp). */
export function stamp(label) {
  performance.mark(label);
  console.timeStamp(label);
  return performance.now();
}

/** Wait until scrollY is unchanged for 3 rAFs (at most `maxMs`), then 2 more rAFs; stamps `label`; returns the page clock and scrollY. */
export function settle({ label, maxMs }) {
  return new Promise((done) => {
    const t0 = performance.now();
    let same = 0;
    let last = scrollY;
    const raf2 = (cb) => requestAnimationFrame(() => requestAnimationFrame(cb));
    const step = () => {
      if (scrollY === last) same += 1; else { same = 0; last = scrollY; }
      if (same >= 3 || performance.now() - t0 > maxMs) {
        raf2(() => {
          performance.mark(label);
          console.timeStamp(label);
          done({ t: performance.now(), scrollY, timedOut: same < 3 });
        });
      } else requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  });
}

/** Stop the loop; return its timestamps. */
export function stopRaf() {
  window.__fw.on = false;
  return window.__fw.raf;
}

/** The WebGL renderer string (a hint only: ANGLE or the driver may mask it). */
export function rendererString() {
  try {
    const gl = document.createElement('canvas').getContext('webgl');
    const ext = gl && gl.getExtension('WEBGL_debug_renderer_info');
    return ext ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : (gl ? 'webgl without debug info' : 'no webgl');
  } catch (e) {
    return `error: ${e && e.message}`;
  }
}
