// Nav scroll-hide probe (task nav-scroll-hide-check): does the top nav leave the screen while the people section is
// scrolled, in the rewrite as in the original? Both arms are loaded at a desktop width, the page is scrolled from above the
// people section through it and out and back (a fixed step per frame), and every frame records what the nav and the
// people sticky element look like. Reports facts only; analysis is navscroll-analyze.mjs. Reuses the visual-diff
// servers, engines, asset overlay and the gate's readiness wait by import; none of them is changed.
//   sweep       scrollTo(y) in fixed steps (STEP px), FRAMES rAF per step, one record per step ("per frame")
//   settled     the same positions held for SETTLE_MS, records are end states
//   transition  at each onset/offset found by the sweep: park just before, jump one step, record every rAF for TRANS_MS together
//               with the running transitions (getAnimations(): property, start time, duration, delay, easing). Native rAF;
//               nothing is seeked or paused.
//   wheel       real mouse wheel events (WHEEL_PX every WHEEL_MS) down through the section and back, native rAF recorder
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PIN_SRC, waitReady } from '../../gate-breakpoints/src/page.mjs';
import { PKG as GATE_PKG, siteDist, snapshotRoot, startServer } from '../../gate-breakpoints/src/serve.mjs';
import { LAUNCHERS } from './engines.mjs';
import { injectFontsInPage } from './page.mjs';
import { originalFontFaces, startOverlayServer } from './serve.mjs';
import { transitions } from './navscroll-analyze.mjs';

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const STEP = 16;
export const FRAMES = 3;
export const SETTLE_MS = 700;
export const TRANS_MS = 700;
export const WHEEL_PX = 100;
export const WHEEL_MS = 60;
const FAMILY = 'Google Sans';
const CAP_MS = { orig: 20000, rewrite: 15000 };

/** Desktop widths: the control just below the original's sticky breakpoint, the smallest width above it, three common screens. */
export const WIDTHS = [
  { id: 'w860', width: 860, height: 800 },
  { id: 'w861', width: 861, height: 800 },
  { id: 'w1280', width: 1280, height: 800 },
  { id: 'w1440', width: 1440, height: 900 },
  { id: 'w1920', width: 1920, height: 1080 },
];

/** Where each arm's elements are. The rewrite uses its identity hooks (data-fw), the original its class names. */
export const SEL = {
  orig: { nav: '.start-selling-top-nav', sticky: '.start-selling-profile-sticky', section: '#profile-showcase, .start-selling-profile' },
  rewrite: { nav: '[data-fw="nav"]', sticky: '[data-fw="people-sticky"]', section: '#profile-showcase, [data-fw="people-deck"]' },
};

const envOf = (w) => ({
  width: w.width, height: w.height, deviceWidth: w.width, deviceHeight: w.height, dpr: 1,
  reducedMotion: 'no-preference', colorScheme: 'light', hover: 'hover', pointer: 'fine',
});

/**
 * Page side. One self-contained function (Playwright serialises it); `arg.op` picks the step. It reports; it decides nothing.
 * Record: y scrollY, cls the `is-` classes of the nav, hidden is-scroll-hidden present, tx/ty the computed transform's
 * translation, op opacity, vis visibility, top/bottom the nav's rect, stTop/stBottom the sticky element's rect, secBottom
 * the section's bottom.
 */
export async function navScrollInPage(arg) {
  const { op, sel } = arg;
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const snap = () => {
    const nav = document.querySelector(sel.nav);
    const st = document.querySelector(sel.sticky);
    const sec = st ? st.closest(sel.section) : null;
    if (!nav) return { absent: 'nav', y: window.scrollY };
    const cs = getComputedStyle(nav);
    const m = cs.transform === 'none' ? null : new DOMMatrix(cs.transform);
    const r = nav.getBoundingClientRect();
    const sr = st ? st.getBoundingClientRect() : null;
    return {
      y: window.scrollY,
      cls: [...nav.classList].filter((c) => c.startsWith('is-')).sort().join(' '),
      hidden: nav.classList.contains('is-scroll-hidden'),
      tx: m ? +m.e.toFixed(3) : 0,
      ty: m ? +m.f.toFixed(3) : 0,
      op: +cs.opacity,
      vis: cs.visibility,
      top: +r.top.toFixed(2),
      bottom: +r.bottom.toFixed(2),
      stTop: sr ? +sr.top.toFixed(2) : null,
      stBottom: sr ? +sr.bottom.toFixed(2) : null,
      secTop: sec ? +sec.getBoundingClientRect().top.toFixed(2) : null,
      secBottom: sec ? +sec.getBoundingClientRect().bottom.toFixed(2) : null,
    };
  };
  const go = (y) => window.scrollTo({ top: y, behavior: 'instant' });

  if (op === 'warm') {
    // A section far below may be sized only once it has been near the viewport (content-visibility), which moves everything under it.
    // The geometry is read after the whole page has been seen once.
    const last = document.documentElement.scrollHeight;
    for (let y = 0; y < last; y += Math.round(window.innerHeight / 2)) {
      go(y);
      await raf();
      await raf();
    }
    go(0);
    await wait(600);
    return document.documentElement.scrollHeight;
  }

  if (op === 'describe') {
    const nav = document.querySelector(sel.nav);
    const st = document.querySelector(sel.sticky);
    const sec = st ? st.closest(sel.section) : document.querySelector(sel.section);
    const cs = st ? getComputedStyle(st) : null;
    const ncs = nav ? getComputedStyle(nav) : null;
    const secR = sec ? sec.getBoundingClientRect() : null;
    const stR = st ? st.getBoundingClientRect() : null;
    return {
      nav: !!nav, sticky: !!st, section: !!sec,
      vw: document.documentElement.clientWidth, vh: window.innerHeight,
      docH: document.documentElement.scrollHeight,
      maxScroll: document.documentElement.scrollHeight - window.innerHeight,
      secTop: secR ? secR.top + window.scrollY : null,
      secH: secR ? secR.height : null,
      stickyDocTop: stR ? stR.top + window.scrollY : null,
      stickyH: stR ? stR.height : null,
      stickyPosition: cs ? cs.position : null,
      stickyCssTop: cs ? cs.top : null,
      navCls: nav ? [...nav.classList].filter((c) => c.startsWith('is-')).sort().join(' ') : null,
      navTransition: ncs ? { property: ncs.transitionProperty, duration: ncs.transitionDuration, easing: ncs.transitionTimingFunction, delay: ncs.transitionDelay } : null,
      navPosition: ncs ? ncs.position : null,
      scrollY: window.scrollY,
    };
  }

  if (op === 'sweep' || op === 'settled') {
    const out = [];
    go(arg.ys[0]);
    await wait(op === 'settled' ? arg.settleMs : 300);
    for (const y of arg.ys) {
      go(y);
      const early = [];
      if (op === 'settled') {
        let at = 0;
        for (const t of [50, 250, 500]) {
          await wait(t - at);
          at = t;
          const e = snap();
          early.push({ t, hidden: e.hidden, secTop: e.secTop, stTop: e.stTop });
        }
        await wait(arg.settleMs - at);
      } else for (let i = 0; i < arg.frames; i++) await raf();
      out.push({ ...snap(), want: y, ...(op === 'settled' ? { early } : {}) });
    }
    return out;
  }

  if (op === 'transition') {
    go(arg.yBefore);
    await wait(arg.settleMs);
    const before = snap();
    const frames = [];
    let anims = [];
    const t0 = performance.now();
    go(arg.yAfter);
    while (performance.now() - t0 < arg.ms) {
      const dtNow = performance.now() - t0;
      const nav = document.querySelector(sel.nav);
      const found = nav
        ? nav.getAnimations().filter((a) => a.transitionProperty).map((a) => {
            const t = a.effect.getTiming();
            return { prop: a.transitionProperty, startTime: a.startTime, duration: t.duration, delay: t.delay, easing: t.easing };
          })
        : [];
      if (found.length > anims.length) anims = found;
      frames.push({ dt: +dtNow.toFixed(2), ct: document.timeline.currentTime, ...snap() });
      await raf();
    }
    return { before, anims, frames, yBefore: arg.yBefore, yAfter: arg.yAfter };
  }

  if (op === 'wheelStart') {
    const rec = [];
    window.__navWheel = { rec, on: true };
    let last = '';
    const loop = () => {
      if (!window.__navWheel.on) return;
      const s = snap();
      const key = `${s.y}|${s.cls}|${s.vis}`;
      if (key !== last) { last = key; rec.push({ ct: document.timeline.currentTime, ...s }); }
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
    return true;
  }
  if (op === 'wheelStop') {
    window.__navWheel.on = false;
    return window.__navWheel.rec;
  }
  throw new Error(`unknown op ${op}`);
}

/** The u grid (scrollY minus the section's document top) of a sweep: from one viewport above the section to half a viewport past it. */
export function gridOf(geo, step = STEP) {
  const from = -geo.vh;
  const to = geo.secH + geo.vh / 2;
  const us = [];
  for (let u = from; u <= to; u += step) us.push(u);
  return us;
}

/** Adds u (the section's live offset: minus its rect top at that frame; falls back to scrollY minus the described top) and uw (the grid value asked for; the key the arms are matched on). */
const withU = (recs, secTop, uws) => recs.map((r, i) => ({ ...r, u: +(r.secTop != null ? -r.secTop : r.y - secTop).toFixed(2), uw: uws ? uws[i] : undefined }));

/** Positions held for SETTLE_MS: every half viewport from one viewport above the section to half a viewport past its end. */
export function settledGrid(geo) {
  const us = [];
  for (let u = -geo.vh; u <= geo.secH + geo.vh / 2; u += geo.vh / 2) us.push(Math.round(u));
  return us;
}

async function runArm(engine, site, origin, path, w, fontCss) {
  const env = envOf(w);
  const s = await engine.open(env, { origin, path, init: PIN_SRC });
  try {
    const page = s.page;
    if (site === 'rewrite' && fontCss) await page.evaluate(injectFontsInPage, { css: fontCss, family: FAMILY });
    const ready = await page.evaluate(waitReady, { site, capMs: CAP_MS[site] });
    const sel = SEL[site];
    const run = (op, extra = {}) => page.evaluate(navScrollInPage, { op, sel, ...extra });
    await run('warm');
    const geo = await run('describe');
    if (!geo.nav || !geo.sticky || !geo.section) return { site, ready, geo, absent: true };
    const arm = { site, ready: { ready: ready.ready, splash: ready.splash }, geo };
    const us = gridOf(geo);
    const usUp = [...us].reverse();
    const ys = (list) => list.map((u) => Math.round(geo.secTop + u));
    arm.sweepDown = withU(await run('sweep', { ys: ys(us), frames: FRAMES }), geo.secTop, us);
    arm.sweepUp = withU(await run('sweep', { ys: ys(usUp), frames: FRAMES }), geo.secTop, usUp);
    const sgu = settledGrid(geo);
    arm.settled = withU(await run('settled', { ys: ys(sgu), settleMs: SETTLE_MS }), geo.secTop, sgu);
    arm.transitions = [];
    const seen = new Set();
    for (const [dir, sweep] of [['down', arm.sweepDown], ['up', arm.sweepUp]]) {
      for (const t of transitions(sweep)) {
        if (t.yBefore == null) continue;
        const key = `${dir}:${t.to ? 'on' : 'off'}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const rec = await run('transition', { yBefore: t.yBefore, yAfter: t.y, settleMs: SETTLE_MS, ms: TRANS_MS });
        arm.transitions.push({ key, dir, to: t.to, u: t.u, uBefore: t.uBefore, ...rec });
      }
    }
    // real wheel events: down through the section and out, then back
    await page.mouse.move(Math.round(w.width / 2), Math.round(w.height / 2));
    await run('sweep', { ys: [Math.round(geo.secTop - geo.vh)], frames: FRAMES });
    await sleep(SETTLE_MS);
    await run('wheelStart');
    const n = Math.ceil((geo.secH + geo.vh * 1.5) / WHEEL_PX);
    for (let i = 0; i < n; i++) { await page.mouse.wheel(0, WHEEL_PX); await sleep(WHEEL_MS); }
    await sleep(SETTLE_MS);
    for (let i = 0; i < n; i++) { await page.mouse.wheel(0, -WHEEL_PX); await sleep(WHEEL_MS); }
    await sleep(SETTLE_MS);
    arm.wheel = withU(await run('wheelStop'), geo.secTop);
    return arm;
  } finally {
    await s.close().catch(() => {});
  }
}

export async function runNavScroll({ engineName, outDir, widthIds = WIDTHS.map((w) => w.id) }) {
  const lock = JSON.parse(readFileSync(resolve(GATE_PKG, '../../snapshot.lock.json'), 'utf8'));
  const dist = siteDist();
  const buildInfo = JSON.parse(readFileSync(join(dist, 'build-info.json'), 'utf8'));
  const snap = snapshotRoot();
  const servers = { orig: await startServer(snap), rewrite: await startOverlayServer(dist, snap) };
  const fontCss = await originalFontFaces(snap, [FAMILY]);
  if (fontCss === '') throw new Error(`no @font-face for ${FAMILY} in the snapshot's CSS`);
  const engine = await LAUNCHERS[engineName]();
  const widths = WIDTHS.filter((w) => widthIds.includes(w.id));
  const cases = [];
  for (const w of widths) {
    const t0 = Date.now();
    const [orig, rewrite] = await Promise.all(['orig', 'rewrite'].map((site) =>
      runArm(engine, site, servers[site].origin, '/', w, fontCss).catch((e) => ({ site, error: String(e.message).split('\n')[0] }))));
    cases.push({ id: w.id, width: w.width, height: w.height, orig, rewrite });
    log(`  ${engineName}: ${w.id} done in ${Math.round((Date.now() - t0) / 1000)} s`);
  }
  const header = {
    schema: 'fw.nav-scroll/1', engine: engineName, browser: await engine.version(),
    snapshot: lock.snapshot, site: { buildId: buildInfo.buildId, configHash: buildInfo.configHash },
    params: { STEP, FRAMES, SETTLE_MS, TRANS_MS, WHEEL_PX, WHEEL_MS },
  };
  await engine.close();
  await Promise.all(Object.values(servers).map((s) => s.close()));
  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `${engineName}.navscroll.json`);
  writeFileSync(file, JSON.stringify({ header, cases }) + '\n');
  log(`wrote ${file}`);
  return file;
}
