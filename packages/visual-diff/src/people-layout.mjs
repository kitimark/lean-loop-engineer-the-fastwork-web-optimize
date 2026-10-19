// People-section layout probe (task people-layout-shift): where does the people section's layout differ between the original
// and the port, and when does it shift? Reports facts only; the comparison is people-layout-analyze.mjs. Reuses the gate's
// servers, the visual-diff engines and the gate's readiness wait by import; none of them is changed. The port is served as
// built (its own fonts and images, no overlay, no font injection): the question is what a visitor sees.
//   load     the whole #people subtree (every element: path, tag, class, document rect, computed style) at scrollY 0 once the
//            arm is ready, before any scroll
//   cold     one deterministic scroll from the top down through the section and half a viewport past it (COLD_STEP px per
//            step, FRAMES native rAF per step); every frame records the tracked boxes (KEY) and the section's siblings
//   hold     positions held (HOLD_MS) from one viewport above the section to half a viewport past it, a subtree dump (rects only) at each
//   warm     the page scrolled once from top to bottom and back, then `load`-style dump, the scroll again and the holds again
// In Chromium a PerformanceObserver('layout-shift', buffered) installed before any page script collects every entry with its
// sources (node description, previous and current rect) from navigation on. WebKit has no such entry type; its shifts are the
// per-frame box deltas of the same elements (analysis).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PIN_SRC, waitReady } from '../../gate-breakpoints/src/page.mjs';
import { PKG as GATE_PKG, siteDist, snapshotRoot, startServer } from '../../gate-breakpoints/src/serve.mjs';
import { LAUNCHERS } from './engines.mjs';

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const COLD_STEP = 32;
export const FRAMES = 2;
export const HOLD_MS = 450;
const CAP_MS = { orig: 20000, rewrite: 15000 };

/** The widths of the task: three desktop screens, the smallest desktop width above the 861 px breakpoint and a touch phone. */
export const WIDTHS = [
  { id: 'w1920', width: 1920, height: 1080 },
  { id: 'w1440', width: 1440, height: 900 },
  { id: 'w1280', width: 1280, height: 800 },
  { id: 'w861', width: 861, height: 900 },
  { id: 'w401', width: 401, height: 860, touch: true },
];

const envOf = (w) => ({
  width: w.width, height: w.height, deviceWidth: w.width, deviceHeight: w.height, dpr: w.touch ? 2 : 1,
  reducedMotion: 'no-preference', colorScheme: 'light', hover: w.touch ? 'none' : 'hover', pointer: w.touch ? 'coarse' : 'fine',
});

/**
 * Init script (after PIN_SRC): the layout-shift collector. A shift entry is stored with a description of every source node taken
 * at once (the node may be gone later). Does nothing where the entry type does not exist (WebKit).
 */
export const LS_SRC = `(() => {
  const ls = { entries: [], cur: { ph: 'load', y: 0 }, supported: false };
  window.__ls = ls;
  const q = (r) => (r ? [+r.x.toFixed(2), +r.y.toFixed(2), +r.width.toFixed(2), +r.height.toFixed(2)] : null);
  const desc = (n) => {
    if (!n || n.nodeType !== 1) return n ? '#text' : null;
    const parts = [];
    for (let e = n, i = 0; e && e.nodeType === 1 && i < 6; e = e.parentElement, i++) {
      const k = e.parentElement ? Array.prototype.indexOf.call(e.parentElement.children, e) : 0;
      parts.push(e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + ':' + k);
      if (e.id === 'people') break;
    }
    return parts.reverse().join('>') + ' .' + String(n.className && n.className.baseVal !== undefined ? n.className.baseVal : n.className).split(' ')[0];
  };
  try {
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        ls.entries.push({
          t: +e.startTime.toFixed(1), v: +e.value.toFixed(5), inp: e.hadRecentInput, y: window.scrollY, ph: ls.cur.ph,
          src: (e.sources || []).map((s) => ({ n: desc(s.node), p: q(s.previousRect), c: q(s.currentRect) })),
        });
      }
    }).observe({ type: 'layout-shift', buffered: true });
    ls.supported = true;
  } catch (err) { ls.supported = false; }
})();`;

/**
 * Page side. One self-contained function (Playwright serialises it); `arg.op` picks the step. It reports; it decides nothing.
 * Boxes are [x, y, w, h] in document coordinates (rect plus scroll), 2 decimals.
 */
export async function peopleLayoutInPage(arg) {
  const { op } = arg;
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const go = (y) => window.scrollTo({ top: y, behavior: 'instant' });
  const r2 = (n) => +n.toFixed(2);
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return [r2(r.left + window.scrollX), r2(r.top + window.scrollY), r2(r.width), r2(r.height)];
  };
  const cn = (el) => (typeof el.className === 'string' ? el.className : (el.className && el.className.baseVal) || '');
  const sec = () => document.getElementById('people');

  // The tracked boxes, found by structure so that one function serves both arms (the class names differ, the shape does not).
  const keyOf = () => {
    const s = sec();
    if (!s) return null;
    const k = { section: s };
    const card = s.firstElementChild;
    k.card = card;
    k.header = card && card.children[0];
    k.headerCopy = k.header && k.header.firstElementChild;
    k.title = document.getElementById('future-heading');
    k.titleWords = k.title && k.title.children[1];
    k.o = s.querySelector('[data-fw="people-o"], .start-selling-future-people-o');
    k.oStage = k.o && k.o.firstElementChild;
    k.oStack = k.oStage && k.oStage.lastElementChild;
    k.copy = k.title && k.title.nextElementSibling;
    k.showcase = card && card.children[1];
    k.profile = document.getElementById('profile-showcase');
    k.sticky = k.profile && k.profile.firstElementChild;
    k.chrome = k.sticky && k.sticky.firstElementChild;
    k.tabs = k.chrome && k.chrome.children[0];
    k.deck = k.chrome && k.chrome.children[1];
    k.shell = k.deck && (k.deck.querySelector('[data-profession="' + k.deck.getAttribute('data-active') + '"]') || k.deck.firstElementChild);
    k.panel = k.shell && k.shell.firstElementChild;
    k.pill = card && card.children[2];
    k.proof = k.pill && k.pill.firstElementChild;
    k.avatars = k.proof && k.proof.firstElementChild;
    k.pillBtn = k.pill && k.pill.lastElementChild;
    return k;
  };
  // The non-identity transforms on the way from an element to the root: a box that moves while this string changes is moving by
  // transform (the scroll-driven entrance and exit of the card), not by layout.
  const tfChain = (el) => {
    const out = [];
    for (let e = el; e && e.nodeType === 1; e = e.parentElement) {
      const t = getComputedStyle(e).transform;
      if (t !== 'none') out.push(t);
    }
    return out.join('|');
  };
  const sample = () => {
    const k = keyOf();
    const s = sec();
    const kb = {};
    const tf = {};
    if (k) for (const n of Object.keys(k)) { kb[n] = box(k[n]); tf[n] = k[n] ? tfChain(k[n]) : ''; }
    const sib = s && s.parentElement ? [...s.parentElement.children].map((e) => { const b = box(e); return [b[1], b[3]]; }) : [];
    return { t: +performance.now().toFixed(2), y: window.scrollY, dh: document.documentElement.scrollHeight, k: kb, tf, sib };
  };

  if (op === 'describe') {
    const s = sec();
    const b = box(s);
    return {
      found: !!s, vw: document.documentElement.clientWidth, vh: window.innerHeight,
      docH: document.documentElement.scrollHeight, secTop: b ? b[1] : null, secH: b ? b[3] : null,
      siblings: s && s.parentElement ? [...s.parentElement.children].map((e) => `${e.tagName.toLowerCase()}.${cn(e).split(' ')[0]}${e.id ? '#' + e.id : ''}`) : [],
      fonts: [...document.fonts].map((f) => `${f.family}|${f.weight}|${f.style}|${f.status}`),
      scrollY: window.scrollY,
    };
  }

  if (op === 'dump') {
    const s = sec();
    if (!s) return { absent: true };
    const nodes = [];
    const walk = (el, path) => {
      const rec = { p: path, g: el.tagName.toLowerCase(), c: cn(el).slice(0, 80), b: box(el) };
      if (el.tagName === 'IMG') {
        rec.img = { nw: el.naturalWidth, nh: el.naturalHeight, done: el.complete, src: (el.currentSrc || el.src || '').replace(location.origin, '').slice(0, 80), load: el.loading, wa: el.getAttribute('width'), ha: el.getAttribute('height') };
      }
      const tf = getComputedStyle(el).transform;
      if (tf !== 'none') rec.tf = tf;
      let text = '';
      for (const n of el.childNodes) if (n.nodeType === 3) text += n.nodeValue;
      if (text.trim() !== '') {
        const rg = document.createRange();
        rg.selectNodeContents(el);
        const rs = [...rg.getClientRects()].filter((r) => r.width > 0);
        rec.tx = { n: text.trim().length, lines: new Set(rs.map((r) => Math.round(r.top))).size, w: rs.length ? r2(Math.max(...rs.map((r) => r.right)) - Math.min(...rs.map((r) => r.left))) : 0 };
      }
      if (arg.style) {
        const cs = getComputedStyle(el);
        rec.s = {
          d: cs.display, ps: cs.position, t: cs.top, w: cs.width, h: cs.height, mg: cs.margin, pd: cs.padding, gap: cs.gap,
          ff: cs.fontFamily.split(',')[0].replace(/["']/g, '').trim(), fs: cs.fontSize, lh: cs.lineHeight, fw: cs.fontWeight, ls: cs.letterSpacing,
          ar: cs.aspectRatio, of: cs.objectFit, tf: cs.transform === 'none' ? '' : cs.transform, ov: cs.overflow, bs: cs.boxSizing, cv: cs.contentVisibility,
        };
      }
      nodes.push(rec);
      let i = 0;
      for (const ch of el.children) walk(ch, path + '.' + i++);
    };
    walk(s, '0');
    const sibs = s.parentElement ? [...s.parentElement.children].map((e) => ({ g: e.tagName.toLowerCase(), c: cn(e).slice(0, 60), b: box(e) })) : [];
    return { scrollY: window.scrollY, docH: document.documentElement.scrollHeight, vw: document.documentElement.clientWidth, vh: window.innerHeight, nodes, sibs };
  }

  if (op === 'phase') {
    window.__ls.cur = { ph: arg.ph, y: window.scrollY };
    return true;
  }

  if (op === 'scrollpass') {
    window.__ls.cur = { ph: arg.ph, y: 0 };
    const frames = [];
    go(arg.ys[0]);
    await wait(250);
    for (const y of arg.ys) {
      go(y);
      for (let i = 0; i < arg.frames; i++) await raf();
      window.__ls.cur = { ph: arg.ph, y: window.scrollY };
      frames.push({ want: y, ...sample() });
    }
    return frames;
  }

  if (op === 'warm') {
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

  if (op === 'ls') {
    return { supported: window.__ls.supported, entries: window.__ls.entries };
  }
  throw new Error(`unknown op ${op}`);
}

/** The positions held (document coordinates of the scroll): from one viewport above the section to half a viewport past it, every half viewport. */
export function holdGrid(geo) {
  const ys = [];
  for (let u = -geo.vh; u <= geo.secH + geo.vh / 2; u += geo.vh / 2) ys.push(Math.max(0, Math.round(geo.secTop + u)));
  return [...new Set(ys)];
}

/** The cold pass: from the top of the page to half a viewport past the end of the section. */
export function coldGrid(geo) {
  const ys = [];
  const end = geo.secTop + geo.secH + geo.vh / 2;
  for (let y = 0; y <= end; y += COLD_STEP) ys.push(y);
  return ys;
}

async function runArm(engine, site, origin, w, rep) {
  const env = envOf(w);
  const s = await engine.open(env, { origin, path: '/', init: `${PIN_SRC}\n${LS_SRC}` });
  try {
    const page = s.page;
    const ready = await page.evaluate(waitReady, { site, capMs: CAP_MS[site] });
    const run = (op, extra = {}) => page.evaluate(peopleLayoutInPage, { op, ...extra });
    const geo = await run('describe');
    if (!geo.found) return { site, rep, ready, geo, absent: true };
    const arm = { site, rep, ready: { ready: ready.ready, splash: ready.splash }, geo };
    await run('phase', { ph: 'load' });
    arm.load = await run('dump', { style: true });
    const ys = coldGrid(geo);
    const holds = holdGrid(geo);
    arm.coldFrames = await run('scrollpass', { ys, frames: FRAMES, ph: 'cold' });
    arm.coldHolds = [];
    for (const y of holds) {
      await run('phase', { ph: 'hold' });
      const r = await page.evaluate(async ({ y, holdMs }) => {
        window.scrollTo({ top: y, behavior: 'instant' });
        await new Promise((res) => setTimeout(res, holdMs));
        return y;
      }, { y, holdMs: HOLD_MS });
      arm.coldHolds.push({ want: r, ...(await run('dump', { style: false })) });
    }
    arm.lsCold = await run('ls');
    await run('warm');
    await run('phase', { ph: 'warm' });
    arm.warmLoad = await run('dump', { style: true });
    arm.warmFrames = await run('scrollpass', { ys, frames: FRAMES, ph: 'warm' });
    arm.warmHolds = [];
    for (const y of holds) {
      const r = await page.evaluate(async ({ y, holdMs }) => {
        window.scrollTo({ top: y, behavior: 'instant' });
        await new Promise((res) => setTimeout(res, holdMs));
        return y;
      }, { y, holdMs: HOLD_MS });
      arm.warmHolds.push({ want: r, ...(await run('dump', { style: false })) });
    }
    arm.ls = await run('ls');
    return arm;
  } finally {
    await s.close().catch(() => {});
  }
}

export async function runPeopleLayout({ engineName, outDir, widthIds = WIDTHS.map((w) => w.id), reps = 2 }) {
  const lock = JSON.parse(readFileSync(resolve(GATE_PKG, '../../snapshot.lock.json'), 'utf8'));
  const dist = siteDist();
  const buildInfo = JSON.parse(readFileSync(join(dist, 'build-info.json'), 'utf8'));
  const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(dist) };
  const engine = await LAUNCHERS[engineName]();
  const widths = WIDTHS.filter((w) => widthIds.includes(w.id));
  const cases = [];
  for (const w of widths) {
    for (let rep = 0; rep < reps; rep++) {
      const t0 = Date.now();
      const [orig, rewrite] = await Promise.all(['orig', 'rewrite'].map((site) =>
        runArm(engine, site, servers[site].origin, w, rep).catch((e) => ({ site, rep, error: String(e.message).split('\n')[0] }))));
      cases.push({ id: w.id, width: w.width, height: w.height, rep, orig, rewrite });
      log(`  ${engineName}: ${w.id} rep ${rep} done in ${Math.round((Date.now() - t0) / 1000)} s`);
    }
  }
  const header = {
    schema: 'fw.people-layout/1', engine: engineName, browser: await engine.version(),
    snapshot: lock.snapshot, site: { buildId: buildInfo.buildId, configHash: buildInfo.configHash },
    params: { COLD_STEP, FRAMES, HOLD_MS, reps },
  };
  await engine.close();
  await Promise.all(Object.values(servers).map((s) => s.close()));
  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `${engineName}.people-layout.json`);
  writeFileSync(file, JSON.stringify({ header, cases }) + '\n');
  log(`wrote ${file}`);
  return file;
}
