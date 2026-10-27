#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PIN_SRC } from '../../gate-breakpoints/src/page.mjs';
import { siteDist, startServer } from '../../gate-breakpoints/src/serve.mjs';
import { LAUNCHERS } from '../../visual-diff/src/engines.mjs';
import { decode, encodePng } from '../../visual-diff/src/diff.mjs';
import { rewritePathFor } from '../../visual-diff/src/run.mjs';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const BANDS = (opt('bands', '320x568,360x640,390x844,430x932,640x360,640x1000,641x700,768x1024,1024x768,1280x800,1440x900,1920x1080')).split(',').map((s) => s.split('x').map(Number));
const MS = opt('ms', '0,.01,.05,.08,.15,.2,.32,.5,.55,.8,1').split(',').map(Number);
const engineName = opt('engine', 'chromium');
const out = resolve(opt('out', 'out'));
const OVER = 12;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pin(m) {
  const nav = document.querySelector('[data-fw="nav"]');
  nav.classList.toggle('is-on-dark', m > 0.2 || !!nav.dataset.fwKeepDark);
  nav.style.setProperty('--morph', String(m));
  nav.dataset.fwMorph = String(m);
  return nav.getBoundingClientRect().toJSON();
}

function regionStats(a, b, rect) {
  const x0 = Math.max(0, Math.floor(rect.x)), y0 = Math.max(0, Math.floor(rect.y));
  const x1 = Math.min(a.width, Math.ceil(rect.x + rect.width)), y1 = Math.min(a.height, Math.ceil(rect.y + rect.height));
  let max = 0, over = 0, n = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const i = 4 * (y * a.width + x);
    const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
    if (d > max) max = d;
    if (d > OVER) over++;
    n++;
  }
  return { max, share: n ? over / n : 0, px: n };
}

const dist = siteDist();
const flag = rewritePathFor(dist, 'morph.geom:on');
const server = await startServer(dist);
const engine = await LAUNCHERS[engineName]();
const rows = [];
mkdirSync(join(out, 'img'), { recursive: true });
try {
  for (const [w, h] of BANDS) {
    const env = { width: w, height: h, deviceWidth: w, deviceHeight: h, dpr: w <= 640 ? 3 : 1, hover: w <= 1024 ? 'none' : 'hover', pointer: w <= 1024 ? 'coarse' : 'fine', colorScheme: 'light', reducedMotion: 'no-preference' };
    const open = async (path) => {
      const s = await engine.open(env, { origin: server.origin, path, init: PIN_SRC });
      await s.page.evaluate(async () => { for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await new Promise((r) => setTimeout(r, 50)); });
      await s.page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      await sleep(1800);
      return s;
    };
    const A = await open('/');
    const B = await open(flag.path);
    try {
      for (const m of MS) {
        const ra = await A.page.evaluate(pin, m);
        await B.page.evaluate(pin, m);
        await sleep(900);
        if (m > 0) await B.page.evaluate((m) => { const n = document.querySelector('[data-fw="nav"]'); n.dataset.fwMorph = String(m); }, m);
        await sleep(300);
        const sa = decode(await A.page.screenshot({ animations: 'allow', caret: 'hide' }));
        const sb = decode(await B.page.screenshot({ animations: 'allow', caret: 'hide' }));
        const rb = await B.page.evaluate(() => document.querySelector('[data-fw="nav"]').getBoundingClientRect().toJSON());
        const k = sa.width / w;
        const px = (r) => ({ x: r.x * k, y: r.y * k, width: r.width * k, height: r.height * k });
        const nav = { x: Math.min(ra.x, rb.x) * k, y: Math.min(ra.y, rb.y) * k, width: Math.max(ra.width, rb.width) * k, height: Math.max(ra.height, rb.height) * k };
        const whole = { x: 0, y: 0, width: sa.width, height: sa.height };
        const row = { band: `${w}x${h}`, m, nav: regionStats(sa, sb, nav), page: regionStats(sa, sb, whole), flagBox: px(rb) };
        rows.push(row);
        if (m === 0 || m === 1) { writeFileSync(join(out, 'img', `${w}x${h}-m${m}-faithful.png`), encodePng(sa)); writeFileSync(join(out, 'img', `${w}x${h}-m${m}-flag.png`), encodePng(sb)); }
        process.stderr.write(`${row.band} m=${m} nav max ${row.nav.max} share ${row.nav.share.toFixed(4)} page max ${row.page.max} share ${row.page.share.toFixed(4)}\n`);
      }
    } finally { await A.close().catch(() => {}); await B.close().catch(() => {}); }
  }
} finally { await engine.close?.(); server.close?.(); }
writeFileSync(join(out, `look-${engineName}.json`), JSON.stringify({ over: OVER, engine: engineName, ms: MS, rows }, null, 1) + '\n');
process.exit(0);
