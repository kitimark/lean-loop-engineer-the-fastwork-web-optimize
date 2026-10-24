// Invisible-paint lane, summary of the jobs' artifacts.
//   node src/repaint-summary.mjs <dir with wktr-j*/ subdirectories> [--out <dir>]
// Reads table-<arm>-<pass>.json and counts-<arm>-<zone>-<pass>.json of every job, sums the part x zone tables per arm, writes the
// per-100-frames numbers (Lean `per100`, twin in measure-webkit paintclip.mjs) as summary.md / summary.json, and decides the
// determinism class of every count type per arm and zone over the jobs with fwcore (kMax 4, tMax 24). Nothing is decided here.
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { per100, CLASSES } from '../../measure-webkit/src/paintclip.mjs';
import { sumTables, ZONES, PARTS, ARMS } from './repaint.mjs';

const top = (o, n = 2) => Object.entries(o).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).slice(0, n).map(([k, v]) => `${k} (${v})`).join('; ');

/** Tables of all jobs: { arm: { tables: [table...], frames: {zone: n}, runs: n } } from table files [{ arm, ...file }]. */
export function groupByArm(files) {
  const out = {};
  for (const f of files) {
    const a = (out[f.meta.arm] ??= { tables: [], frames: Object.fromEntries(ZONES.map((z) => [z, 0])), calls: Object.fromEntries(ZONES.map((z) => [z, 0])), runs: 0, meta: [] });
    a.tables.push(f.table);
    a.runs++;
    for (const z of ZONES) { a.frames[z] += f.frames[z] ?? 0; a.calls[z] += f.calls?.[z] ?? 0; }
    a.meta.push({ pass: f.meta.pass, label: f.meta.label, wallMs: f.meta.wallMs, probe: f.meta.probe, configHash: f.meta.configHash, innerWidth: f.meta.page?.innerWidth, innerHeight: f.meta.page?.innerHeight, dpr: f.meta.page?.dpr, docH: f.meta.page?.docH, maxY: f.meta.page?.maxY, recordErrors: f.meta.page?.recordErrors ?? 0, fw: f.meta.page?.fw ?? null });
  }
  return out;
}

/** Rows of one arm: per zone and part, per-100-frames paints, invisible paints by class, wasted area, causes, re-raster. */
export function armRows(arm) {
  const sum = sumTables(arm.tables);
  const rows = [];
  for (const z of ZONES) {
    const frames = arm.frames[z];
    for (const part of PARTS) {
      const c = sum.find((x) => x.zone === z && x.part === part);
      if (!c) continue;
      const inv = CLASSES.filter((k) => k !== 'visible').reduce((s, k) => s + c.byClass[k].n, 0);
      rows.push({
        zone: z, part, frames,
        paintsPer100: per100(c.rects, frames), invisiblePer100: per100(inv, frames),
        byClassPer100: Object.fromEntries(CLASSES.map((k) => [k, per100(c.byClass[k].n, frames)])),
        areaPer100: per100(c.area, frames), wastePer100: per100(c.waste, frames),
        reRasterLayersPer100: per100(c.reRaster.layers, frames), reRasterAreaPer100: per100(c.reRaster.area, frames),
        causes: top(c.causes, 3), elements: top(c.els, 3),
      });
    }
  }
  return rows;
}

const f = (n) => String(n);
/** A markdown table of the rows of one arm. */
export function toMarkdown(arm, name, classes) {
  const lines = [`### ${name} (${arm.runs} runs, frames ${ZONES.map((z) => `${z} ${arm.frames[z]}`).join(', ')})`, '',
    '| zone | part | paints/100f | invisible/100f | waste px/100f | zero-area | hidden | clipped | beyond | prepaint | re-raster layers/100f | re-raster px/100f | causes (non-visible) | elements (non-visible) |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'];
  const sum = sumTables(arm.tables);
  const callsLine = ZONES.map((z) => `${z} ${per100(arm.calls[z], arm.frames[z])} calls -> ${per100(sum.filter((c) => c.zone === z).reduce((s, c) => s + c.rects, 0), arm.frames[z])} kept`).join(', ');
  for (const r of armRows(arm)) {
    lines.push(`| ${r.zone} | ${r.part} | ${f(r.paintsPer100)} | ${f(r.invisiblePer100)} | ${f(r.wastePer100)} | ${f(r.byClassPer100['zero-area'])} | ${f(r.byClassPer100.hidden)} | ${f(r.byClassPer100['clipped-out'])} | ${f(r.byClassPer100['beyond-margin'])} | ${f(r.byClassPer100['prepaint-margin'])} | ${f(r.reRasterLayersPer100)} | ${f(r.reRasterAreaPer100)} | ${r.causes || '-'} | ${r.elements || '-'} |`);
  }
  lines.push('', `Tracked repaint calls per 100 frames and the dirty rects the engine keeps (Lean \`dirty\`): ${callsLine}`);
  if (classes) {
    lines.push('', `Count-type classes over the ${arm.runs} runs (kMax 4, tMax 24):`, '');
    for (const z of ZONES) {
      const cz = classes[z];
      if (!cz) continue;
      const by = {};
      for (const [t, c] of Object.entries(cz)) (by[c.class] ??= []).push(`${t}${c.class === 'stable' ? `(k${c.k},t${c.t})` : ''}`);
      lines.push(`- ${z}: ${Object.entries(by).map(([k, v]) => `${k}: ${v.join(', ')}`).join(' | ') || 'none'}`);
    }
  }
  return lines.join('\n');
}

/** Read every job dir under `dir`: table files and the counts files per arm and zone. */
export function readJobs(dir) {
  const tables = [];
  const counts = {};
  for (const d of readdirSync(dir).filter((x) => /^wktr-j/.test(x)).sort()) {
    const jd = join(dir, d);
    for (const name of readdirSync(jd)) {
      let m = /^table-(\w+)-(\d+)\.json$/.exec(name);
      if (m) { const t = JSON.parse(readFileSync(join(jd, name), 'utf8')); tables.push({ meta: t.meta, frames: t.frames, calls: t.calls, table: t.table, job: d }); continue; }
      m = /^counts-(\w+)-(hero|rest|finish)-(\d+)\.json$/.exec(name);
      if (m) ((counts[m[1]] ??= {})[m[2]] ??= []).push(join(jd, name));
    }
  }
  return { tables, counts };
}

async function main() {
  const argv = process.argv.slice(2);
  const oi = argv.indexOf('--out');
  const dir = resolve(argv.find((a, i) => !a.startsWith('--') && !(oi >= 0 && i === oi + 1)) ?? '.');
  const out = resolve(oi >= 0 ? argv[oi + 1] : join(dir, 'summary'));
  mkdirSync(out, { recursive: true });
  const { tables, counts } = readJobs(dir);
  const arms = groupByArm(tables);
  let classifyFn = null;
  if (process.env.FW_CORE_BIN || existsSync(join(resolve(import.meta.dirname, '../../../lean/.lake/build/bin/fwcore')))) ({ classify: classifyFn } = await import('../../measure-chromium/src/fwcore.mjs'));
  const md = ['## Invisible paint, WKTR repaint rects per frame (MEASURED, macOS WebKit in the iOS 26.5 Simulator; counts, not time)', ''];
  const json = {};
  for (const name of Object.keys(ARMS)) {
    const arm = arms[name];
    if (!arm) { md.push(`### ${name}: no run`, ''); continue; }
    const classes = {};
    if (classifyFn) {
      for (const z of ZONES) {
        const files = counts[name]?.[z] ?? [];
        if (files.length >= 2) classes[z] = classifyFn(files.map((p) => ({ frames: JSON.parse(readFileSync(p, "utf8")).frames })), 4, 24);
      }
    }
    json[name] = { runs: arm.runs, frames: arm.frames, calls: arm.calls, meta: arm.meta, rows: armRows(arm), classes };
    md.push(toMarkdown(arm, name, classifyFn ? classes : null), '');
  }
  writeFileSync(join(out, 'summary.md'), md.join('\n'));
  writeFileSync(join(out, 'summary.json'), JSON.stringify(json, null, 1));
  console.log(md.join('\n'));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
