// Replay of a committed CI profile (strokes at 60 Hz) into the rewrite page with a flag set, on Chromium with CDP touches
// (task combo-scroll-fight, note research/notes/2026/10-2x-combo-scroll-fight.md). Records scrollY, finger and the morph value on
// every animation frame and every `scrollTo` call of the page (who wrote the scroll position, from where, while the finger was down or not).
import { dispatchAt, touchMessage } from './chromium-replay.mjs';
import { metrics } from './combo-metrics.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Touch events [t ms, phase, x, y] of the strokes: a start, the moves, an end at the last position one frame later. */
export function eventsOf(profile) {
  const dt = 1000 / profile.hz;
  const out = [];
  for (const s of profile.input.strokes) {
    s.path.forEach(([x, y], i) => out.push([(s.f0 + i) * dt, i === 0 ? 's' : 'm', x, y]));
    const [x, y] = s.path[s.path.length - 1];
    out.push([(s.f0 + s.path.length) * dt, 'e', x, y]);
  }
  return out.sort((a, b) => a[0] - b[0]);
}

export const RECORDER_JS = `(() => {
  if (window.__combo) return;
  const R = (window.__combo = { t: [], y: [], m: [], d: [], writes: [], moves: [], down: false, on: false });
  const st = (e) => { R.down = e.touches.length > 0; };
  for (const k of ['touchstart', 'touchmove', 'touchend', 'touchcancel']) addEventListener(k, st, { capture: true, passive: true });
  // touchmove as the page left it: [t, cancelable, defaultPrevented, scrollY], read in the bubble phase after the page's capture listeners
  document.addEventListener('touchmove', (e) => { if (R.on) R.moves.push([Math.round(performance.now() * 10) / 10, e.cancelable ? 1 : 0, e.defaultPrevented ? 1 : 0, window.scrollY]); }, { passive: true });
  const orig = window.scrollTo.bind(window);
  window.scrollTo = function (...a) {
    const o = a[0];
    const top = o && typeof o === 'object' ? o.top : a[1];
    if (R.on) R.writes.push([Math.round(performance.now() * 10) / 10, top, window.scrollY, R.down ? 1 : 0]);
    return orig(...a);
  };
  const loop = (now) => {
    if (R.on) {
      const nav = document.querySelector('[data-fw="nav"]');
      R.t.push(Math.round(now * 10) / 10); R.y.push(window.scrollY); R.m.push(Number(nav && nav.dataset.fwMorph || 0)); R.d.push(R.down ? 1 : 0);
    }
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
})()`;

/** Where the pass starts: the top, the page end, or the scroll position where the platform is armed (its bottom at the viewport bottom). */
export const START_JS = (start) => `(() => {
  const se = document.scrollingElement;
  const max = se.scrollHeight - innerHeight;
  let y = 0;
  if (${JSON.stringify(start)} === 'end') y = max;
  if (${JSON.stringify(start)} === 'armed') {
    const p = document.querySelector('.start-selling-platform, [data-fw="platform"]');
    if (p) y = Math.min(max, Math.round(p.getBoundingClientRect().bottom + se.scrollTop - innerHeight));
  }
  se.scrollTop = y;
  return y;
})()`;

export async function comboPass({ browser, origin, search = '', profile, throttle = 6, settleMs = 4000, tailMs = 2500, log = () => {} }) {
  const v = profile.viewport;
  const context = await browser.newContext({ viewport: { width: v.width, height: v.height }, deviceScaleFactor: v.dpr, isMobile: true, hasTouch: true });
  try {
    await context.addInitScript(RECORDER_JS);
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    await page.goto(`${origin}/${search}`, { waitUntil: 'load' });
    await sleep(settleMs);
    const variants = await page.evaluate('JSON.stringify(window.__fw && window.__fw.config.variants)');
    const maxY = await page.evaluate('document.documentElement.scrollHeight - innerHeight');
    const at = await page.evaluate(START_JS(profile.input.start ?? 'top'));
    log(`start ${profile.input.start ?? 'top'}: scrollY ${at}`);
    await sleep(600);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });
    await page.evaluate('window.__combo.on = true; 1');
    const events = eventsOf(profile);
    log(`replaying ${profile.id}: ${events.length} touch events, ${(events[events.length - 1][0] / 1000).toFixed(1)} s, maxY ${maxY}, throttle ${throttle}x`);
    const late = await dispatchAt(cdp, events);
    await sleep(tailMs);
    await page.evaluate('window.__combo.on = false; 1');
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    const rec = await page.evaluate('JSON.stringify({ t: __combo.t, y: __combo.y, m: __combo.m, d: __combo.d, writes: __combo.writes, moves: __combo.moves })');
    const r = JSON.parse(rec);
    return { maxY, variants: JSON.parse(variants), events: events.length, lateMax: Math.max(...late), rec: r, metrics: metrics({ ts: r.t, ys: r.y, down: r.d, writes: r.writes }) };
  } finally {
    await context.close();
  }
}

export { touchMessage };
