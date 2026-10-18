// Measures the outer border-box height of the original's homepage sections in the read-only snapshot, at a grid of
// viewports, and writes the raw samples. Used twice:
//   node scripts/shell-measure.mjs samples [--out file]   the fit input (src/shells/samples.json), original only
//   node scripts/shell-measure.mjs check [--arm original|rewrite|both] [--tol 0.5]
//        every probe of the Lean breakpoint matrix (src/breakpoints.gen.json): the rewrite's section boxes against the
//        original's, in the same browser (needs `pnpm build` for dist/aot). Exit 1 if any box differs by more than --tol.
// Nothing of the snapshot is copied: only numbers (heights in CSS px) are written.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SITE = resolve(HERE, '..');
const require = createRequire(join(SITE, 'package.json'));
const puppeteer = require('puppeteer-core');
const { startServer, snapshotRoot, siteDist } = await import('../../../packages/gate-breakpoints/src/serve.mjs');

export const SECTIONS = ['people', 'pain', 'commission', 'platform'];
const ORIGINAL_SELECTOR = {
  hero: 'section.hero-track',
  people: 'section#people',
  pain: 'section.pain',
  commission: 'section.commission',
  platform: 'section#platform',
};
const CHROME = process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

/** Runs in the page. `sel` maps section id -> selector. Reports heights only. */
function collect(sel) {
  const out = { docH: document.documentElement.scrollHeight };
  for (const [id, s] of Object.entries(sel)) {
    if (id === 'hero') continue;
    const e = document.querySelector(s);
    out[id] = e ? e.getBoundingClientRect().height : null;
  }
  // where the hero track starts: 0 in the original; in the rewrite the pilots' placeholder nav and countdown sit above it
  const hero = document.querySelector(sel.hero);
  out.heroTop = hero ? hero.getBoundingClientRect().top + scrollY : null;
  return out;
}

async function measureAt(browser, origin, sel, w, h, ready) {
  const page = await browser.newPage();
  try {
    await page.setViewport({ width: Math.ceil(w), height: h });
    await page.goto(origin + '/', { waitUntil: 'networkidle0' });
    await page.evaluate(ready);
    // text can still reflow for a moment after load: take the value once two reads 300 ms apart agree
    let prev = null;
    for (let i = 0; i < 20; i++) {
      await new Promise((r) => setTimeout(r, 300));
      const cur = await page.evaluate(collect, sel);
      if (prev && JSON.stringify(prev) === JSON.stringify(cur)) return cur;
      prev = cur;
    }
    throw new Error(`box heights do not settle at ${w}x${h}`);
  } finally {
    await page.close();
  }
}

const readyOriginal = () => document.fonts.ready.then(() => undefined);
const readyRewrite = () =>
  new Promise((res) => {
    const t0 = performance.now();
    const tick = () => (window.__fw && window.__fw.hydrated) || performance.now() - t0 > 8000 ? res(undefined) : setTimeout(tick, 50);
    tick();
  });

function args() {
  const a = process.argv.slice(2);
  const get = (k, d) => (a.includes(k) ? a[a.indexOf(k) + 1] : d);
  return { cmd: a[0], out: get('--out', join(SITE, 'src/shells/samples.json')), arm: get('--arm', 'both'), tol: Number(get('--tol', '0.5')) };
}

async function samples(browser, out) {
  const gen = JSON.parse(readFileSync(join(SITE, 'src/breakpoints.gen.json'), 'utf8'));
  const edge = new Set(gen.edgePairs.width.flat());
  const widths = new Set([...edge, 1440, 1600]);
  for (const p of gen.matrix.probes) widths.add(Math.max(320, Math.ceil(p.width))); // the gate hosts a fractional width at the next whole px
  for (let w = 320; w <= 1600; w += 10) widths.add(w);
  const srv = await startServer(snapshotRoot());
  const rows = [];
  for (const w of [...widths].sort((x, y) => x - y)) {
    for (const h of [600, 900]) {
      rows.push({ w, h, ...(await measureAt(browser, srv.origin, ORIGINAL_SELECTOR, w, h, readyOriginal)) });
    }
  }
  await srv.close();
  writeFileSync(
    out,
    JSON.stringify({ schema: 'fw.shells.samples/1', about: 'Outer border-box heights (CSS px) of the original homepage sections, desktop Chromium, viewport w x h. Raw measurement; src/shells/fit.mjs turns it into CSS.', rows }, null, 1) + '\n',
  );
  console.log(`wrote ${rows.length} rows to ${out}`);
}

async function check(browser, arm, tol) {
  const gen = JSON.parse(readFileSync(join(SITE, 'src/breakpoints.gen.json'), 'utf8'));
  const probes = [...new Map(gen.matrix.probes.map((p) => [`${p.width}x${p.height}`, p])).values()];
  const rew = arm !== 'original' ? await startServer(siteDist()) : null;
  const orig = await startServer(snapshotRoot());
  const sel = { hero: '[data-fw="hero-exit"]', ...Object.fromEntries(SECTIONS.map((s) => [s, `[data-fw="${s}"]`])) };
  let bad = 0;
  let worst = 0;
  for (const p of probes) {
    const o = await measureAt(browser, orig.origin, ORIGINAL_SELECTOR, p.width, p.height, readyOriginal);
    const r = await measureAt(browser, rew.origin, sel, p.width, p.height, readyRewrite);
    const diffs = SECTIONS.map((s) => [s, r[s] === null ? Infinity : r[s] - o[s]]);
    const d = Math.max(...diffs.map(([, v]) => Math.abs(v)));
    worst = Math.max(worst, d);
    const pageDiff = r.docH - r.heroTop - o.docH; // page tolerance max(tol, 1), even when tol is 0 (scrollHeight is a whole number: 1 px slack)
    const flag = d > tol || Math.abs(pageDiff) > Math.max(tol, 1) ? 'FAIL' : 'ok';
    if (flag === 'FAIL') bad++;
    console.log(`${flag} ${p.width}x${p.height} sections ${diffs.map(([s, v]) => `${s}${v >= 0 ? '+' : ''}${Number.isFinite(v) ? v.toFixed(2) : 'missing'}`).join(' ')} docH ${r.docH} - scaffold ${r.heroTop} vs ${o.docH} (${pageDiff >= 0 ? '+' : ''}${pageDiff.toFixed(2)})`);
  }
  await orig.close();
  await rew?.close();
  console.log(`${probes.length} probes, ${bad} outside ${tol} px (worst section diff ${worst.toFixed(2)})`);
  return bad === 0;
}

const { cmd, out, arm, tol } = args();
const browser = await puppeteer.launch({ executablePath: CHROME, headless: true });
let ok = true;
try {
  if (cmd === 'samples') await samples(browser, out);
  else if (cmd === 'check') ok = await check(browser, arm, tol);
  else throw new Error('usage: shell-measure.mjs samples|check');
} finally {
  await browser.close();
}
process.exit(ok ? 0 : 1);
