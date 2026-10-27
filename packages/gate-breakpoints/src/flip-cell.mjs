import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PKG, siteDist, startServer } from './serve.mjs';
import { PIN_SRC } from './page.mjs';

export const GOLDEN = resolve(PKG, '../contracts/golden/morph-geom.jsonl');

export function loadFlipCell(path = GOLDEN) {
  const lines = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const cell = lines.find((l) => l.fn === 'flipCell')?.out;
  const bands = lines.filter((l) => l.fn === 'flipBand').map((l) => ({ w: l.in.w, h: l.in.h, ...l.out }));
  if (!cell || bands.length === 0) throw new Error(`no flipCell or flipBand line in ${path}`);
  return { ...cell, bands };
}

const edges = (r) => [r.x, r.y, r.x + r.width, r.y + r.height];

export function readRects() {
  const nav = document.querySelector('[data-fw="nav"]');
  const rect = (e) => (e ? e.getBoundingClientRect().toJSON() : null);
  const ks = ['K0', 'K1', 'K2', 'K3'].map((n) => nav.querySelector(`[data-mg="${n}"]`));
  let pill = rect(nav);
  if (ks.every(Boolean)) {
    const rs = ks.map((k) => k.getBoundingClientRect());
    const x = Math.max(...rs.map((r) => r.left));
    const y = Math.max(...rs.map((r) => r.top));
    const r = Math.min(...rs.map((q) => q.right));
    const b = Math.min(...rs.map((q) => q.bottom));
    pill = { x, y, width: r - x, height: b - y };
  }
  const cols = [...document.querySelectorAll('[data-fw="morph-columns"] > div')].filter((c) => getComputedStyle(c).display !== 'none');
  const lang = nav.querySelector('[data-fw="nav-actions"] > :first-child');
  return {
    columns: cols.map(rect),
    images: cols.flatMap((c) => [...c.querySelectorAll('img')].map(rect)),
    pill,
    lang: rect(lang),
    earn: rect(nav.querySelector('[data-fw="nav-earn"]')),
    actions: rect(nav.querySelector('[data-fw="nav-actions"]')),
    flip: document.documentElement.classList.contains('is-flip'),
    variant: window.__fw?.config?.variants?.['morph.geom'] ?? null,
    navClass: nav.className,
  };
}

export function judgeRects(base, flag, band, tolPx, settled = true, expectFlip = null) {
  const bad = [];
  if (expectFlip !== null && flag.flip !== expectFlip) bad.push(`flip class ${flag.flip ? 'on' : 'off'}, expected ${expectFlip ? 'on' : 'off'}`);
  const cmp = (id, a, b, pick = [0, 1, 2, 3]) => {
    if (!a || !b) {
      if (!!a !== !!b) bad.push(`${id}: ${a ? 'flag lacks it' : 'base lacks it'}`);
      return;
    }
    const d = Math.max(...pick.map((i) => Math.abs(edges(a)[i] - edges(b)[i])));
    if (!(d <= tolPx)) bad.push(`${id}: edges differ by ${d.toFixed(2)} px (> ${tolPx})`);
  };
  if (flag.columns.length !== band.cols) bad.push(`columns: ${flag.columns.length}, expected ${band.cols}`);
  cmp('nav', base.pill, flag.pill);
  cmp('lang', base.lang, flag.lang, settled ? [0, 1, 2, 3] : [1, 3]);
  cmp('earn', base.earn, flag.earn, [1, 3]);
  cmp('actions', base.actions, flag.actions, [2]);
  if (base.images.length !== flag.images.length) bad.push(`images: ${flag.images.length}, base ${base.images.length}`);
  const n = Math.min(base.images.length, flag.images.length);
  for (let i = 0; i < n; i++) cmp(`image${i}`, base.images[i], flag.images[i], [0, 2]);
  const m = Math.min(base.columns.length, flag.columns.length);
  for (let i = 0; i < m; i++) cmp(`column${i}`, base.columns[i], flag.columns[i], [0]);
  for (let i = 1; i < flag.columns.length; i++) {
    const a = flag.columns[i - 1];
    const b = flag.columns[i];
    if (a && b && !(b.x > a.x + 1)) bad.push(`column${i}: not beside column${i - 1} (left ${b.x.toFixed(1)}, previous ${a.x.toFixed(1)})`);
  }
  return bad;
}

function pin(m) {
  const nav = document.querySelector('[data-fw="nav"]');
  nav.classList.toggle('is-on-dark', m > 0.2 || !!nav.dataset.fwKeepDark);
  nav.style.setProperty('--morph', String(m));
  nav.dataset.fwMorph = String(m);
}

// Scrolls in steps, then keeps asking for the target until the page is there and has stayed for 3 checks: one scrollTo can stop short while the
// page is locked or still growing (run 40530697810, WebKit 1280x800: the base page stayed at y 2236 while the flag page was at the top, so its
// nav was scroll-hidden at y -72 and the m=0 reading compared two different scroll positions).
async function stepScroll(to) {
  const target = () => (to === 'bottom' ? document.documentElement.scrollHeight - window.innerHeight : 0);
  const from = window.scrollY;
  for (let i = 1; i <= 14; i++) {
    window.scrollTo(0, from + ((target() - from) * i) / 14);
    await new Promise((r) => setTimeout(r, 90));
  }
  let steady = 0;
  let tries = 0;
  for (; tries < 80 && steady < 3; tries++) {
    window.scrollTo(0, target());
    await new Promise((r) => setTimeout(r, 250));
    steady = Math.abs(window.scrollY - target()) < 2 ? steady + 1 : 0;
  }
  return { reached: steady >= 3, y: Math.round(window.scrollY), tries };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function readLive() {
  const hz = await new Promise((res) => {
    let n = 0;
    const t0 = performance.now();
    const f = () => {
      n++;
      if (performance.now() - t0 < 300) requestAnimationFrame(f);
      else res(n / ((performance.now() - t0) / 1000));
    };
    requestAnimationFrame(f);
  });
  const attrs = (e) => (e ? [...e.attributes].map((a) => `${a.name}=${a.value}`).filter((a) => !a.startsWith('style') && !a.startsWith('class')).join(' ') : null);
  const nav = document.querySelector('[data-fw="nav"]');
  return {
    vis: document.visibilityState,
    focus: document.hasFocus(),
    hz: Math.round(hz),
    scrollY: Math.round(window.scrollY),
    maxY: Math.round(document.documentElement.scrollHeight - window.innerHeight),
    panel: attrs(document.querySelector('[data-fw="morph-panel"]')),
    nav: attrs(nav),
    navClass: nav ? nav.className : null,
    morph: nav ? nav.dataset.fwMorph ?? null : null,
  };
}

// The morph panel mounts and unmounts on timers and an IntersectionObserver, so two pages loaded side by side can differ in whether the columns exist
// at all (run 40525667335: WebKit 1280x800 base unmounted, flag mounted; 1920x1080 the reverse). A reading is only valid once both agree.
export async function waitMountAgree(a, b, limitMs = 20000) {
  const mounted = (pg) => pg.evaluate(() => !!document.querySelector('[data-fw="morph-panel"]'));
  const t0 = Date.now();
  let run = 0;
  let last = [null, null];
  while (Date.now() - t0 < limitMs) {
    last = [await mounted(a), await mounted(b)];
    run = last[0] === last[1] ? run + 1 : 0;
    if (run >= 3) return { agree: true, a: last[0], b: last[1], waitedMs: Date.now() - t0 };
    await sleep(500);
  }
  return { agree: false, a: last[0], b: last[1], waitedMs: Date.now() - t0 };
}

export async function runFlipCell({ engineName, fw, outDir, bandFilter = null, mutation = null, expectFail = false, reportOnly = false }) {
  const { mutatePage, MUTATION_OWNER } = await import('./flip-verify.mjs');
  const { rewritePathFor } = await import('../../visual-diff/src/run.mjs');
  const { LAUNCHERS } = await import('../../visual-diff/src/engines.mjs');
  const cell = loadFlipCell();
  const dist = siteDist();
  const flag = rewritePathFor(dist, fw);
  const server = await startServer(dist);
  const engine = await LAUNCHERS[engineName]();
  const rows = [];
  try {
    for (const band of cell.bands.filter((b) => !bandFilter || bandFilter.includes(`${b.w}x${b.h}`))) {
      const env = {
        width: band.w, height: band.h, deviceWidth: band.w, deviceHeight: band.h, dpr: band.w <= 640 ? 3 : 1,
        hover: band.w <= 1024 ? 'none' : 'hover', pointer: band.w <= 1024 ? 'coarse' : 'fine', colorScheme: 'light', reducedMotion: 'no-preference',
      };
      const timed = fw.includes('morph.tween:geom-timed');
      const open = async (path) => {
        const s = await engine.open(env, { origin: server.origin, path, init: PIN_SRC });
        await s.page.evaluate(async () => {
          for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await new Promise((r) => setTimeout(r, 50));
        });
        if (!timed) await s.page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
        await sleep(1800);
        return s;
      };
      const A = await open('/');
      const B = await open(flag.path + flag.search);
      try {
        const applied = mutation ? await B.page.evaluate(mutatePage, mutation) : null;
        if (mutation && !applied) process.stderr.write(`mutation ${mutation} changed nothing on ${band.w}x${band.h}\n`);
        let mount = null;
        const steps = timed ? [[1, 'bottom'], [0, 'top']] : cell.ms.map((m) => [m, null]);
        for (const [m, to] of steps) {
          if (to) {
            const sa = await A.page.evaluate(stepScroll, to);
            const sb = await B.page.evaluate(stepScroll, to);
            await sleep(2600);
            mount = { ...(await waitMountAgree(A.page, B.page)), scroll: { base: sa, flag: sb } };
          } else {
            await A.page.evaluate(pin, m);
            await B.page.evaluate(pin, m);
            await sleep(1200);
          }
          const liveA = timed ? await A.page.evaluate(readLive) : null;
          const liveB = timed ? await B.page.evaluate(readLive) : null;
          const base = await A.page.evaluate(readRects);
          const got = await B.page.evaluate(readRects);
          const skipped = timed && m > 0.2 && !got.flip ? 'flip not engaged: the take guard decided at push start (A5)'
            : timed && mount && !(mount.scroll.base.reached && mount.scroll.flag.reached) ? `scroll did not reach ${to} (base y ${mount.scroll.base.y}, flag y ${mount.scroll.flag.y}): the pages are not at the same place`
            : timed && mount && !mount.agree ? `panel mounted on one page only (base ${mount.a}, flag ${mount.b}): its lazy mount is timer-driven, not the flip` : null;
          const bandNow = timed && mount && mount.agree && !mount.b ? { ...band, cols: 0 } : band;
          const bad = skipped ? [] : judgeRects(base, got, bandNow, cell.tolPx, m === 0 || m === 1, m > 0.2 ? true : m === 0 ? false : null);
          let recheck = null;
          if (timed && bad.length) {
            await A.page.bringToFront();
            await sleep(1500);
            await B.page.bringToFront();
            await sleep(1500);
            const base2 = await A.page.evaluate(readRects);
            const got2 = await B.page.evaluate(readRects);
            const bad2 = judgeRects(base2, got2, bandNow, cell.tolPx, m === 0 || m === 1, m > 0.2 ? true : m === 0 ? false : null);
            recheck = { ok: bad2.length === 0, bad: bad2, live: [await A.page.evaluate(readLive), await B.page.evaluate(readLive)] };
          }
          rows.push({ band: `${band.w}x${band.h}`, m, flipClass: got.flip, ok: bad.length === 0, bad, ...(skipped ? { skipped } : {}), ...(bad.length ? { base, flag: got } : {}), ...(timed ? { live: { base: liveA, flag: liveB }, mount } : {}), ...(recheck ? { recheck } : {}), ...(mutation ? { applied } : {}) });
          process.stderr.write(`${band.w}x${band.h} m=${m} flip=${got.flip} variant=${got.variant} ${skipped ? `skipped (${skipped})` : bad.length === 0 ? 'ok' : bad.join('; ')}\n`);
        }
      } finally {
        await A.close().catch(() => {});
        await B.close().catch(() => {});
      }
    }
  } finally {
    await engine.close?.();
    server.close?.();
  }
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, `flip-${engineName}${mutation ? `-${mutation}` : ''}.json`), `${JSON.stringify({ fw, engine: engineName, mutation, tolPx: cell.tolPx, ms: cell.ms, rows }, null, 1)}\n`);
  const failed = rows.filter((r) => !r.ok).length;
  const skipped = rows.filter((r) => r.skipped).length;
  if (mutation) {
    const owner = MUTATION_OWNER[mutation];
    const hit = rows.filter((r) => r.bad.some(owner)).length;
    console.log(`flip cell ${engineName} mutation ${mutation}: ${hit > 0 ? 'caught' : 'NOT caught'} (${hit} of ${rows.length} readings fail on its reading; ${failed} fail in all)`);
    return expectFail ? hit > 0 : true;
  }
  console.log(`flip cell ${engineName} ${fw}: ${failed === 0 ? 'pass' : 'fail'} (${rows.length} readings, ${failed} failed, ${skipped} skipped)${reportOnly ? ' reported only, exit 0' : ''}`);
  return reportOnly || failed === 0;
}
