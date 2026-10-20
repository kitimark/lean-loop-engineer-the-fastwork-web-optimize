// node src/images/cli.mjs audit   --engine chromium|playwright-webkit --arms rewrite,original [--widths 390,1512|lean] [--dprs 1,2,3] --out DIR
//                                 [--pool 2] [--drawn drawn.json]   (arm "drawn" = the images-at-drawn-size arm, arm.mjs)
// node src/images/cli.mjs summary --in DIR[,DIR...] --out DIR        (ranked tables, per-cell rows, key hash and stability per engine/arm)
// node src/images/cli.mjs compare --in A.json,B.json,...             (key hash and stability of the same engine and arm across reps)
// node src/images/cli.mjs arm     build --audit images-chromium-rewrite.json --out DIR   (resized copies + drawn.json; arm-build.mjs)
// node src/images/cli.mjs arm     check                                                    (files and sources against drawn.json)
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { siteDist, snapshotRoot } from '../serve.mjs';
import { composeRewrite, drawnFile, loadDrawn } from './arm.mjs';
import { leanWidths, runAudit } from './audit.mjs';
import { aggregate, effectClasses, fileReader, LAG_REGIONS, mb, regionOf, rowsOfCell, tableMd, totals } from './reduce.mjs';

const arg = (name, dflt = undefined) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : dflt;
};
const list = (s) => (s ? s.split(',').map((x) => x.trim()).filter(Boolean) : []);

const kindOf = (c) => c.replace(/@.*$/, '');

/** Per (cell, region, url): natural size, largest drawn CSS size and the set of effect kinds seen. Items with display none are left out. */
export function keyed(file) {
  const m = new Map();
  for (const [k, c] of Object.entries(file.cells)) {
    if (c.error) continue;
    for (const it of c.items) {
      if (it.none) continue;
      const key = `${k}|${regionOf(it)}|${it.url}`;
      const e = m.get(key) ?? { nat: it.nat.join('x'), w: 0, h: 0, kinds: new Set() };
      e.w = Math.max(e.w, Math.round(it.img[0]));
      e.h = Math.max(e.h, Math.round(it.img[1]));
      for (const c2 of effectClasses(it)) e.kinds.add(kindOf(c2));
      m.set(key, e);
    }
  }
  return m;
}

/**
 * The canonical content of a file: which image URLs sit in which region of which cell, and their natural sizes. The page is
 * live (native rAF), so drawn sizes move by a pixel or two and effect kinds follow the animation phase; those are compared
 * by `stability`, not hashed.
 */
export function canon(file) {
  const rows = [...keyed(file)].map(([k, e]) => `${k}|${e.nat}`).sort();
  const docs = Object.keys(file.cells).sort().map((k) => [k, file.cells[k].error ? 'error' : 1]);
  return createHash('sha256').update(JSON.stringify([docs, rows])).digest('hex').slice(0, 16);
}

/** How much the readings of the same engine and arm differ across reps, counted per (cell, region, url) key. */
export function stability(files) {
  const per = files.map(keyed);
  const keys = new Set(per.flatMap((m) => [...m.keys()]));
  const r = { reps: files.length, keys: keys.size, absentInSomeRep: 0, natDiffers: 0, sizeOver1px: 0, size1px: 0, kindSetDiffers: 0, kindFreq: {} };
  for (const k of keys) {
    const es = per.map((m) => m.get(k));
    if (es.some((e) => !e)) { r.absentInSomeRep++; continue; }
    if (new Set(es.map((e) => e.nat)).size > 1) r.natDiffers++;
    const dw = Math.max(...es.map((e) => e.w)) - Math.min(...es.map((e) => e.w));
    const dh = Math.max(...es.map((e) => e.h)) - Math.min(...es.map((e) => e.h));
    if (dw > 1 || dh > 1) r.sizeOver1px++; else if (dw || dh) r.size1px++;
    if (new Set(es.map((e) => [...e.kinds].sort().join(','))).size > 1) {
      r.kindSetDiffers++;
      for (const x of new Set(es.flatMap((e) => [...e.kinds]))) if (es.some((e) => !e.kinds.has(x))) r.kindFreq[x] = (r.kindFreq[x] ?? 0) + 1;
    }
  }
  return r;
}

/** Rows of every cell of an audit file; `rootOf(file)` is the served root. */
export function rowsOfFile(file, rootOf, drawnPath = undefined) {
  const root = rootOf(file);
  const m = file.arm === 'drawn' ? loadDrawn(drawnPath) : null;
  const plain = fileReader(root);
  const out = {};
  for (const [k, c] of Object.entries(file.cells)) {
    if (c.error) continue;
    out[k] = rowsOfCell(c, m ? fileReader(root, (u) => drawnFile(m, u, c.width, c.dpr) ?? u) : plain);
  }
  return out;
}

const rootOf = (f) => (f.arm === 'original' ? snapshotRoot() : siteDist());

/** The headline cells: a Mac Safari window and an iPhone, plus the extremes. */
export const HEADLINE = ['w1512@2', 'w430@3'];

export function summaryMd(file, rows) {
  const L = [`## ${file.engine} / ${file.arm} (${file.version}; canon ${canon(file)})`, ''];
  for (const cellKey of HEADLINE) {
    const r = rows[cellKey];
    if (!r) continue;
    L.push(`### ${cellKey}`, '');
    for (const region of LAG_REGIONS) {
      const ag = aggregate(r.filter((x) => x.region === region));
      if (ag.length === 0) continue;
      const t = totals(ag);
      L.push(`Region ${region}: ${t.files} files (${t.filesDrawn} drawn), ${mb(t.bytes)} MB on disk, decoded ${mb(t.decoded)} MB, needed at drawn size ${mb(t.needed)} MB, wasted ${mb(t.wasted)} MB, decoded under a filter ${mb(t.underFilterDecoded)} MB`, '');
      L.push(tableMd(`${region} at ${cellKey}`, ag), '');
    }
  }
  // across the grid: the largest waste per region
  L.push('### Range over the grid (drawn files only)', '', '| cell | hero decoded | hero needed | morph decoded | morph needed | people decoded | people needed |', '|---|---|---|---|---|---|---|');
  for (const [k, r] of Object.entries(rows)) {
    const cols = LAG_REGIONS.map((reg) => totals(aggregate(r.filter((x) => x.region === reg))));
    L.push(`| ${k} | ${cols.map((t) => `${mb(t.decoded)} | ${mb(t.needed)}`).join(' | ')} |`);
  }
  return L.join('\n');
}

async function main() {
  const cmd = process.argv[2];
  if (cmd === 'audit') {
    const engine = arg('engine');
    const out = arg('out', 'out/images');
    const gen = JSON.parse(readFileSync(new URL('../../../../apps/site/src/breakpoints.gen.json', import.meta.url), 'utf8'));
    const wArg = arg('widths', 'lean');
    const widths = wArg === 'lean' ? leanWidths(gen) : list(wArg).map(Number);
    const dprs = list(arg('dprs', '1,2,3')).map(Number);
    for (const arm of list(arg('arms', 'rewrite'))) {
      const armDprs = arm === 'original' && arg('original-dprs') ? list(arg('original-dprs')).map(Number) : dprs;
      const { name, file } = await runAudit({ engine, arm, widths, dprs: armDprs, out, pool: Number(arg('pool', '2')), drawn: arg('drawn'), extra: list(arg('extra')).map((s) => s.split(':').map(Number)) });
      console.log(`wrote ${name} cells=${Object.keys(file.cells).length} errors=${Object.values(file.cells).filter((c) => c.error).length} ${file.ms} ms`);
    }
    return;
  }
  if (cmd === 'summary') {
    const out = arg('out', 'out/images');
    mkdirSync(out, { recursive: true });
    const md = [];
    const canons = new Map();
    const byGroup = new Map();
    for (const dir of list(arg('in', out))) {
      const tag = basename(resolve(dir));
      for (const f of readdirSync(dir).filter((n) => /^images-.*\.json$/.test(n) && !n.startsWith('images-rows'))) {
        const file = JSON.parse(readFileSync(join(dir, f), 'utf8'));
        if (file.schema !== 'fw.images.audit/1') continue;
        const rows = rowsOfFile(file, rootOf);
        const c = canon(file);
        writeFileSync(join(out, `images-rows-${tag}--${f.replace('images-', '')}`), JSON.stringify({ engine: file.engine, arm: file.arm, tag, canon: c, rows }));
        md.push(`<!-- ${tag} -->\n${summaryMd(file, rows)}`);
        const k = `${file.engine}/${file.arm}`;
        canons.set(k, [...(canons.get(k) ?? []), { tag, canon: c }]);
        byGroup.set(k, [...(byGroup.get(k) ?? []), file]);
        console.log(`${tag}/${f}: canon ${c} cells ${Object.keys(rows).length}`);
      }
    }
    const stab = {};
    for (const [k, v] of canons) {
      stab[k] = { ...stability(byGroup.get(k)), distinctKeyHash: new Set(v.map((x) => x.canon)).size };
      console.log(`${k}: ${JSON.stringify(stab[k])}`);
    }
    writeFileSync(join(out, 'images-summary.md'), md.join('\n\n') + '\n');
    writeFileSync(join(out, 'images-canon.json'), JSON.stringify({ canons: Object.fromEntries(canons), stability: stab }));
    return;
  }
  if (cmd === 'compare') {
    const fs = list(arg('in')).map((p) => JSON.parse(readFileSync(p, 'utf8')));
    for (const f of fs) console.log(f.engine, f.arm, canon(f));
    const st = stability(fs);
    console.log(JSON.stringify(st));
    // layout identity: same keys, natural sizes and sizes within a pixel; effect kinds follow the animation phase and are reported only
    const same = st.absentInSomeRep === 0 && st.natDiffers === 0 && st.sizeOver1px === 0;
    console.log(same ? 'layout: same across reps' : 'layout: DIFFERENT across reps');
    process.exit(same ? 0 : 1);
  }
  if (cmd === 'arm') {
    const { armCli } = await import('./arm-build.mjs');
    await armCli(process.argv.slice(3), { arg, list });
    return;
  }
  console.error('usage: audit | summary | compare | arm build|check|verify');
  process.exit(2);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) main().catch((e) => { console.error(e); process.exit(1); });
export { composeRewrite, loadDrawn };
