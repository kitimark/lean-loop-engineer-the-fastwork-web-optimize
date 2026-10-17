// Code that runs inside the page. Everything exported as a function here is self-contained (no closure over module
// scope), because the engines serialise it with toString() and evaluate it in the page. No decisions are made here:
// the page only reports what it sees. The pass/fail rule is in verdict.mjs.

/**
 * Init script, injected before any page script in both arms and both engines. It pins `Date` (new Date(), Date.now())
 * to one instant and seeds Math.random (mulberry32), so the countdown and any random layout choice are identical
 * between the two arms and between runs. It leaves timers, requestAnimationFrame and performance.now native.
 */
export const PIN_SRC = `(() => {
  const FIXED = Date.parse('2026-10-01T00:00:00+07:00');
  const RealDate = Date;
  function FakeDate(...a) {
    if (!new.target) return new RealDate(FIXED).toString();
    return a.length === 0 ? new RealDate(FIXED) : new RealDate(...a);
  }
  FakeDate.prototype = RealDate.prototype;
  FakeDate.now = () => FIXED;
  FakeDate.parse = RealDate.parse;
  FakeDate.UTC = RealDate.UTC;
  Object.defineProperty(FakeDate, 'name', { value: 'Date' });
  window.Date = FakeDate;
  let s = 0x9e3779b9 >>> 0;
  Math.random = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
})();`;

/** Wait until the arm has settled: fonts, hydration (rewrite) or the hero splash (original), then 3 frames and 300 ms. */
export async function waitReady(arg) {
  const { site, capMs } = arg;
  const t0 = performance.now();
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  try { await document.fonts.ready; } catch { /* no font API */ }
  let ready = false;
  let splash = null;
  if (site === 'rewrite') {
    while (!(window.__fw && window.__fw.hydrated) && performance.now() - t0 < capMs) await sleep(50);
    ready = !!(window.__fw && window.__fw.hydrated);
  } else {
    const done = () => !!document.querySelector('.hero-track .hero.is-ring-splash-done');
    while (!done() && performance.now() - t0 < capMs) await sleep(50);
    splash = done();
    ready = !!document.querySelector('.hero-track .hero');
  }
  // every finite CSS animation or transition has finished (infinite ones, e.g. the call-to-action orbit, are ignored)
  const running = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && Number.isFinite(t.iterations) && a.playState !== 'finished' && a.playState !== 'idle';
  }).length;
  const t1 = performance.now();
  while (running() > 0 && performance.now() - t1 < capMs) await sleep(50);
  for (let i = 0; i < 3; i++) await frame();
  await sleep(300);
  const fw = window.__fw;
  return { ready, splash, fwMode: fw ? fw.mode : null, hydrationErrors: fw ? (fw.hydrationErrors ? fw.hydrationErrors.length ?? fw.hydrationErrors : 0) : null };
}

/** A short pause after a live resize: two frames and 600 ms (the original debounces its resize work with timers). */
export async function waitResize() {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  await frame();
  await frame();
  await sleep(600);
  const running = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && Number.isFinite(t.iterations) && a.playState !== 'finished' && a.playState !== 'idle';
  }).length;
  const t1 = performance.now();
  while (running() > 0 && performance.now() - t1 < 5000) await sleep(50);
  await frame();
  return true;
}

/**
 * Collect the raw facts of one arm in its current state.
 * arg: { site: 'orig'|'rewrite', conditions: [{tsId, css, legacyCss}], neutral: [{tsId, css}], dprWanted, widthWanted,
 *        parts: { [partId]: [{ role, selector, rect }] }, props: { [partId]: { [role]: string[] } } | null, filter: string }
 * With props == null, only the declared property names per role are reported (the scan that fixes the property lists).
 */
export function collectInPage(arg) {
  const mm = (q) => { try { return window.matchMedia(q).matches; } catch { return null; } };
  const out = { truth: {}, truthLegacy: {}, neutral: {}, observed: {}, viewport: {}, parts: {} };

  out.viewport = {
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    clientWidth: document.documentElement.clientWidth,
    clientHeight: document.documentElement.clientHeight,
    screenWidth: window.screen.width,
    screenHeight: window.screen.height,
    dpr: window.devicePixelRatio,
    scrollY: window.scrollY,
  };
  out.observed = {
    hoverHover: mm('(hover: hover)'),
    hoverNone: mm('(hover: none)'),
    pointerFine: mm('(pointer: fine)'),
    pointerCoarse: mm('(pointer: coarse)'),
    pointerNone: mm('(pointer: none)'),
    reducedMotion: mm('(prefers-reduced-motion: reduce)'),
    dark: mm('(prefers-color-scheme: dark)'),
    widthExact: mm(`(width: ${arg.widthWanted}px)`),
    print: mm('print'),
    forcedColors: mm('(forced-colors: active)'),
  };
  for (const c of arg.conditions) {
    out.truth[c.tsId] = mm(c.css);
    out.truthLegacy[c.tsId] = c.legacyCss === null ? null : mm(c.legacyCss);
  }
  for (const n of arg.neutral) out.neutral[n.tsId] = mm(n.css);

  const filter = new RegExp(arg.filter);
  const rules = [];
  const walk = (list) => {
    for (const r of list) {
      if (r.selectorText !== undefined) { if (filter.test(r.selectorText)) rules.push(r); }
      else if (r.cssRules) walk(r.cssRules);
    }
  };
  for (const sheet of Array.from(document.styleSheets)) {
    try { walk(sheet.cssRules); } catch { /* cross-origin sheet: not part of either arm */ }
  }
  const matches = (el, sel) => { try { return el.matches(sel); } catch { return false; } };

  for (const [pid, roles] of Object.entries(arg.parts)) {
    out.parts[pid] = {};
    for (const { role, selector, rect: wantRect } of roles) {
      const els = Array.from(document.querySelectorAll(selector)).slice(0, 64);
      const declared = new Set();
      const items = els.map((el) => {
        for (const r of rules) {
          if (!matches(el, r.selectorText)) continue;
          for (let i = 0; i < r.style.length; i++) declared.add(r.style[i]);
        }
        const r = el.getBoundingClientRect();
        const rect = wantRect ? { x: r.x, y: r.y, w: r.width, h: r.height } : null;
        const names = arg.props && arg.props[pid] && arg.props[pid][role] ? arg.props[pid][role] : [];
        const cs = getComputedStyle(el);
        const style = {};
        for (const n of names) style[n] = cs.getPropertyValue(n);
        return { rect, style };
      });
      out.parts[pid][role] = { count: els.length, declared: Array.from(declared).sort(), items: arg.props ? items : [] };
    }
  }
  return out;
}

/**
 * Original only: the morph panel is mounted lazily. A one-way flag is set the first time the platform section comes within
 * 200 % of the viewport (IntersectionObserver, 2.DyWL8TcE.js:13080-13089), so this scrolls there, waits for the first
 * column, and returns to the top. Self-contained (it is serialised into the page). Reports what it saw; decides nothing.
 */
export async function mountPanel() {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  const sel = '.start-selling-morph-col';
  const y0 = window.scrollY;
  const target = document.querySelector('#platform');
  if (target) {
    const r = target.getBoundingClientRect();
    window.scrollTo({ top: window.scrollY + r.top - window.innerHeight / 2, behavior: 'instant' });
  }
  const t0 = performance.now();
  while (!document.querySelector(sel) && performance.now() - t0 < 8000) { await frame(); await sleep(50); }
  const mounted = document.querySelectorAll(sel).length;
  window.scrollTo({ top: y0, behavior: 'instant' });
  for (let i = 0; i < 3; i++) await frame();
  await sleep(300);
  return { target: !!target, mounted, scrollY: window.scrollY };
}

/**
 * Open an overlay by clicking its trigger, wait until `ready` matches, then until every finite animation and transition
 * has ended, and settle for three frames and 300 ms. Self-contained (it is serialised into the page); reports what it saw.
 * arg: { trigger: selector of the button to click, ready: selector that matches once the overlay is shown }
 */
export async function openOverlay(arg) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  const btn = document.querySelector(arg.trigger);
  if (!btn) return { clicked: false, ready: false };
  btn.click();
  const t0 = performance.now();
  while (!document.querySelector(arg.ready) && performance.now() - t0 < 5000) await sleep(50);
  const ready = !!document.querySelector(arg.ready);
  const running = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && Number.isFinite(t.iterations) && a.playState !== 'finished' && a.playState !== 'idle';
  }).length;
  const t1 = performance.now();
  while (running() > 0 && performance.now() - t1 < 5000) await sleep(50);
  for (let i = 0; i < 3; i++) await frame();
  await sleep(300);
  return { clicked: true, ready };
}

/**
 * Close an overlay opened by `openOverlay`: click its close button and wait until `gone` no longer matches (the drawer is
 * unmounted 480 ms after the close; the dialog loses `open`), so the next read of the page starts from the closed state.
 * arg: { close: selector of the close button, gone: selector that matches while the overlay is still up }
 */
export async function closeOverlay(arg) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  const btn = document.querySelector(arg.close);
  if (!btn) return { clicked: false, gone: !document.querySelector(arg.gone) };
  btn.click();
  const t0 = performance.now();
  while (document.querySelector(arg.gone) && performance.now() - t0 < 5000) await sleep(50);
  for (let i = 0; i < 2; i++) await frame();
  await sleep(100);
  return { clicked: true, gone: !document.querySelector(arg.gone) };
}
