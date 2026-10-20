// The note's ranked table (task image-audit): one row per image file of a lag region, from the per-cell rows that
// `cli.mjs summary` writes (images-rows-*.json: { engine, arm, rows: { "w<width>@<dpr>": [row] } }), the union of the reps.
// Pure apart from the file reads of `tablesMd`'s caller. A row says, per file: natural size, format, bytes on disk (KiB), decoded MiB
// (natural pixels x 4), the device pixels it is drawn at in the two headline cells, the waste ratio (natural / drawn pixels) in
// each cell of the headline widths and its range over every cell where the file is drawn, and the effects above it.
//   node src/images/cli.mjs table --in DIR[,DIR...] --engine E --arm A [--limit-people 12]
import { aggregate, kb, LAG_REGIONS, mb } from './reduce.mjs';

/** Headline cells in column order: the widths of a Mac Safari window and an iPhone, at the DPRs the audit ran there. */
export const HEAD = ['w1512@1', 'w1512@2', 'w1512@3', 'w430@1', 'w430@3'];
/** The effects column reads these two cells only (the union of the reps): an effect seen in one odd width is in the artifact rows, not here. */
export const FX_CELLS = ['w1512@2', 'w430@3'];
export const CODE = { filter: 'F', 'filter-anim': 'Fa', 'backdrop-filter': 'B', 'opacity<1': 'O', 'opacity-anim': 'Oa', transform: 'T', 'transform-anim': 'Ta', mask: 'M', 'clip-path': 'C', blend: 'X' };
const kindOf = (c) => c.replace(/@.*$/, '');
const key = (a) => `${a.url}|${a.kind}${a.prop ?? ''}`;
const short = (u) => u.replace(/^\/selling\//, '').replace(/^\/assets\//, 'a/').replace(/^(a\/.*)-[A-Za-z0-9_-]{8}(\.\w+)$/, '$1$2');

/** Per region, per file key: the union over reps of the per-cell aggregates. `files` are parsed rows files. */
export function gather(files) {
  const out = new Map(); // region -> Map(key -> { head, cells: Map(cell -> aggregate), effects: Set, reps })
  for (const f of files) {
    for (const [cell, rows] of Object.entries(f.rows)) {
      for (const region of LAG_REGIONS) {
        const aggs = aggregate(rows.filter((x) => x.region === region));
        for (const a of aggs) {
          if (!out.has(region)) out.set(region, new Map());
          const m = out.get(region);
          let e = m.get(key(a));
          if (!e) { e = { base: a, cells: new Map(), effects: new Map() }; m.set(key(a), e); }
          const prev = e.cells.get(cell);
          // the file must serve the largest drawn reading of any rep
          if (!prev || (a.drawnCount > 0 && a.drawnPx > prev.drawnPx) || prev.drawnCount === 0) e.cells.set(cell, a);
          if (a.drawnCount > 0 && FX_CELLS.includes(cell)) for (const c of a.effects) e.effects.set(kindOf(c), (e.effects.get(kindOf(c)) ?? 0) + 1);
        }
      }
    }
  }
  return out;
}

const waste = (a) => (a && a.drawnCount > 0 && a.drawnPx > 0 ? a.natPx / a.drawnPx : null);
const fx = (n) => (n == null ? '-' : n.toFixed(1));

/** The row of one file: pure data. */
export function rowOf(e) {
  const b = e.base;
  const per = [...e.cells.entries()].map(([c, a]) => ({ cell: c, w: waste(a), dev: a.drawnCount > 0 ? `${a.devW}x${a.devH}` : null, a })).filter((x) => x.w != null);
  const lo = per.reduce((m, x) => (m == null || x.w < m.w ? x : m), null);
  const hi = per.reduce((m, x) => (m == null || x.w > m.w ? x : m), null);
  const wasted = (cell) => { const a = e.cells.get(cell); return a && a.drawnCount > 0 ? a.wastedBytes : 0; };
  return {
    url: b.url, kind: b.kind, prop: b.prop, natW: b.natW, natH: b.natH, format: b.format, bytes: b.bytes, decoded: b.decodedBytes,
    dev: Object.fromEntries(['w1512@2', 'w430@3'].map((c) => [c, e.cells.get(c)?.drawnCount > 0 ? `${e.cells.get(c).devW}x${e.cells.get(c).devH}` : null])),
    waste: Object.fromEntries(HEAD.map((c) => [c, waste(e.cells.get(c))])),
    lo, hi, drawnIn: per.length, cellsSeen: e.cells.size,
    // the rank key: the largest wasted decoded bytes in the two headline cells
    score: Math.max(wasted('w1512@2'), wasted('w430@3')),
    effects: [...e.effects.keys()].filter((k) => CODE[k]).sort().map((k) => CODE[k]).join(' ') || '-',
  };
}

export function tablesMd(files, { limit = { hero: 99, morph: 99, people: 12 }, label = '' } = {}) {
  const g = gather(files);
  const L = [];
  for (const region of LAG_REGIONS) {
    const m = g.get(region);
    if (!m) continue;
    const rows = [...m.values()].map(rowOf).sort((a, b) => b.score - a.score || b.decoded - a.decoded || a.url.localeCompare(b.url));
    const drawnRows = rows.filter((r) => r.drawnIn > 0);
    const dec = drawnRows.reduce((s, r) => s + r.decoded, 0);
    const disk = rows.reduce((s, r) => s + (r.bytes ?? 0), 0);
    L.push(`**${region}${label}**: ${rows.length} files (${drawnRows.length} drawn in some cell), ${mb(disk)} MiB on disk, ${mb(dec)} MiB decoded (natural pixels x 4)`, '');
    L.push('| # | file | natural | fmt | KiB | decoded MiB | drawn px at 1512@2 | drawn px at 430@3 | waste x at 1512@1 / @2 / @3 | at 430@1 / @3 | waste x range over all cells (cells drawn) | effects above it |', '|---|---|---|---|---|---|---|---|---|---|---|---|');
    rows.slice(0, limit[region] ?? 99).forEach((r, i) => {
      const w = r.waste;
      const range = r.lo ? `${fx(r.lo.w)} (${r.lo.cell}) to ${fx(r.hi.w)} (${r.hi.cell}) (${r.drawnIn})` : 'never drawn';
      L.push(`| ${i + 1} | ${short(r.url)}${r.kind === 'bg' ? ` (${r.prop})` : ''} | ${r.natW}x${r.natH} | ${r.format} | ${kb(r.bytes)} | ${mb(r.decoded)} | ${r.dev['w1512@2'] ?? '-'} | ${r.dev['w430@3'] ?? '-'} | ${fx(w['w1512@1'])} / ${fx(w['w1512@2'])} / ${fx(w['w1512@3'])} | ${fx(w['w430@1'])} / ${fx(w['w430@3'])} | ${range} | ${r.effects} |`);
    });
    if ((limit[region] ?? 99) < rows.length) L.push('', `(${rows.length - limit[region]} more files in the artifact rows)`);
    L.push('');
  }
  return L.join('\n');
}
