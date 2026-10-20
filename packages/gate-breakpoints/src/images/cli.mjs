// node src/images/cli.mjs audit   --engine chromium|playwright-webkit --arms rewrite,original [--widths 390,1512|lean] [--dprs 1,2,3] --out DIR
//                                 [--pool 2] [--drawn drawn.json]   (arm "drawn" = the images-at-drawn-size arm, arm.mjs)
// node src/images/cli.mjs summary --in DIR[,DIR...] --out DIR        (ranked tables, per-cell rows, canonical hash per file)
// node src/images/cli.mjs compare --in A.json,B.json,...             (canonical hashes of the same engine and arm across reps)
// node src/images/cli.mjs arm     build --audit images-chromium-rewrite.json --out DIR   (resized copies + drawn.json; arm-build.mjs)
// node src/images/cli.mjs arm     check                                                    (files and sources against drawn.json)
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { siteDist, snapshotRoot } from '../serve.mjs';
import { composeRewrite, drawnFile, loadDrawn } from './arm.mjs';
import { leanWidths, runAudit } from './audit.mjs';
import { aggregate, fileReader, LAG_REGIONS, mb, rank, rowsOfCell, tableMd, totals } from './reduce.mjs';

const arg = (name, dflt = undefined) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : dflt;
};
const list = (s) => (s ? s.split(',').map((x) => x.trim()).filter(Boolean) : []);

/** The canonical content of a file's readings: what the layout and the files said, with ids and timing left out. */
export function canon(file) {
  const cells = Object.keys(file.cells).sort().map((k) => {
    const c = file.cells[k];
    if (c.error) return [k, 'error'];
    const items = c.items.map((it) => [it.kind, it.prop ?? '', it.url, it.nat, it.box.map((x) => +x.toFixed(2)), it.img.map((x) => +x.toFixed(2)), it.none, it.fw, [...new Set(it.effects.map((e) => `${e.at}|${e.up}|${e.e.replace(/=.*/, '').replace(/:\w+$/, '')}`))].sort()]);
    items.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
    return [k, c.docHeight, items];
  });
  return createHash('sha256').update(JSON.stringify(cells)).digest('hex').slice(0, 16);
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
        console.log(`${tag}/${f}: canon ${c} cells ${Object.keys(rows).length}`);
      }
    }
    for (const [k, v] of canons) console.log(`${k}: ${v.length} runs, ${new Set(v.map((x) => x.canon)).size} distinct canon`);
    writeFileSync(join(out, 'images-summary.md'), md.join('\n\n') + '\n');
    writeFileSync(join(out, 'images-canon.json'), JSON.stringify(Object.fromEntries(canons)));
    return;
  }
  if (cmd === 'compare') {
    const hs = list(arg('in')).map((p) => { const f = JSON.parse(readFileSync(p, 'utf8')); return [p, f.engine, f.arm, canon(f)]; });
    for (const h of hs) console.log(h.join('  '));
    const same = new Set(hs.map((h) => `${h[1]}/${h[2]}/${h[3]}`)).size === new Set(hs.map((h) => `${h[1]}/${h[2]}`)).size;
    console.log(same ? 'canon: equal across reps' : 'canon: DIFFERENT across reps');
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
