#!/usr/bin/env node
// Frame capture of the nav "Join waitlist" button on one engine (task nav-cta-webkit-match). The page is the real
// apps/site/src/parts/nav/nav.module.css (module syntax reduced to plain classes) around the nav markup, with the font
// the site ships. A hero-pill flip is the only input: the class is toggled, every animation is paused and seeked to t
// (transitions, the unmask and the sheen alike), and the band is screenshotted. Compare the two engines' directories with
// earn-frames-compare.mjs.
//
//   node src/earn-frames.mjs --engine chromium|playwright-webkit --out DIR [--widths 1280,390] [--arms faithful,logical]
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium, webkit } from 'playwright-core';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] ? args[i + 1] : d; };
export const TS = [0, 60, 120, 200, 300, 400, 520, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1500, 1800];
export const BAND = 100;
const FONT = 'google-sans-latin-normal.BbZhqv4U.woff2';

export function pageHtml(arm, fontUrl) {
  const css = readFileSync(resolve(here, '../../../apps/site/src/parts/nav/nav.module.css'), 'utf8').replace(/:global\(([^)]*)\)/g, '$1');
  return `<!doctype html><meta charset="utf-8"><style>
@font-face { font-family: 'Site Sans'; src: url(${fontUrl}); font-weight: 100 900; }
html, body { margin: 0; background: #fff; font-family: 'Site Sans', sans-serif; overflow: hidden; text-rendering: geometricPrecision; }
${css}
.label { display: inline-block; width: 5.7em; overflow: hidden; }
.lang { background: #fff; color: #1f2937; border: 1px solid #e5e5e5; }
</style>
<header class="nav is-hero-pill is-hero-chrome-ready${arm === 'logical' ? ' is-earn-logical' : ''}">
  <div class="bar"><span class="logo"></span>
    <div class="actions"><button class="btn lang" type="button">EN</button><button class="btn earn" type="button"><span class="label">Join waitlist</span></button></div>
  </div>
</header>`;
}

async function launch(name) {
  if (name === 'playwright-webkit' || name === 'webkit') return webkit.launch();
  return chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}), ...(process.env.PREMISE_CHANNEL ? { channel: process.env.PREMISE_CHANNEL } : {}) });
}

async function frame(page, scenario, t) {
  await page.evaluate(async ({ scenario }) => {
    const nav = document.querySelector('.nav');
    document.getAnimations().forEach((a) => a.finish());
    if (scenario === 'exit') { nav.getBoundingClientRect(); nav.classList.remove('is-hero-pill'); }
    else { nav.classList.remove('is-hero-pill'); await new Promise((r) => setTimeout(r, 2600)); document.getAnimations().forEach((a) => a.finish()); nav.getBoundingClientRect(); nav.classList.add('is-hero-pill'); }
    document.getAnimations();
    for (let i = 0; i < 3; i++) await new Promise((r) => requestAnimationFrame(r));
  }, { scenario });
  const rows = await page.evaluate((t) => {
    const as = document.getAnimations();
    as.forEach((a) => { a.pause(); a.currentTime = t; });
    const rect = (el) => { const r = el.getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map((v) => Math.round(v * 100) / 100); };
    const earn = document.querySelector('.earn');
    const cs = getComputedStyle(earn);
    const range = document.createRange();
    range.selectNodeContents(earn);
    const r = range.getBoundingClientRect();
    return { label: [r.left, r.top, r.width, r.height].map((v) => Math.round(v * 100) / 100), anims: as.map((a) => a.transitionProperty ?? a.animationName).sort().join(','), earn: rect(earn), lang: rect(document.querySelector('.lang')),
      padL: cs.paddingLeft, padR: cs.paddingRight, opacity: cs.opacity, maxWidth: cs.maxWidth };
  }, t);
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  return rows;
}

async function main() {
  const engine = opt('engine', 'chromium');
  const out = resolve(opt('out', 'out-earn'));
  const widths = opt('widths', '1280,390').split(',').map(Number);
  const arms = opt('arms', 'faithful,logical').split(',');
  const fontUrl = pathToFileURL(resolve(here, '../../../snapshot/site/_app/immutable/assets', FONT)).href;
  mkdirSync(out, { recursive: true });
  const browser = await launch(engine);
  const index = { schema: 1, engine, browser: browser.version(), band: BAND, font: FONT, frames: [] };
  try {
    for (const width of widths) for (const arm of arms) for (const scenario of ['exit', 'entry']) {
      const file = join(out, `page-${arm}.html`);
      writeFileSync(file, pageHtml(arm, fontUrl));
      const ctx = await browser.newContext({ viewport: { width, height: 400 }, deviceScaleFactor: 1 });
      const page = await ctx.newPage();
      for (const t of TS) {
        await page.goto(pathToFileURL(file).href, { waitUntil: 'load' });
        await page.evaluate(() => document.fonts.ready);
        await page.waitForTimeout(300);
        const meta = await frame(page, scenario, t);
        const name = `${width}-${scenario}-${arm}-${String(t).padStart(4, '0')}.png`;
        const clip = { x: 0, y: 0, width, height: BAND };
        writeFileSync(join(out, name), await page.screenshot({ clip }));
        await page.addStyleTag({ content: '.earn { color: transparent !important; }' });
        await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
        writeFileSync(join(out, name.replace('.png', '-nt.png')), await page.screenshot({ clip }));
        index.frames.push({ width, scenario, arm, t, file: name, fileNoText: name.replace('.png', '-nt.png'), ...meta });
      }
      await ctx.close();
    }
  } finally {
    await browser.close();
  }
  writeFileSync(join(out, `frames-${engine === 'webkit' ? 'playwright-webkit' : engine}.json`), `${JSON.stringify(index, null, 1)}\n`);
  console.log(`earn-frames ${engine} ${index.browser}: ${index.frames.length} frames in ${out}`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) await main();
