// Image audit reducer: readings (audit.mjs) -> rows (one per image per cell) -> ranked tables. Pure apart from reading the served
// file for its byte size and format. The cost terms here (decoded bytes, waste ratio) are the ones proposed for
// lean/Fw/Engine/WebKitImage.lean; the TS here is a stand-in until fwcore reduces them.
import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

/** File format by magic bytes (not by extension). */
export function sniff(buf) {
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpeg';
  if (buf.length >= 12 && buf.subarray(0, 4).toString() === 'RIFF' && buf.subarray(8, 12).toString() === 'WEBP') return 'webp';
  if (buf.length >= 4 && buf.subarray(0, 3).toString() === 'GIF') return 'gif';
  if (buf.length >= 12 && buf.subarray(4, 12).toString().startsWith('ftypavif')) return 'avif';
  const head = buf.subarray(0, 512).toString('utf8').trimStart();
  if (head.startsWith('<svg') || head.startsWith('<?xml')) return 'svg';
  return 'other';
}

const BY_FW = [['hero', 'hero'], ['morph', 'morph'], ['people', 'people'], ['platform', 'platform'], ['commission', 'commission'], ['pain', 'pain'], ['nav', 'nav'], ['overlay', 'overlay']];
const BY_CLS = [[/(^|[\s_-])(orbit|hero|mobile-deck)/i, 'hero'], [/morph|start-selling/i, 'morph'], [/people|profile-feed|carousel|showcase/i, 'people']];

/**
 * Region of a reading: the innermost ancestor that names one (so the morph panel mounted inside the hero's tree is `morph`).
 * The rewrite names regions by data-fw (innermost first in `fw`), the original snapshot by class names (innermost first in `cls`).
 */
export function regionOf(it) {
  for (const f of it.fw ?? []) for (const [p, r] of BY_FW) if (f.startsWith(p)) return r;
  for (const c of it.cls ?? []) for (const [re, r] of BY_CLS) if (re.test(c)) return r;
  return 'other';
}

/** The lag regions: the user sees lag when the hero cards move out and at the end of the page. */
export const LAG_REGIONS = ['hero', 'morph', 'people'];

/** Paint-relevant effects of an item's ancestors, as a sorted list of classes with the nearest distance (0 = the element itself). */
export function effectClasses(it) {
  const best = new Map();
  const put = (k, up, at) => { if (!best.has(k) || best.get(k).up > up) best.set(k, { up, at }); };
  for (const x of it.effects ?? []) {
    const e = x.e;
    if (e.startsWith('filter=')) put('filter', x.up, x.at);
    else if (e.startsWith('backdrop-filter=')) put('backdrop-filter', x.up, x.at);
    else if (e.startsWith('opacity=')) put('opacity<1', x.up, x.at);
    else if (e === 'transform' || e === 'individual-transform') put('transform', x.up, x.at);
    else if (e.startsWith('will-change=')) put('will-change', x.up, x.at);
    else if (e.startsWith('mix-blend-mode=')) put('blend', x.up, x.at);
    else if (e === 'mask' || e === 'clip-path') put(e, x.up, x.at);
    else {
      const m = /^(animation|transition|waapi)\(([^)]*)\):(\w+)$/.exec(e);
      if (m) {
        const props = m[2].split('+');
        if (props.some((p) => /^(opacity)$/.test(p))) put('opacity-anim', x.up, x.at);
        if (props.some((p) => /^(transform|translate|scale|rotate)$/.test(p))) put('transform-anim', x.up, x.at);
        if (props.some((p) => /^(filter|backdrop-filter)$/.test(p))) put('filter-anim', x.up, x.at);
        if (!props.some((p) => /^(opacity|transform|translate|scale|rotate|filter|backdrop-filter)$/.test(p))) put('other-anim', x.up, x.at);
      }
    }
  }
  return [...best.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([k, v]) => `${k}@${v.at}${v.up ? '^' + v.up : ''}`);
}

/** Does this effect list make a repaint resample? Filter and backdrop-filter re-run over the content they cover. */
export const underFilter = (classes) => classes.some((c) => /^(filter|backdrop-filter|filter-anim)@/.test(c));

/**
 * One row per reading of a cell. `file(urlPath)` returns { bytes, format } for the served file or null.
 * Device pixels are CSS px times DPR, rounded as a raster would be (each side to a whole pixel).
 */
export function rowsOfCell(cell, file) {
  const out = [];
  const dpr = cell.dpr;
  for (const it of cell.items ?? []) {
    const f = file(it.url) ?? { bytes: null, format: 'missing' };
    const [nw, nh] = it.nat;
    const dw = Math.round(it.img[0] * dpr);
    const dh = Math.round(it.img[1] * dpr);
    const nat = nw * nh;
    const drawn = it.none ? 0 : dw * dh;
    const vector = f.format === 'svg';
    const classes = effectClasses(it);
    out.push({
      region: regionOf(it), kind: it.kind, prop: it.prop ?? null, url: it.url, id: it.id, fw: it.fw?.[0] ?? null, none: it.none, everInView: it.everInView,
      loading: it.loading ?? null, decoding: it.decoding ?? null, srcset: it.srcset ?? null, imageSet: it.imageSet ?? false, complete: it.complete ?? true,
      format: f.format, bytes: f.bytes, natW: nw, natH: nh, natPx: nat, boxW: it.box[0], boxH: it.box[1], cssW: it.img[0], cssH: it.img[1], fit: it.fit,
      devW: dw, devH: dh, drawnPx: drawn, decodedBytes: vector ? 0 : nat * 4, neededBytes: vector ? 0 : drawn * 4,
      waste: !vector && drawn > 0 && nat > 0 ? nat / drawn : null, wastedBytes: !vector && drawn > 0 ? Math.max(0, nat - drawn) * 4 : 0,
      visMin: it.visMin, visMax: it.visMax, effects: classes, underFilter: underFilter(classes),
    });
  }
  return out;
}

/** The served-file reader for an audit root: bytes and format by magic bytes, cached. */
export function fileReader(root, resolveUrl = (u) => u) {
  const cache = new Map();
  return (urlPath) => {
    const p = resolveUrl(urlPath.split('?')[0]);
    if (cache.has(p)) return cache.get(p);
    let v = null;
    try {
      const abs = join(root, p);
      const st = statSync(abs);
      if (st.isFile()) v = { bytes: st.size, format: sniff(readFileSync(abs).subarray(0, 600)) };
    } catch { /* missing */ }
    cache.set(p, v);
    return v;
  };
}

/** Aggregate the rows of one region in one cell by file: one entry per distinct (url, kind). Decoded bytes count once per file. */
export function aggregate(rows) {
  const by = new Map();
  for (const r of rows) {
    const k = `${r.url}|${r.kind}${r.prop ?? ''}`;
    let a = by.get(k);
    if (!a) {
      a = { ...r, count: 0, drawnCount: 0, effects: new Set(), fws: new Set() };
      by.set(k, a);
    }
    a.count++;
    if (!r.none) a.drawnCount++;
    for (const e of r.effects) a.effects.add(e);
    if (r.fw) a.fws.add(r.fw);
    // the drawn size of the file: the largest drawn instance (the file must serve it)
    if (!r.none && r.drawnPx >= a.drawnPx) Object.assign(a, { devW: r.devW, devH: r.devH, drawnPx: r.drawnPx, cssW: r.cssW, cssH: r.cssH, waste: r.waste, wastedBytes: r.wastedBytes, neededBytes: r.neededBytes, fit: r.fit });
  }
  return [...by.values()].map((a) => ({ ...a, effects: [...a.effects].sort(), fws: [...a.fws].sort() }));
}

/** Rank by wasted decoded bytes (descending), then decoded bytes, then url. */
export const rank = (list) => [...list].sort((a, b) => b.wastedBytes - a.wastedBytes || b.decodedBytes - a.decodedBytes || a.url.localeCompare(b.url));

export const mb = (n) => (n / 1048576).toFixed(2);
export const kb = (n) => (n == null ? '-' : (n / 1024).toFixed(0));
const short = (u) => u.replace(/^\/selling\//, '').replace(/^\/assets\//, 'a/');

/** Markdown of the ranked table of one region in one cell. */
export function tableMd(title, aggs, { limit = 14 } = {}) {
  const lines = [`**${title}**`, '', '| # | file | n | natural | drawn CSS | drawn device px | fmt | KB | decoded MB | waste x | effects (nearest ancestor) |', '|---|---|---|---|---|---|---|---|---|---|---|'];
  rank(aggs).slice(0, limit).forEach((a, i) => {
    lines.push(`| ${i + 1} | ${short(a.url)}${a.kind === 'bg' ? ` (${a.prop})` : ''} | ${a.drawnCount}/${a.count} | ${a.natW}x${a.natH} | ${a.drawnPx ? `${a.cssW.toFixed(0)}x${a.cssH.toFixed(0)}` : 'not drawn'} | ${a.drawnPx ? `${a.devW}x${a.devH}` : '-'} | ${a.format} | ${kb(a.bytes)} | ${mb(a.decodedBytes)} | ${a.waste ? a.waste.toFixed(1) : '-'} | ${a.effects.join(', ') || '-'} |`);
  });
  return lines.join('\n');
}

/** Totals of one region in one cell. */
export function totals(aggs) {
  const drawn = aggs.filter((a) => a.drawnCount > 0);
  const sum = (f, xs = drawn) => xs.reduce((s, a) => s + f(a), 0);
  return {
    files: aggs.length, filesDrawn: drawn.length, bytes: sum((a) => a.bytes ?? 0, aggs), bytesDrawn: sum((a) => a.bytes ?? 0),
    decoded: sum((a) => a.decodedBytes), needed: sum((a) => a.neededBytes), wasted: sum((a) => a.wastedBytes),
    underFilterDecoded: sum((a) => (underFilter(a.effects) ? a.decodedBytes : 0)),
  };
}
