// Reads the original's inline SVG artwork from the unmodified snapshot into the gitignored src/svg.gen.json.
// Path data is Fastwork material: it is never committed (svg-extract.test.ts fails if a tracked file holds any of it).
// Run by `node scripts/svg-extract.mjs`, by build.mjs itself, and by the test and typecheck scripts.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const pageFile = fileURLToPath(new URL('../../../snapshot/site/index.html', import.meta.url));
const nodesDir = fileURLToPath(new URL('../../../snapshot/site/_app/immutable/nodes/', import.meta.url));
export const OUT = fileURLToPath(new URL('../src/svg.gen.json', import.meta.url));

function balanced(src, name) {
  const m = new RegExp(`[^\\w$]${name}=[\\[{]`).exec(src);
  if (!m) throw new Error(`svg-extract: ${name} not found`);
  const start = m.index + name.length + 2;
  const open = src[start];
  const close = open === '[' ? ']' : '}';
  let depth = 0;
  let tpl = false;
  for (let k = start; k < src.length; k++) {
    const ch = src[k];
    if (ch === '`') tpl = !tpl;
    if (tpl) continue;
    if (ch === open) depth++;
    if (ch === close && --depth === 0) return (0, eval)(`(${src.slice(start, k + 1)})`);
  }
  throw new Error(`svg-extract: ${name} unbalanced`);
}

function attrsOf(tag) {
  const o = {};
  for (const m of tag.matchAll(/([\w:-]+)="([^"]*)"/g)) o[m[1]] = m[2];
  return o;
}

/** `<svg ...>children</svg>` to { svg: attrs without class/style, kids: [{ tag, attrs }] } */
function parseSvg(src) {
  const open = /^<svg\b([^>]*)>/.exec(src);
  if (!open) throw new Error('svg-extract: not an svg');
  const { class: _c, style: _s, ...svg } = attrsOf(open[1]);
  const kids = [...src.matchAll(/<(path|circle|ellipse|line|rect|polyline|polygon)\b([^>]*?)\/?>/g)].map((m) => ({
    tag: m[1],
    attrs: Object.fromEntries(Object.entries(attrsOf(m[2])).filter(([k]) => k !== 'class' && k !== 'style')),
  }));
  return { svg, kids };
}

export function extractSvg() {
  const html = readFileSync(pageFile, 'utf8');
  const nodeFile = readdirSync(nodesDir).find((f) => /^2\..*\.js$/.test(f));
  if (!nodeFile) throw new Error('svg-extract: snapshot nodes/2.*.js not found');
  const js = readFileSync(join(nodesDir, nodeFile), 'utf8');

  const base = balanced(js, 'LE');
  const words = balanced(js, 'RE').filter((w) => !w.hidden);

  const blocks = [];
  for (const m of html.matchAll(/<svg\b[^>]*>/g)) {
    const end = html.indexOf('</svg>', m.index);
    blocks.push(html.slice(m.index, end + 6).replace(/<!--[\s\S]*?-->/g, ''));
  }
  const jsBlocks = [];
  for (const m of js.matchAll(/<svg\b[^>]*>.*?<\/svg>/g)) jsBlocks.push(m[0]);
  const jsContext = (needle) => {
    const at = js.indexOf(needle);
    if (at < 0) throw new Error(`svg-extract: ${needle} not found`);
    const from = js.indexOf('<svg', at);
    return js.slice(from, js.indexOf('</svg>', from) + 6);
  };
  const jsSelf = (needle) => {
    const at = js.indexOf(needle);
    if (at < 0) throw new Error(`svg-extract: ${needle} not found`);
    const from = js.lastIndexOf('<svg', at);
    return js.slice(from, js.indexOf('</svg>', from) + 6);
  };
  const jsReview = (n) => {
    const hit = jsBlocks.filter((b) => b.includes('svelte-19hdikk'));
    if (hit.length !== 4) throw new Error('svg-extract: review icons not found');
    return parseSvg(hit[n]);
  };
  const many = (name, test) => {
    const hit = blocks.filter(test);
    if (hit.length === 0) throw new Error(`svg-extract: ${name} not found`);
    return hit.map(parseSvg);
  };
  const one = (name, test) => many(name, test)[0];

  const wordmarkSvg = blocks.find((b) => b.startsWith('<svg class="svelte-1l8nvlt"'));
  if (!wordmarkSvg) throw new Error('svg-extract: nav wordmark not found');
  const wordmark = {
    viewBox: /viewBox="([^"]*)"/.exec(wordmarkSvg)[1],
    width: /width="([^"]*)"/.exec(wordmarkSvg)[1],
    paths: [...wordmarkSvg.matchAll(/<path d="([^"]*)"/g)].map((m) => m[1]),
  };

  const gen = {
    wordmark,
    accent: { base: base.paths, words: words.map((w) => ({ label: w.label, viewBox: w.viewBox, paths: w.paths })) },
    art: {
      'nav.globe': one('nav.globe', (s) => s.startsWith('<svg viewBox="0 0 24 24" class="svelte-1lc7nmb">')),
      'icon.bell': one('icon.bell', (s) => s.includes('solar-bell-linear')),
      'icon.calendar': one('icon.calendar', (s) => s.includes('solar-calendar-linear')),
      'platform.star': one('platform.star', (s) => /^<svg viewBox="0 0 24 24" aria-hidden="true"><path d="[^"]{100}"><\/path><\/svg>$/.test(s)),
      'platform.pin': one('platform.pin', (s) => s.includes('<circle cx="12" cy="10" r="2.25">')),
      'platform.shield': one('platform.shield', (s) => s.includes('width="67.2" height="67.2" viewBox="0 0 46 46"')),
      'brand.mark': one('brand.mark', (s) => s.includes('viewBox="0 0 74 66"')),
      'commission.chevron': one('commission.chevron', (s) => s.includes('class="why-link-chevron"')),
      'hero.cue': one('hero.cue', (s) => s.includes('viewBox="0 0 20 20"')),
      'drawer.mark': parseSvg(jsSelf('class="why-bring-mark"')),
      'nav.chevron': parseSvg(jsSelf('class="start-selling-language-switch__chevron')),
      'nav.langCheck': parseSvg(jsSelf('class="start-selling-language-switch-option__check')),
      'platform.search': one('platform.search', (s) => s.startsWith('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"') && s.includes('<circle')),
      'platform.check': one('platform.check', (s) => s.startsWith('<svg viewBox="0 0 24 24"><circle')),
      'platform.dashLeft': one('platform.dashLeft', (s) => s.includes('secure-network-dash-left"') && s.includes('<line')),
      'platform.dashRight': one('platform.dashRight', (s) => s.includes('secure-network-dash-right"') && s.includes('<line')),
      'people.star': parseSvg(jsSelf('class="star svelte-ndydzv"')),
      'people.mute': parseSvg(jsContext('class="mute svelte-18m48uz"')),
      'people.play': parseSvg(jsContext('class="video svelte-18m48uz"')),
      'people.clock': parseSvg(jsSelf('class="clock svelte-18m48uz"')),
      'review.bolt': jsReview(0),
      'review.shield': jsReview(1),
      'review.star': jsReview(2),
      'review.tag': jsReview(3),
      'drawer.close': parseSvg(jsContext('class="why-bring-close">')),
      'commission.underline': many('commission.underline', (s) => s.includes('class="underline-frame')),
      'commission.zero': many('commission.zero', (s) => s.includes('class="zero-frame')),
    },
  };
  const text = `${JSON.stringify(gen)}\n`;
  let old = null;
  try {
    old = readFileSync(OUT, 'utf8');
  } catch {
    /* first run */
  }
  if (old !== text) writeFileSync(OUT, text);
  return gen;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) extractSvg();
