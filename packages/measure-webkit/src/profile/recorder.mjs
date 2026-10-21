// In-page pieces of the WebKit profile legs (glue; no decision). Both legs install the same recorder after the page has loaded:
// a rAF loop that keeps the callback time and the scroll position (tenth px) while `on`, and the two `performance.mark` calls that
// bracket a window ('wk:a' at start, 'wk:b' at stop). The marks arrive in the Timeline as TimeStamp records, which is how the
// Timeline clock is tied to the page clock (reduce.mjs `profileWindow`). It only observes.

/** Installed with `(${installRecorder})()`: defines `window.__pr` with `start()` and `stop()`. */
export function installRecorder() {
  const st = { on: false, ts: [], ys: [], a: 0, b: 0 };
  window.__pr = st;
  const tick = (t) => { if (st.on) { st.ts.push(t); st.ys.push(Math.round(window.scrollY * 10)); } requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
  const mark = (name) => { performance.clearMarks(name); performance.mark(name); return performance.getEntriesByName(name).pop().startTime; };
  st.start = () => { st.ts = []; st.ys = []; st.a = mark('wk:a'); st.on = true; };
  st.stop = () => {
    st.on = false;
    st.b = mark('wk:b');
    return {
      ts: st.ts, ys: st.ys, a: st.a, b: st.b,
      vh10: Math.round(window.innerHeight * 10),
      maxY10: Math.round((document.documentElement.scrollHeight - window.innerHeight) * 10),
    };
  };
}

export const RECORDER_SRC = `(${installRecorder.toString()})();`;

/** Scroll to the end of the page and let it rest (the same place the Chromium cadence lane starts its end window from). */
export const TO_END_JS = `(() => new Promise((resolve) => {
  window.scrollTo({ top: document.documentElement.scrollHeight - window.innerHeight, behavior: 'instant' });
  setTimeout(() => resolve(true), 1800);
}))()`;

/**
 * A scripted hero scroll inside the page (the Simulator has no wheel device): `count` steps of `dy` CSS px every `everyMs` on absolute
 * deadlines, then `tailMs` of rest. Returns the recorder's result.
 */
export const heroJs = ({ count, dy, everyMs, tailMs }) => `(async () => {
  const st = window.__pr;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  st.start();
  const t0 = performance.now();
  for (let i = 0; i < ${count}; i++) {
    window.scrollBy({ top: ${dy}, behavior: 'instant' });
    const wait = t0 + (i + 1) * ${everyMs} - performance.now();
    if (wait > 0) await sleep(wait);
  }
  await sleep(${tailMs});
  return st.stop();
})()`;

/**
 * The end-of-page window inside the page: one synthetic wheel push of `dy` down and one back, each held `holdMs`
 * (the push is what starts the end-of-page morph; lag/probe.mjs dispatches it the same way).
 */
export const endJs = ({ dy, holdMs }) => `(async () => {
  const st = window.__pr;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const push = (d) => document.body.dispatchEvent(new WheelEvent('wheel', { deltaY: d, cancelable: true, bubbles: true }));
  st.start();
  push(${dy});
  await sleep(${holdMs});
  push(-${dy});
  await sleep(${holdMs});
  return st.stop();
})()`;

/** The page result of the recorder (ms, scrollY tenths) as the reducer's `page` (hundredths of a ms on the page clock). */
export function pageOf(rec, toHundredths) {
  return {
    frames: rec.ts.map((t, i) => [toHundredths(t), rec.ys[i]]),
    vh10: rec.vh10, maxY10: rec.maxY10,
    w0: toHundredths(rec.a), w1: toHundredths(rec.b),
    marks: { a: toHundredths(rec.a), b: toHundredths(rec.b) },
  };
}

/** Tenths of ms between neighbouring rAF timestamps (ms, fractional). */
export const intervalsOf = (ts) => ts.slice(1).map((t, i) => Math.round((t - ts[i]) * 10));
