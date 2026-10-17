// Build: client bundle -> SSR bundle -> prerender (+ Emotion AOT extraction) -> static HTML.
//   node scripts/build.mjs --engine aot|runtime
// Output: dist/<engine>/ (served), dist/.ssr-<engine>/ (build-only server bundle).
import react from '@vitejs/plugin-react';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build } from 'vite';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const argEngine = process.argv.indexOf('--engine');
const engine = argEngine > 0 ? process.argv[argEngine + 1] : 'aot';
if (engine !== 'aot' && engine !== 'runtime') throw new Error(`--engine must be aot|runtime, got ${engine}`);

process.env.NODE_ENV = 'production';
const require = createRequire(path.join(root, 'package.json'));
const ver = (name) => JSON.parse(require('node:fs').readFileSync(require.resolve(`${name}/package.json`), 'utf8')).version;
const buildId = {
  engine,
  mui: ver('@mui/material'),
  emotionReact: ver('@emotion/react'),
  emotionCache: ver('@emotion/cache'),
  react: ver('react'),
  vite: ver('vite'),
};

const outDir = path.join(root, 'dist', engine);
const ssrDir = path.join(root, 'dist', `.ssr-${engine}`);
const base = {
  root,
  configFile: false,
  logLevel: 'warn',
  plugins: [react()],
  define: { __FW_ENGINE__: JSON.stringify(engine), __FW_BUILD__: JSON.stringify(buildId) },
  css: { modules: { generateScopedName: '[name]_[local]_[hash:base64:6]' } },
};

const t0 = performance.now();
await build({
  ...base,
  build: {
    outDir,
    emptyOutDir: true,
    manifest: true,
    rollupOptions: { input: path.join(root, 'src/entry-client.tsx') },
  },
});
const t1 = performance.now();

await build({
  ...base,
  ssr: { noExternal: [/^@mui\//, /^@emotion\//] },
  build: { ssr: path.join(root, 'src/entry-server.tsx'), outDir: ssrDir, emptyOutDir: true, copyPublicDir: false },
});
const t2 = performance.now();

const { prerender } = await import(pathToFileURL(path.join(ssrDir, 'entry-server.js')).href);
const pre = prerender();
const t3 = performance.now();

// ---- assemble the static page
const manifest = JSON.parse(await readFile(path.join(outDir, '.vite/manifest.json'), 'utf8'));
const entry = manifest['src/entry-client.tsx'];
if (!entry) throw new Error('entry missing from manifest');
const collect = (chunk, seen = new Set()) => {
  for (const k of chunk.imports ?? []) if (!seen.has(k)) (seen.add(k), collect(manifest[k], seen));
  return seen;
};
const imported = [...collect(entry)].map((k) => manifest[k]);
const appCss = [...new Set([...imported.flatMap((c) => c.css ?? []), ...(entry.css ?? [])])];

let head = '';
let scripts = '';
let muiCssName = null;
let muiCss = '';
if (engine === 'aot') {
  muiCss = `@layer reset, mui, parts, flags;\n@layer mui{${pre.themeCss}${pre.css}}\n`;
  muiCssName = `mui.${createHash('sha256').update(muiCss).digest('hex').slice(0, 8)}.css`;
  await writeFile(path.join(outDir, muiCssName), muiCss);
  await writeFile(path.join(outDir, 'emotion-ids.json'), JSON.stringify(pre.ids));
  head += `<link rel="stylesheet" href="/${muiCssName}">`; // first: it declares the layer order
  scripts += `<script type="application/json" id="fw-emotion-ids">${JSON.stringify(pre.ids)}</script>`;
} else {
  head += pre.styleTags; // plain Emotion SSR: inline <style data-emotion="mui ..."> tags
}
for (const css of appCss) head += `<link rel="stylesheet" href="/${css}">`;
for (const c of imported) head += `<link rel="modulepreload" href="/${c.file}">`;
scripts += `<script type="module" src="/${entry.file}"></script>`;

const template = await readFile(path.join(root, 'index.html'), 'utf8');
const html = template
  .replace('<!--fw-head-->', () => head)
  .replace('<!--fw-config-->', pre.configHash)
  .replace('<!--fw-root-->', () => pre.homeHtml)
  .replace('<!--fw-scripts-->', () => scripts);
await writeFile(path.join(outDir, 'index.html'), html);
await writeFile(path.join(root, 'dist', `.census-${engine}.html`), pre.censusHtml);

// ---- build gates (PLAN 6.5)
const gates = [];
const gate = (name, ok, detail = '') => gates.push({ name, ok, detail });
if (engine === 'aot') {
  gate('no <style> tag in prerendered HTML', !/<style[\s>]/i.test(html));
  gate('no data-emotion in prerendered HTML', !/data-emotion/.test(html));
  gate('census produced ids', pre.ids.length > 0, `${pre.ids.length} ids`);
  const bad = muiCss.match(/[:(\s](null|undefined|NaN)(px|%|em|rem|vh|vw|s|ms)?[;}\s)]/g);
  gate('no null/undefined/NaN in emitted CSS', !bad, bad ? bad.slice(0, 5).join(' | ') : '');
  gate('layer order declared first', muiCss.startsWith('@layer reset, mui, parts, flags;'));
}
const failed = gates.filter((g) => !g.ok);

const info = {
  buildId,
  configHash: pre.configHash,
  ms: {
    client: Math.round(t1 - t0),
    ssr: Math.round(t2 - t1),
    prerender: Math.round(t3 - t2),
    assemble: Math.round(performance.now() - t3),
    total: Math.round(performance.now() - t0),
  },
  bytes: { html: html.length, muiCss: muiCss.length },
  emotionIds: pre.ids.length,
  stats: pre.stats,
  muiCss: muiCssName,
  gates,
};
await mkdir(outDir, { recursive: true });
await writeFile(path.join(outDir, 'build-info.json'), JSON.stringify(info, null, 2));
console.log(`[${engine}] built in ${info.ms.total} ms`, JSON.stringify(info.ms));
console.log(`[${engine}] ids=${info.emotionIds} muiCss=${info.bytes.muiCss}B html=${info.bytes.html}B`);
for (const g of gates) console.log(`  gate ${g.ok ? 'PASS' : 'FAIL'}: ${g.name} ${g.detail}`);
if (failed.length) process.exit(1);
