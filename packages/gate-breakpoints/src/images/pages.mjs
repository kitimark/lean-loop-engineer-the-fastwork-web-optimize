// Page-level check of the images-at-drawn-size arm with the real visual diff (packages/visual-diff, the PL tolerance and the Lean verdict
// twin): the parts of the lag regions are compared original-against-rewrite twice per probe, once with the site build as it is
// (baseline) and once with a tree of the same build in which every image the table names holds the copy that probe (width, DPR)
// gets (drawn). The pages, scripts and styles are byte for byte the same; only image bytes under the same URLs differ, so a
// change of verdict or of pixel count between the two runs is the arm's. Nothing is decided here: counts and verdicts are the
// visual-diff package's, this file runs it twice and sets the numbers side by side.
//   node src/images/cli.mjs arm pages --engine chromium|playwright-webkit --out DIR [--probes id,...] [--parts a,b] [--manifest drawn.json]
import { cpSync, copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { siteDist } from '../serve.mjs';
import { DEFAULT_MANIFEST, drawnFile, loadDrawn } from './arm.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const VISUAL_CLI = resolve(HERE, '../../../visual-diff/src/cli.mjs');
const GEN = resolve(HERE, '../../../../apps/site/src/breakpoints.gen.json');

/** The parts that hold the lag regions' images (data-fw anchors of packages/gate-breakpoints/src/anchors.json). */
export const LAG_PARTS = ['hero', 'hero.orbit', 'hero.deck', 'hero.exit', 'morph.panel', 'morph.columns', 'people.card', 'people.o', 'people.carousel', 'people.deck'];
export const DEFAULT_PROBES = ['desk-1512', 'desk-1100', 'desk-861', 'touch-1031', 'touch-601', 'touch-401', 'touch-320'];

/** A copy of the site build in which the image URLs the table names serve the copy for (width, dpr). Returns the replaced URLs. */
export function materialize({ dist, manifest, width, dpr, out }) {
  rmSync(out, { recursive: true, force: true });
  cpSync(dist, out, { recursive: true });
  const replaced = [];
  for (const url of Object.keys(manifest.images)) {
    const f = drawnFile(manifest, url, width, dpr);
    if (!f) continue;
    const src = join(dist, f.replace(/^\//, ''));
    if (!existsSync(src)) throw new Error(`copy missing in the build: ${f}`);
    copyFileSync(src, join(out, url.replace(/^\//, '')));
    replaced.push(url);
  }
  return replaced;
}

const cellsOf = (file) => {
  const j = JSON.parse(readFileSync(file, 'utf8'));
  const by = new Map();
  for (const p of j.probes) for (const c of p.cells) by.set(`${p.id}|${c.part}`, c);
  return { by, header: j.header };
};

/** Side by side: one row per (probe, part), baseline against drawn. */
export function sideBySide(base, drawn, probes, parts) {
  const rows = [];
  for (const id of probes) {
    for (const part of parts) {
      const b = base.by.get(`${id}|${part}`);
      const d = drawn.by.get(`${id}|${part}`);
      if (!b && !d) continue;
      const pick = (c) => (c ? (c.status === 'compared' ? { verdict: c.verdict, ppm: c.ratioPpm, changed: c.stats.changed, total: c.stats.total, maxDelta: c.stats.maxDelta } : { verdict: c.status }) : { verdict: 'absent' });
      const B = pick(b);
      const D = pick(d);
      rows.push({ probe: id, part, base: B, drawn: D, sameVerdict: B.verdict === D.verdict, dPpm: B.ppm != null && D.ppm != null ? D.ppm - B.ppm : null });
    }
  }
  return rows;
}

export function tableMd(rows) {
  const L = ['| probe | part | baseline | drawn | change of ppm |', '|---|---|---|---|---|'];
  for (const r of rows) {
    const f = (x) => (x.ppm == null ? x.verdict : `${x.verdict} ${x.ppm} ppm`);
    L.push(`| ${r.probe} | ${r.part} | ${f(r.base)} | ${f(r.drawn)}${r.sameVerdict ? '' : ' **VERDICT CHANGED**'} | ${r.dPpm == null ? '-' : (r.dPpm > 0 ? '+' : '') + r.dPpm} |`);
  }
  return L.join('\n');
}

export async function pagesCli(_args, { arg, list }) {
  const engine = arg('engine', 'chromium');
  const out = resolve(arg('out', 'out/images-pages'));
  const probes = list(arg('probes', DEFAULT_PROBES.join(',')));
  const parts = list(arg('parts', LAG_PARTS.join(',')));
  const manifest = loadDrawn(resolve(arg('manifest', DEFAULT_MANIFEST)));
  const dist = siteDist();
  const gen = JSON.parse(readFileSync(GEN, 'utf8'));
  mkdirSync(out, { recursive: true });
  const run = (dir, root, id) => execFileSync(process.execPath, [VISUAL_CLI, 'run', '--engine', engine, '--out', dir, '--probes', id, '--parts', parts.join(',')], { env: { ...process.env, FW_SITE_DIST: root }, stdio: ['ignore', 'inherit', 'inherit'] });
  const sides = [];
  const replacedBy = {};
  for (const id of probes) {
    const p = gen.matrix.probes.find((x) => x.id === id);
    if (!p) throw new Error(`unknown probe ${id}`);
    const tree = join(out, 'tree');
    replacedBy[id] = materialize({ dist, manifest, width: p.width, dpr: p.dpr, out: tree }).length;
    run(join(out, 'base', id), dist, id);
    run(join(out, 'drawn', id), tree, id);
    rmSync(tree, { recursive: true, force: true });
    const base = cellsOf(join(out, 'base', id, `${engine}.visual.json`));
    const drawn = cellsOf(join(out, 'drawn', id, `${engine}.visual.json`));
    sides.push(...sideBySide(base, drawn, [id], parts));
  }
  const changed = sides.filter((r) => !r.sameVerdict).length;
  writeFileSync(join(out, `pages-${engine}.json`), JSON.stringify({ schema: 'fw.images.pages/1', engine, probes, parts, replacedBy, rows: sides }));
  writeFileSync(join(out, `pages-${engine}.md`), `## ${engine}: drawn arm against baseline (${sides.length} cells, ${changed} verdict changes)\n\n${tableMd(sides)}\n`);
  console.log(`pages ${engine}: ${sides.length} cells, ${changed} verdict changes`);
  if (changed) process.exitCode = 1;
}
