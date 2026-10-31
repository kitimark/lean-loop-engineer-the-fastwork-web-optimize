import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PKG, siteDist, startServer } from './serve.mjs';
import { PIN_SRC } from './page.mjs';
import { LIMITS, bound, call, cellsPass, closeBounded, takeCell, waitCell } from './bounded.mjs';

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
    earnW: nav ? Math.round(nav.querySelector('[data-fw="nav-earn"]')?.getBoundingClientRect().width ?? -1) : null,
  };
}

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
  const faults = [];
  const outcomes = [];
  try {
    for (const band of cell.bands.filter((b) => !bandFilter || bandFilter.includes(`${b.w}x${b.h}`))) {
      const env = {
        width: band.w, height: band.h, deviceWidth: band.w, deviceHeight: band.h, dpr: band.w <= 640 ? 3 : 1,
        hover: band.w <= 1024 ? 'none' : 'hover', pointer: band.w <= 1024 ? 'coarse' : 'fine', colorScheme: 'light', reducedMotion: 'no-preference',
      };
      const timed = fw.includes('morph.tween:geom-timed');
      const openPage = (path) => bound('open page', LIMITS.callMs, async () => {
        const s = await engine.open(env, { origin: server.origin, path, init: PIN_SRC });
        await s.page.evaluate(async () => {
          for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await new Promise((r) => setTimeout(r, 50));
        });
        if (!timed) await s.page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
        await sleep(1800);
        return s;
      });
      let pair = null;
      const ensure = async () => {
        if (pair) return pair;
        const A = await openPage('/');
        let B;
        try {
          B = await openPage(flag.path + flag.search);
        } catch (err) {
          await closeBounded('close base page', A);
          throw err;
        }
        const applied = mutation ? await call('mutate', B.page, mutatePage, mutation) : null;
        if (mutation && !applied) process.stderr.write(`mutation ${mutation} changed nothing on ${band.w}x${band.h}\n`);
        pair = { A, B, applied };
        return pair;
      };
      const drop = async () => {
        const p = pair;
        pair = null;
        if (!p) return;
        await closeBounded('close base page', p.A);
        await closeBounded('close flag page', p.B);
      };
      try {
        const steps = timed ? [[1, 'bottom'], [0, 'top']] : cell.ms.map((m) => [m, null]);
        for (const [m, to] of steps) {
          const name = `${band.w}x${band.h} m=${m}`;
          const taken = await takeCell(name, async () => {
            const { A, B, applied } = await ensure();
            let mount = null;
            let ready = null;
            if (to) {
              const sa = await call('scroll base', A.page, stepScroll, to);
              const sb = await call('scroll flag', B.page, stepScroll, to);
              await sleep(2600);
              mount = { ...(await bound('mount agree', LIMITS.readyMs + LIMITS.callMs, () => waitMountAgree(A.page, B.page))), scroll: { base: sa, flag: sb } };
            } else {
              await call('pin base', A.page, pin, m);
              await call('pin flag', B.page, pin, m);
              await sleep(1200);
              ready = await waitCell(A.page, B.page, band.cols);
            }
            const liveA = timed ? await call('live base', A.page, readLive) : null;
            const liveB = timed ? await call('live flag', B.page, readLive) : null;
            const base = await call('read base', A.page, readRects);
            const got = await call('read flag', B.page, readRects);
            const skipped = timed && m > 0.2 && !got.flip ? 'flip not engaged: the take guard decided at push start (A5)'
              : timed && mount && !(mount.scroll.base.reached && mount.scroll.flag.reached) ? `scroll did not reach ${to} (base y ${mount.scroll.base.y}, flag y ${mount.scroll.flag.y}): the pages are not at the same place`
              : timed && mount && !mount.agree ? `panel mounted on one page only (base ${mount.a}, flag ${mount.b}): its lazy mount is timer-driven, not the flip` : null;
            const bandNow = timed && mount && mount.agree && !mount.b ? { ...band, cols: 0 } : band;
            const bad = skipped ? [] : judgeRects(base, got, bandNow, cell.tolPx, m === 0 || m === 1, m > 0.2 ? true : m === 0 ? false : null);
            let recheck = null;
            if (timed && bad.length) {
              await bound('bring base to front', LIMITS.callMs, () => A.page.bringToFront());
              await sleep(1500);
              await bound('bring flag to front', LIMITS.callMs, () => B.page.bringToFront());
              await sleep(1500);
              const base2 = await call('reread base', A.page, readRects);
              const got2 = await call('reread flag', B.page, readRects);
              const bad2 = judgeRects(base2, got2, bandNow, cell.tolPx, m === 0 || m === 1, m > 0.2 ? true : m === 0 ? false : null);
              recheck = { ok: bad2.length === 0, bad: bad2, live: [await call('live base', A.page, readLive), await call('live flag', B.page, readLive)] };
            }
            const row = { band: `${band.w}x${band.h}`, m, flipClass: got.flip, ok: bad.length === 0, bad, ...(skipped ? { skipped } : {}), ...(bad.length ? { base, flag: got } : {}), ...(timed ? { live: { base: liveA, flag: liveB }, mount } : {}), ...(ready ? { ready: { step: ready.step, waitedMs: ready.waitedMs } } : {}), ...(recheck ? { recheck } : {}), ...(mutation ? { applied } : {}) };
            const line = `${band.w}x${band.h} m=${m} flip=${got.flip} variant=${got.variant} ${skipped ? `skipped (${skipped})` : bad.length === 0 ? 'ok' : bad.join('; ')}${ready && ready.step === 'late' ? ` [ready wait ran out after ${ready.waitedMs} ms]` : ''}`;
            return { ok: row.ok, value: { row, line } };
          }, { onFault: drop });
          faults.push(...taken.faults);
          outcomes.push(taken.outcome);
          if (taken.outcome === 'exhausted') {
            const last = taken.faults[taken.faults.length - 1];
            const row = { band: `${band.w}x${band.h}`, m, flipClass: null, ok: false, bad: [`no reading in ${taken.attempts} attempts (${last ? last.error : 'no fault noted'})`], exhausted: true };
            rows.push(row);
            process.stderr.write(`${name} ${row.bad[0]}\n`);
          } else {
            rows.push(taken.value.row);
            process.stderr.write(`${taken.value.line}\n`);
          }
        }
      } finally {
        await drop();
      }
    }
  } finally {
    await closeBounded('close browser', engine);
    server.close?.();
  }
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, `flip-${engineName}${mutation ? `-${mutation}` : ''}.json`), `${JSON.stringify({ fw, engine: engineName, mutation, tolPx: cell.tolPx, ms: cell.ms, limits: LIMITS, faults, rows }, null, 1)}\n`);
  const failed = rows.filter((r) => !r.ok).length;
  const skipped = rows.filter((r) => r.skipped).length;
  if (mutation) {
    const owner = MUTATION_OWNER[mutation];
    const hit = rows.filter((r) => r.bad.some(owner)).length;
    console.log(`flip cell ${engineName} mutation ${mutation}: ${hit > 0 ? 'caught' : 'NOT caught'} (${hit} of ${rows.length} readings fail on its reading; ${failed} fail in all)`);
    return expectFail ? hit > 0 : true;
  }
  console.log(`flip cell ${engineName} ${fw}: ${failed === 0 ? 'pass' : 'fail'} (${rows.length} readings, ${failed} failed, ${skipped} skipped, ${faults.length} faults)${reportOnly ? ' reported only, exit 0' : ''}`);
  return reportOnly || cellsPass(outcomes);
}
