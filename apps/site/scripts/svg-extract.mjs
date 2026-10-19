// Reads the original's inline SVG path data from the unmodified snapshot into the gitignored src/svg.gen.json.
// Path data is Fastwork material: it is never committed (svg-extract.test.ts fails if a tracked file holds it).
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../../../snapshot/site/', import.meta.url));
const out = fileURLToPath(new URL('../src/svg.gen.json', import.meta.url));

const html = readFileSync(join(root, 'index.html'), 'utf8');
const nodesDir = join(root, '_app/immutable/nodes/');
const nodeFile = readdirSync(nodesDir).find((f) => /^2\..*\.js$/.test(f));
if (!nodeFile) throw new Error('svg-extract: snapshot nodes/2.*.js not found');
const js = readFileSync(join(nodesDir, nodeFile), 'utf8');

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

const base = balanced(js, 'LE');
const words = balanced(js, 'RE').filter((w) => !w.hidden);

const svgStart = html.indexOf('<svg class="svelte-1l8nvlt"');
const svgEnd = html.indexOf('</svg>', svgStart);
if (svgStart < 0 || svgEnd < 0) throw new Error('svg-extract: nav wordmark not found');
const wordmarkSvg = html.slice(svgStart, svgEnd);
const wordmark = {
  viewBox: /viewBox="([^"]*)"/.exec(wordmarkSvg)[1],
  width: /width="([^"]*)"/.exec(wordmarkSvg)[1],
  paths: [...wordmarkSvg.matchAll(/<path d="([^"]*)"/g)].map((m) => m[1]),
};

const gen = {
  wordmark,
  accent: { base: base.paths, words: words.map((w) => ({ label: w.label, viewBox: w.viewBox, paths: w.paths })) },
};
writeFileSync(out, `${JSON.stringify(gen)}\n`);
