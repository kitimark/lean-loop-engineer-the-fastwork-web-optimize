// The flip-state cell (task geom-flip-fix): with a morph.geom flag, the columns lie side by side and the bar, the earn button
// and the actions box sit where the base page puts them, at m in {0, 0.5, 1}, at the breakpoint widths, on both engines.
// The bound, the ms, the elements and the per-width column count come from the Lean golden (morph-geom.jsonl, lines `flipCell`
// and `flipBand`; Lean Fw.Parts.MorphGeom flip_column_left, earn_flip_fixed, actions_fix_eq). This file holds no list of its own.
//   node src/cli.mjs flip --engine chromium|playwright-webkit|both --fw morph.geom:on --out out/flip [--bands 390x844,...]
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PKG, siteDist, startServer } from './serve.mjs';
import { PIN_SRC } from './page.mjs';

export const GOLDEN = resolve(PKG, '../contracts/golden/morph-geom.jsonl');

/** The cell definition and the bands of the golden. */
export function loadFlipCell(path = GOLDEN) {
  const lines = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const cell = lines.find((l) => l.fn === 'flipCell')?.out;
  const bands = lines.filter((l) => l.fn === 'flipBand').map((l) => ({ w: l.in.w, h: l.in.h, ...l.out }));
  if (!cell || bands.length === 0) throw new Error(`no flipCell or flipBand line in ${path}`);
  return { ...cell, bands };
}

const edges = (r) => [r.x, r.y, r.x + r.width, r.y + r.height];

/** Rects of the cell's elements, in page px. Runs in the page. `pill` is the nav box on the base page and the intersection of the
 * four rounded clippers on a flip page (the nav box itself is laid out at the final size there); `images` are the images of the
 * visible columns (compared by their x edges: the flip scales an image in both axes where the base keeps its height and crops,
 * a finding of this task); `lang` and `earn` are compared by their y edges, `lang` by its x edges only where the time tracks are
 * settled (m = 0 and 1), `actions` by its right edge (its box is stretched to the bar in the flip, its buttons are not). */
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

/** Judge one reading: the flag arm's rects against the base arm's, each compared edge within tolPx. Pure. Returns the failed readings. */
export function judgeRects(base, flag, band, tolPx, settled = true) {
  const bad = [];
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

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function runFlipCell({ engineName, fw, outDir, bandFilter = null }) {
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
      const open = async (path) => {
        const s = await engine.open(env, { origin: server.origin, path, init: PIN_SRC });
        await s.page.evaluate(async () => {
          for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await new Promise((r) => setTimeout(r, 50));
        });
        await s.page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
        await sleep(1800);
        return s;
      };
      const A = await open('/');
      const B = await open(flag.path + flag.search);
      try {
        for (const m of cell.ms) {
          await A.page.evaluate(pin, m);
          await B.page.evaluate(pin, m);
          await sleep(1200);
          const base = await A.page.evaluate(readRects);
          const got = await B.page.evaluate(readRects);
          const bad = judgeRects(base, got, band, cell.tolPx, m === 0 || m === 1);
          rows.push({ band: `${band.w}x${band.h}`, m, flipClass: got.flip, ok: bad.length === 0, bad, ...(bad.length ? { base, flag: got } : {}) });
          process.stderr.write(`${band.w}x${band.h} m=${m} flip=${got.flip} variant=${got.variant} ${got.flip ? '' : got.navClass} ${bad.length === 0 ? 'ok' : bad.join('; ')}\n`);
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
  writeFileSync(join(outDir, `flip-${engineName}.json`), `${JSON.stringify({ fw, engine: engineName, tolPx: cell.tolPx, ms: cell.ms, rows }, null, 1)}\n`);
  const failed = rows.filter((r) => !r.ok).length;
  console.log(`flip cell ${engineName} ${fw}: ${failed === 0 ? 'pass' : 'fail'} (${rows.length} readings, ${failed} failed)`);
  return failed === 0;
}
