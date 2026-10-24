// Felt-lag recorder on the real iPhone (device-lag-recorder). I/O glue only: the page records, for every native
// requestAnimationFrame of a pass in which a PERSON swipes, the frame timestamp, scrollY and the animated values of the parts of the
// two user windows, and every touch event (passive listeners, no preventDefault: the page behaves as without them). A triple tap is
// a felt-lag mark; Lean (Fw.Device.Session via device-session.mjs) finds the marks and does every reduction afterwards, so nothing
// is decided in the page.
// Probe effect: one rAF callback and three inline custom-property reads per frame (inline style reads do not flush layout). The
// callback runs before the page's own callbacks of that frame, so the value read in frame i+1 is the one the page wrote in frame i from
// scrollY of frame i, not from the scrollY read next to it. Lean `partSeries` pairs each value with that earlier position; the stall
// rule compares those pairs.
// The Safari toolbar changes the visual viewport height (collapsed 815 vs 775 px) while the person swipes, so every frame also stores
// `vv.height` (`vh`) and `vv.offsetTop` (`vt`) in 0.1 px (innerHeight when there is no visualViewport); Lean (`classes`) splits the frames
// into toolbar-moving and toolbar-still and the verdicts compare like with like per class. These reads DO flush layout in WebKit
// (VisualViewport.cpp:72-76 updateFrameLayout, used by offsetTop 87-94, height 123-130 and scale 132-141 @ WebKit 862f17d), but the
// callback writes no DOM and already reads `vv.scale` and `scrollY` every frame, so the layout is already up to date and the two new reads
// add no layout work.
// A touch ON a moving page stops its native fling; the person's tap therefore changes the scroll it marks. Say so in the session steps.
// The felt mark must not change the page: the step text names an empty area; a tap that still hits a link ends the page, which the
// pagehide listener (and, after the navigation, the missing liveness flag the poll looks for) names as the failure. A pinch or
// double-tap zoom changes what scrollY means; the visual viewport scale is read every frame and the frames at a scale other than 1
// are counted in the record (`zoom`).
import { sleep } from './sim.mjs';
import { BANNER_JS, BANNER_OFF_JS, SCHEME_JS } from './device-swipe.mjs';

/** The parts sampled: inline custom properties the page writes (hero exit, people card shrink, end-of-page morph fade), as in both sites. */
export const PART_PROPS = Object.freeze({ hero: '--exit-opacity', people: '--future-shrink', fade: '--morph-fade' });

/** The page-side recorder: returns the record in page units (ms, px, per mille). */
export const RECORD_JS = (seconds) => `(async () => {
  const PROPS = ${JSON.stringify(PART_PROPS)};
  const maxY = document.documentElement.scrollHeight - innerHeight;
  const t = [], y = [], vh = [], vt = [], p = { hero: [], people: [], fade: [] }, touches = [];
  const els = {}, last = { hero: 0, people: 0, fade: 0 };
  const read = (name) => {
    let el = els[name];
    if (!el || !el.isConnected) el = els[name] = document.querySelector('[style*="' + PROPS[name] + '"]');
    if (!el) return last[name];
    const v = parseFloat(el.style.getPropertyValue(PROPS[name]));
    if (!Number.isNaN(v)) last[name] = Math.round(Math.min(1, Math.max(0, v)) * 1000);
    return last[name];
  };
  const vv = typeof visualViewport !== 'undefined' ? visualViewport : null;
  const zoom = { frames: 0, min: 1, max: 1 };
  const base = performance.timeOrigin;
  const stamp = (e) => Math.round((e.timeStamp > 1e11 ? e.timeStamp - base : e.timeStamp) * 100) / 100;
  const code = { touchstart: 's', touchmove: 'm', touchend: 'e', touchcancel: 'c' };
  const onTouch = (e) => {
    const c = e.changedTouches[0];
    if (c) touches.push([stamp(e), code[e.type], Math.round(c.clientX * 10) / 10, Math.round(c.clientY * 10) / 10, e.touches.length]);
  };
  const opt = { passive: true, capture: true };
  for (const k of Object.keys(code)) addEventListener(k, onTouch, opt);
  const onHide = () => { globalThis.__wkRec = JSON.stringify({ err: 'page navigated (a tap hit a link)' }); };
  addEventListener('pagehide', onHide, opt);
  const t0 = performance.now();
  await new Promise((done) => {
    const f = (ts) => {
      t.push(Math.round(ts * 100) / 100); y.push(Math.round(scrollY * 10) / 10);
      for (const n of Object.keys(p)) p[n].push(read(n));
      const sc = vv ? vv.scale : 1;
      if (Math.abs(sc - 1) > 0.001) { zoom.frames++; zoom.min = Math.min(zoom.min, sc); zoom.max = Math.max(zoom.max, sc); }
      vh.push(Math.round((vv ? vv.height : innerHeight) * 10) / 10); vt.push(Math.round((vv ? vv.offsetTop : 0) * 10) / 10);
      if (performance.now() - t0 < ${Number(seconds) * 1000}) requestAnimationFrame(f); else done();
    };
    requestAnimationFrame(f);
  });
  for (const k of Object.keys(code)) removeEventListener(k, onTouch, opt);
  removeEventListener('pagehide', onHide, opt);
  return { zoom, maxY: Math.round(maxY * 10) / 10, viewport: { w: innerWidth, h: innerHeight, dpr: devicePixelRatio }, frames: { t, y, vh, vt, p }, touches };
})()`;

/** The arm of step `k` (1-based) from a plan Lean wrote (`planFor`), with its banner text. */
export const stepOf = (k, plan) => {
  const s = plan.find((x) => x.step === k);
  if (!s) throw new Error(`no step ${k} in a plan of ${plan.length}`);
  return s;
};

/** The poll expression: the record, or the named failure when the recorder's page is gone (a fresh page has no liveness flag). */
export const POLL_JS = `window.__wkRec || (window.__wkRecOn ? null : JSON.stringify({err: 'page navigated (a tap hit a link)'}))`;

/**
 * One pass: (1) optionally wait for Light appearance, (2) countdown banner with the step text, (3) record `seconds`, (4) "done".
 * Returns the record in page units. No device name, address or id is in it.
 */
export async function phoneRecord(ctx, { arm, pass, seconds, text, waitLightS = 0, countdownS = 6, loadFresh, clock, settleMs, log }) {
  await loadFresh(ctx.c, { clock, settleMs, timers: 'live' });
  await ctx.c.evaluate('scrollTo({ top: 0, behavior: "instant" }); 1');
  let scheme = await ctx.c.evaluate(SCHEME_JS);
  const tw = Date.now();
  while (scheme === 'dark' && Date.now() - tw < waitLightS * 1000) {
    await ctx.c.evaluate(BANNER_JS(`Please switch the phone to LIGHT appearance (Control Centre or Settings). Waiting ${Math.ceil(waitLightS - (Date.now() - tw) / 1000)} s`, false));
    await sleep(2000);
    scheme = await ctx.c.evaluate(SCHEME_JS);
  }
  for (let s = countdownS; s > 0; s--) {
    await ctx.c.evaluate(BANNER_JS(`${text}  Starts in ${s} s (this banner disappears when recording starts).`, false));
    await sleep(1000);
  }
  await ctx.c.evaluate(BANNER_OFF_JS);
  await ctx.c.evaluate('scrollTo({ top: 0, behavior: "instant" }); 1');
  log(`recording ${seconds} s, arm ${arm} pass ${pass}: person swipes now`);
  await ctx.c.evaluate(`window.__wkRecOn = true; window.__wkRec = undefined; Promise.resolve(${RECORD_JS(seconds)}).then(v => { window.__wkRec = JSON.stringify(v); }, e => { window.__wkRec = JSON.stringify({err: String(e)}); }); 'started'`);
  let run = null, polls = 0;
  const tEnd = Date.now() + (seconds + 90) * 1000;
  while (!run && Date.now() < tEnd) {
    await sleep(2500); polls++;
    try { const v = await ctx.c.evaluate(POLL_JS); if (v) run = JSON.parse(v); } catch (e) { log(`poll ${polls}: ${e.message}`); }
  }
  if (!run || run.err) throw new Error(`recording did not finish: ${run?.err ?? 'timeout'}`);
  await ctx.c.evaluate(BANNER_JS('DONE. You can stop swiping and put the phone down.', true)).catch(() => {});
  const silent = Object.entries(run.frames.p).filter(([, vs]) => vs.every((v) => v === 0)).map(([n]) => n);
  if (silent.length > 0) log(`part value never left 0 for: ${silent.join(', ')} (selector missed or the window was not reached)`);
  if (run.zoom?.frames > 0) log(`WARNING: the page was zoomed in ${run.zoom.frames} frames (scale ${run.zoom.min}..${run.zoom.max}); scroll positions of this pass are not comparable: repeat the step`);
  return { schema: 'fw.phone.record/1', arm, pass, appearance: scheme, ...run };
}
