#!/usr/bin/env node
// Diagnostic for task geom-page-diff (investigation only; not a gate, not a harness change).
// Replays the look report's capture (packages/premise-tests/src/look.mjs) at m=0 and m=1 for a few bands and adds a third
// arm "base+fade": the base page pinned the same way, plus the one write the tween driver does and look.mjs does not
// (--morph-fade on the platform section, apps/site/src/parts/morph.tween/driver.ts:120).
// Output: per-band JSON (strips, platform probes) and diff PNGs (red = channel difference > 12, grey = equal).
//   FW_SITE_DIST=<aot dir> node results/geom-page-diff/probe.mjs --engine chromium|playwright-webkit --out <dir> [--bands 390x844,...]
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PIN_SRC } from '../../packages/gate-breakpoints/src/page.mjs';
import { siteDist, startServer } from '../../packages/gate-breakpoints/src/serve.mjs';
import { LAUNCHERS } from '../../packages/visual-diff/src/engines.mjs';
import { decode, encodePng } from '../../packages/visual-diff/src/diff.mjs';
import { rewritePathFor } from '../../packages/visual-diff/src/run.mjs';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const BANDS = opt('bands', '390x844,1280x800,1920x1080').split(',').map((s) => s.split('x').map(Number));
const engineName = opt('engine', 'chromium');
const out = resolve(opt('out', 'out'));
const OVER = 12;
const STRIPS = 8;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pin(m) {
  const nav = document.querySelector('[data-fw="nav"]');
  nav.classList.toggle('is-on-dark', m > 0.2 || !!nav.dataset.fwKeepDark);
  nav.style.setProperty('--morph', String(m));
  nav.dataset.fwMorph = String(m);
  return nav.getBoundingClientRect().toJSON();
}
const probe = () => {
  const p = document.querySelector('[data-fw="platform"]');
  const cs = p && getComputedStyle(p);
  const r = p && p.getBoundingClientRect().toJSON();
  return {
    scrollY: window.scrollY, scrollHeight: document.documentElement.scrollHeight, innerHeight: window.innerHeight,
    platform: p ? { opacity: cs.opacity, filter: cs.filter, morphFade: p.style.getPropertyValue('--morph-fade') || null, top: r.top, bottom: r.bottom, left: r.left, right: r.right } : null,
  };
};
const fadeWrite = (m) => {
  const p = document.querySelector('[data-fw="platform"]');
  if (p) p.style.setProperty('--morph-fade', String(1 - Math.min(1, m / 0.55)));
};

function over(a, b, i) {
  const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
  return d > OVER;
}
// Share of pixels differing in a region; `skip` (optional rect) is left out of it.
function share(a, b, rect, skip) {
  let n = 0, c = 0;
  const x0 = Math.max(0, Math.floor(rect.x)), y0 = Math.max(0, Math.floor(rect.y));
  const x1 = Math.min(a.width, Math.ceil(rect.x + rect.width)), y1 = Math.min(a.height, Math.ceil(rect.y + rect.height));
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    if (skip && x >= skip.x && x < skip.x + skip.width && y >= skip.y && y < skip.y + skip.height) continue;
    n++;
    if (over(a, b, 4 * (y * a.width + x))) c++;
  }
  return { share: n ? c / n : 0, px: n };
}
function diffImage(a, b, nav) {
  const data = new Uint8Array(a.data.length);
  for (let y = 0; y < a.height; y++) for (let x = 0; x < a.width; x++) {
    const i = 4 * (y * a.width + x);
    const inNav = x >= nav.x && x < nav.x + nav.width && y >= nav.y && y < nav.y + nav.height;
    const o = over(a, b, i);
    const [r, g, bl] = o ? [220, 40, 40] : inNav ? [200, 215, 235] : [235, 235, 235];
    data[i] = r; data[i + 1] = g; data[i + 2] = bl; data[i + 3] = 255;
  }
  return { width: a.width, height: a.height, data };
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
    const arms = { base: await open('/'), flip: await open(flag.path + flag.search), basefade: await open('/') };
    try {
      for (const m of [0, 1]) {
        const shots = {}, probes = {}, navBox = {};
        for (const [name, s] of Object.entries(arms)) {
          navBox[name] = await s.page.evaluate(pin, m);
          if (name === 'basefade') await s.page.evaluate(fadeWrite, m);
        }
        await sleep(900);
        if (m > 0) await arms.flip.page.evaluate((m) => { document.querySelector('[data-fw="nav"]').dataset.fwMorph = String(m); }, m);
        await sleep(300);
        for (const name of Object.keys(arms)) {
          navBox[name] = await arms[name].page.evaluate(pin, m);
          if (name === 'basefade') await arms[name].page.evaluate(fadeWrite, m);
        }
        const freeze = () => { for (const a of document.getAnimations()) if (a instanceof CSSAnimation) { a.pause(); a.currentTime = 4000; } };
        for (const s of Object.values(arms)) await s.page.evaluate(freeze);
        await sleep(200);
        for (const [name, s] of Object.entries(arms)) {
          probes[name] = await s.page.evaluate(probe);
          shots[name] = decode(await s.page.screenshot({ animations: 'allow', caret: 'hide' }));
        }
        const k = shots.base.width / w;
        const nb = (r) => ({ x: r.x * k, y: r.y * k, width: r.width * k, height: r.height * k });
        const nav = nb({ x: Math.min(navBox.base.x, navBox.flip.x), y: Math.min(navBox.base.y, navBox.flip.y), width: Math.max(navBox.base.width, navBox.flip.width), height: Math.max(navBox.base.height, navBox.flip.height) });
        const whole = { x: 0, y: 0, width: shots.base.width, height: shots.base.height };
        const pair = (a, b) => {
          const strips = [];
          const sh = Math.ceil(whole.height / STRIPS);
          for (let s = 0; s < STRIPS; s++) strips.push(+share(shots[a], shots[b], { x: 0, y: s * sh, width: whole.width, height: sh }).share.toFixed(3));
          return { page: share(shots[a], shots[b], whole).share, nav: share(shots[a], shots[b], nav).share, outsideNav: share(shots[a], shots[b], whole, nav).share, strips };
        };
        const row = { band: `${w}x${h}`, m, k, navBox: nav, pageShare: whole.width * whole.height, baseVsFlip: pair('base', 'flip'), basefadeVsFlip: pair('basefade', 'flip'), baseVsBasefade: pair('base', 'basefade'), probes };
        rows.push(row);
        if (m === 1) {
          const tag = `${w}x${h}-m1`;
          writeFileSync(join(out, 'img', `${tag}-diff-base-vs-flip.png`), encodePng(diffImage(shots.base, shots.flip, nav)));
          writeFileSync(join(out, 'img', `${tag}-diff-basefade-vs-flip.png`), encodePng(diffImage(shots.basefade, shots.flip, nav)));
          if (w === 1280) for (const n of ['base', 'flip', 'basefade']) writeFileSync(join(out, 'img', `${tag}-${n}.png`), encodePng(shots[n]));
        }
        process.stderr.write(`${row.band} m=${m} base-vs-flip page ${row.baseVsFlip.page.toFixed(3)} outside ${row.baseVsFlip.outsideNav.toFixed(3)} | basefade-vs-flip page ${row.basefadeVsFlip.page.toFixed(3)} outside ${row.basefadeVsFlip.outsideNav.toFixed(3)} | platform opacity base/flip ${probes.base.platform?.opacity}/${probes.flip.platform?.opacity}\n`);
      }
    } finally { for (const s of Object.values(arms)) await s.close().catch(() => {}); }
  }
} finally { await engine.close?.(); server.close?.(); }
writeFileSync(join(out, `probe-${engineName}.json`), JSON.stringify({ over: OVER, engine: engineName, rows }, null, 1) + '\n');
process.exit(0);
