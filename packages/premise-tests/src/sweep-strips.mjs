#!/usr/bin/env node
// Sweep strips for the user's look review of platform.sweep:layer-sweep (task layer-sweep-review). For each width, the four title
// words of the platform rows (Document, Earn, Secure, Organized, each in its title as index.tsx writes it) are painted as the
// faithful rewrite paints them (background-clip:text, background-position animated) and as the flag paints them (a gradient layer
// under a static mask-clip:text mask, moved by transform), from the declarations of
// apps/site/src/parts/platform/sweep.module.css and the site's word size, weight and font. The 4 s loop is paused at each moment
// by a negative animation delay (nothing is seeked), each word is cropped, and one PNG per moment stacks, word by word, the
// original, the flag and a heat map of their per-pixel difference, each zoomed 4x. Review material only: it decides nothing. The
// page restates the site's declarations; it is not the built site (the Flag / Faithful / Compare preview buttons open that).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium, webkit } from 'playwright-core';
import { combine, decodePng, encodePng, strip } from './png.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

/** The loop moments (word of the file name, microseconds into the 4 s loop). Lean: Fw.Console.ReviewStrips.SweepAt. */
export const MOMENTS = [
  { word: 'p0', us: 0 },
  { word: 'f1', us: 16667 },
  { word: 'f2', us: 33333 },
  { word: 't500', us: 500000 },
  { word: 't2000', us: 2000000 },
];
export const WIDTHS = [390, 1440];
export const WORDS = ['Document', 'Earn', 'Secure', 'Organized'];
export const ZOOM = 4;
export const MARGIN = 4;
const FONT = 'google-sans-latin-normal.BbZhqv4U.woff2';
/** The word size of the platform rows at a viewport width (platform.module.css: 28px up to 1000 px, 40px above). */
export const wordPx = (width) => (width <= 1000 ? 28 : 40);

/** The engine word of the file names and the artifact (Lean: playwright-webkit for the webkit rows). */
export const engineWord = (engine) => (engine === 'webkit' || engine === 'playwright-webkit' ? 'playwright-webkit' : engine);
/** The file of a strip inside the artifact. */
export const stripPath = (engine, width, moment) => `strips/${engineWord(engine)}-${width}-sweep-${moment}.png`;

/** The CSS of the sweep part, as the site ships it (the module's own text; class names stay as written). */
export function sweepCss() {
  return readFileSync(resolve(here, '../../../apps/site/src/parts/platform/sweep.module.css'), 'utf8');
}

/** The title of a word as the platform rows write it (index.tsx). */
function titleHtml(word, cls, bg) {
  const w = (extra = '') => `<span class="${cls}${extra}" data-word>${word}${bg}</span>`;
  if (word === 'Document') return `<h3 class="rowTitle">${w()} <span class="rest">your portfolio and reviews</span></h3>`;
  if (word === 'Earn') return `<h3 class="rowTitle"><span class="rest restBlock">Get discovered.</span> ${w()} <span class="rest">more</span></h3>`;
  if (word === 'Secure') return `<h3 class="rowTitle">${w()} <span class="rest">payment worldwide</span></h3>`;
  return `<h3 class="rowTitle"><span class="rest restBlock">Keep every order</span> ${w(' wordFree')}</h3>`;
}

/** The page of one arm (`faithful` or `layer`) at one width: the four titles one under the other. */
export function pageHtml(arm, width, fontUrl, css = sweepCss()) {
  const px = wordPx(width);
  const cls = arm === 'layer' ? 'word sweep layer' : 'word sweep';
  const bg = arm === 'layer' ? '<i class="layerBg" aria-hidden="true"></i>' : '';
  return `<!doctype html><meta charset="utf-8"><style>
@layer base, parts;
@font-face { font-family: 'Site Sans'; src: url(${fontUrl}); font-weight: 100 900; }
@layer base {
  html, body { margin: 0; background: #131922; font-family: 'Site Sans', sans-serif; text-rendering: geometricPrecision; }
  .rowCopy { padding: ${width <= 1000 ? 24 : 48}px; }
  .rowTitle { color: #fff; letter-spacing: 0; text-wrap: pretty; margin: 0; font-size: ${px}px; font-weight: 400; line-height: 1.15; }
  .word { vertical-align: top; white-space: ${width <= 1000 ? 'normal' : 'nowrap'}; color: #fff; height: auto; font-size: ${px}px; font-weight: 700; line-height: 1.15; display: inline; }
  .word.wordFree { vertical-align: baseline; white-space: normal; }
  .rest { color: #fffc; opacity: 1; font-size: ${px}px; font-weight: 400; }
  ${width >= 861 ? '.restBlock { display: block; }' : ''}
}
${css}
/* the loop is held at the moment --at (negative delay, paused) */
.sweep.sweep, .layerBg { animation-play-state: paused; animation-delay: var(--at, 0s); }
</style>
${WORDS.map((w) => `<div class="rowCopy">${titleHtml(w, cls, bg)}</div>`).join('\n')}
<script>
  // the part's watchLayerWidth (apps/site/src/parts/platform.sweep/layer.ts): device-pixel word width, layer = 6 of it, once per resize
  const dpr = devicePixelRatio || 1;
  const set = (el, n) => el.style.setProperty('--sw6', (6 * n / dpr) + 'px');
  const ro = new ResizeObserver((es) => es.forEach((e) => {
    const d = e.devicePixelContentBoxSize && e.devicePixelContentBoxSize[0];
    if (d) return set(e.target, d.inlineSize);
    const r = e.target.getBoundingClientRect();
    set(e.target, Math.floor((r.left + r.width) * dpr + 0.5) - Math.floor(r.left * dpr + 0.5));
  }));
  document.querySelectorAll('.layer').forEach((el) => { try { ro.observe(el, { box: 'device-pixel-content-box' }); } catch (_) { ro.observe(el); } });
</script>`;
}

async function launch(name) {
  if (name === 'playwright-webkit' || name === 'webkit') return webkit.launch();
  return chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}), ...(process.env.PREMISE_CHANNEL ? { channel: process.env.PREMISE_CHANNEL } : {}) });
}

const raf2 = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

/** The crop box of a word rect: whole pixels with MARGIN around, inside a viewport of `width` x `height`. */
export function cropOf(rect, width, height) {
  const x = Math.max(0, Math.floor(rect.left) - MARGIN); const y = Math.max(0, Math.floor(rect.top) - MARGIN);
  const x1 = Math.min(width, Math.ceil(rect.right) + MARGIN); const y1 = Math.min(height, Math.ceil(rect.bottom) + MARGIN);
  return { x, y, width: x1 - x, height: y1 - y };
}

/** All shots of one arm at one width: per word its rect and crop box, and per moment one PNG buffer per word. */
async function shots(browser, arm, width, out, fontUrl, crops) {
  const file = join(out, `page-${arm}-${width}.html`);
  writeFileSync(file, pageHtml(arm, width, fontUrl));
  const height = 1000;
  const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
  try {
    const page = await ctx.newPage();
    await page.goto(pathToFileURL(file).href, { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    const rects = await page.evaluate(() => [...document.querySelectorAll('[data-word]')].map((el) => { const r = el.getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right, bottom: r.bottom }; }));
    const boxes = crops ?? rects.map((r) => cropOf(r, width, height));
    const pngs = {};
    for (const m of MOMENTS) {
      await page.evaluate((us) => document.documentElement.style.setProperty('--at', `${-us / 1e6}s`), m.us);
      await page.evaluate(raf2);
      pngs[m.word] = [];
      for (const box of boxes) pngs[m.word].push(await page.screenshot({ clip: { x: box.x, y: box.y, width: box.width, height: box.height } }));
    }
    return { rects, boxes, pngs };
  } finally { await ctx.close(); }
}

async function main() {
  const engine = engineWord(opt('engine', 'chromium'));
  const out = resolve(opt('out', 'out-sweep'));
  const widths = opt('widths', WIDTHS.join(',')).split(',').map(Number);
  const fontUrl = pathToFileURL(resolve(here, '../../../snapshot/site/_app/immutable/assets', FONT)).href;
  mkdirSync(join(out, 'strips'), { recursive: true });
  const browser = await launch(engine);
  const index = { schema: 1, engine, browser: browser.version(), dpr: 1, zoom: ZOOM, font: FONT, words: WORDS,
    rows: 'per word, top to bottom: original, flag, difference (heat: 0 black, 1-2 blue, 3-8 green, 9-32 yellow, over 32 red)', strips: [] };
  try {
    for (const width of widths) {
      const faithful = await shots(browser, 'faithful', width, out, fontUrl);
      const layer = await shots(browser, 'layer', width, out, fontUrl, faithful.boxes);
      for (const m of MOMENTS) {
        const words = WORDS.map((word, k) => {
          const { diff, image } = strip(decodePng(faithful.pngs[m.word][k]), decodePng(layer.pngs[m.word][k]), ZOOM);
          return { word, diff, image, crop: faithful.boxes[k], wordFaithful: faithful.rects[k], wordLayer: layer.rects[k] };
        });
        const path = stripPath(engine, width, m.word);
        writeFileSync(join(out, path), encodePng(combine(words.map((w) => w.image))));
        index.strips.push({ file: path, width, moment: m.word, us: m.us,
          max: Math.max(...words.map((w) => w.diff.max)), differing: words.reduce((n, w) => n + w.diff.count, 0), over2: words.reduce((n, w) => n + w.diff.over2, 0),
          words: words.map((w) => ({ word: w.word, crop: w.crop, wordFaithful: w.wordFaithful, wordLayer: w.wordLayer, max: w.diff.max, differing: w.diff.count, over2: w.diff.over2, at: w.diff.at, columns: w.diff.columns })) });
      }
    }
  } finally { await browser.close(); }
  writeFileSync(join(out, 'strips', 'index.json'), `${JSON.stringify(index, null, 1)}\n`);
  console.log(`sweep-strips ${engine} ${index.browser}: ${index.strips.length} strips in ${out}`);
  for (const s of index.strips) console.log(`  ${s.file}: max ${s.max}, differing ${s.differing}, over2 ${s.over2}; per word ${s.words.map((w) => `${w.word} ${w.max}`).join(', ')}`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) await main();
