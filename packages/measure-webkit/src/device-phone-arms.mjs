import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { verdict, spread, sameFlags, movingRows, stat, zoneOf, inZone, ZONES } from './device-session.mjs';
import { COUNT_TYPES } from './reduce.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const PA = Object.freeze(GOLDEN.find((l) => l.kind === 'consts'));
export const ARMS = Object.freeze(GOLDEN.filter((l) => l.kind === 'arm').map((l) => Object.freeze(l.arm)));
export const METRICS = PA.metrics;
const FRAME_METRICS = ['over34', 'over50'];
const COUNT_METRICS = METRICS.filter((m) => !FRAME_METRICS.includes(m));

export const samePage = (a, b) => a.target === b.target && sameFlags(a.flags, b.flags);

export function dedup(xs) {
  const seen = [], out = [];
  for (const x of xs) if (!seen.some((s) => samePage(x, s))) { seen.push(x); out.push(x); }
  return out;
}
export const dropped = (xs) => { const kept = dedup(xs); return xs.filter((x) => !kept.includes(x)).map((x) => ({ id: x.id, sameAs: kept.find((k) => samePage(x, k)).id })); };

export const KEPT = Object.freeze(dedup(ARMS));
export const BASE = KEPT[0];
export const OTHERS = Object.freeze(KEPT.slice(1));

export function visits(b, os) {
  const h = Math.floor(os.length / 2);
  return [b, ...os.slice(0, h), b, ...os.slice(h).reverse(), b];
}
export function blocks(per, l) {
  const out = [];
  for (let i = 0; i < l.length; i += per) out.push(l.slice(i, i + per));
  return out;
}
export const mayStart = (elapsedS, longestS) => elapsedS + longestS <= PA.capMin * 60;
export const coolOk = (gapS) => PA.coolMin * 60 <= gapS;
export const SESSION = Object.freeze(visits(BASE, OTHERS));
/** The session of the base visited around only the named other arms (same order as visits(BASE, OTHERS)). */
export function sessionOf(onlyIds) {
  const known = OTHERS.map((a) => a.id);
  const bad = onlyIds.filter((id) => !known.includes(id));
  if (bad.length > 0 || onlyIds.length === 0) throw new Error(`--only needs kept arm ids from [${known.join(' | ')}]; got [${onlyIds.join(' | ')}]`);
  return Object.freeze(visits(BASE, OTHERS.filter((a) => onlyIds.includes(a.id))));
}
export const wallMin = (n, perBlock = PA.perBlock) => n * PA.visitMin + (Math.max(1, Math.ceil(n / perBlock)) - 1) * PA.coolMin;

export const binZone = (vh10, maxY10, y0) => zoneOf(vh10, maxY10, y0 * 10 + 2500);
export const zoneSum = (vh10, maxY10, z, bins) => bins.filter((b) => binZone(vh10, maxY10, b[0]) === z).reduce((s, b) => s + b[1], 0);

export const cells = (bs, as) => bs.slice(0, Math.min(bs.length, as.length)).map((b, i) => verdict(b, as[i]));
export function labelOf(vs) {
  const b = vs.includes('beats'), w = vs.includes('worse');
  return b && w ? 'mixed' : b ? 'better' : w ? 'worse' : vs.includes('same') ? 'same' : 'unresolved';
}
export const armLabel = (bs, as) => labelOf(cells(bs, as));
export const table = (bs, arms) => arms.map((a) => armLabel(bs, a));

export const searchOf = (arm) => (arm.flags.length === 0 ? '' : `?fw=${arm.flags.join(',')}`);

export function pagesOf(distDir, arms = KEPT) {
  const cfg = JSON.parse(readFileSync(join(distDir, 'configs.json'), 'utf8'));
  const rows = arms.map((a) => {
    const search = searchOf(a);
    const hash = a.target === 'original' ? 'snapshot' : cfg.bySearch[canonSearch(search)];
    if (!hash) throw new Error(`arm ${a.id}: search "${search}" is not prerendered`);
    return { id: a.id, target: a.target, search, hash };
  });
  const dup = rows.filter((r, i) => rows.findIndex((s) => s.hash === r.hash) !== i).map((r) => ({ id: r.id, sameAs: rows.find((s) => s.hash === r.hash).id }));
  return { rows, dup, distinct: dup.length === 0 };
}

const sum0 = (l) => l.reduce((s, v) => s + v, 0);
const med = (l) => { const s = [...l].sort((a, b) => a - b); return s.length === 0 ? null : s[Math.floor(s.length / 2)]; };

export function geometry(counts) {
  const i = counts.reduced[0].info;
  return { vh10: Math.round(i.vh * 10), maxY10: Math.round(i.maxY * 10), vh: i.vh, maxY: i.maxY };
}

export function countValues(counts) {
  return counts.reduced.map((p) => {
    const g = { vh10: Math.round(p.info.vh * 10), maxY10: Math.round(p.info.maxY * 10) };
    const out = {};
    for (const z of ZONES) {
      out[z] = {};
      for (const m of COUNT_METRICS) {
        const k = COUNT_TYPES.indexOf(m);
        if (k < 0 && m !== 'paintArea') throw new Error(`count type ${m} is not recorded`);
        out[z][m] = zoneSum(g.vh10, g.maxY10, z, p.zones.map((b) => [b.y0, m === 'paintArea' ? b.paintArea : b.counts[k]]));
      }
    }
    return out;
  });
}

export function frameValues(frames, vh10) {
  return frames.runs.map((r) => {
    const rows = movingRows(r.ts.map((t, i) => [Math.round(t * 100), Math.round(r.ys[i] * 10)]));
    const mx = Math.round(r.maxY * 10);
    const out = {};
    for (const z of ZONES) { const s = stat(inZone(vh10, mx, z, rows)); out[z] = { over34: s.per34, over50: s.per50, n: s.n }; }
    return out;
  });
}

export function censusValues(counts) {
  return counts.reduced.map((p) => (p.census ?? []).map((c) => ({ y: c.requestedY, layers: c.layerCount, bytes: c.memoryBytes })));
}

export function visitValues(counts, frames) {
  const g = geometry(counts);
  return { ...g, counts: countValues(counts), census: censusValues(counts), frames: frameValues(frames, g.vh10) };
}

const seriesOf = (vals, z, m) => vals.map((v) => v[z][m]);

const censusSeries = (vv, k, field) => vv.flatMap((v) => v.census.map((pass) => pass[k]?.[field]).filter((x) => x !== undefined));
const censusStates = (vv) => Math.max(0, ...vv.flatMap((v) => v.census.map((pass) => pass.length)));
export function censusBase(baseVisits) {
  return Array.from({ length: censusStates(baseVisits) }, (_, k) => {
    const L = censusSeries(baseVisits, k, 'layers'), B = censusSeries(baseVisits, k, 'bytes');
    const y = baseVisits.flatMap((v) => v.census.map((pass) => pass[k]?.y)).find((q) => q !== undefined);
    return { state: k, y, layers: { median: med(L), min: Math.min(...L), max: Math.max(...L), spread: spread(L) }, bytes: { median: med(B), min: Math.min(...B), max: Math.max(...B), spread: spread(B) } };
  });
}
export function censusCells(baseVisits, armVisits) {
  return Array.from({ length: censusStates(baseVisits) }, (_, k) => {
    const row = (field) => { const bs = censusSeries(baseVisits, k, field), as = censusSeries(armVisits, k, field); return { arm: as, base: bs, verdict: cells([bs], [as])[0] ?? 'unresolved' }; };
    return { state: k, layers: row('layers'), bytes: row('bytes') };
  });
}

export function reduceSession(visitsDone) {
  const by = new Map();
  for (const v of visitsDone) { if (!by.has(v.arm)) by.set(v.arm, []); by.get(v.arm).push(v.values); }
  const pool = (id) => (by.get(id) ?? []);
  const series = (id, z, m) => {
    const fam = FRAME_METRICS.includes(m) ? 'frames' : 'counts';
    return pool(id).flatMap((vv) => seriesOf(vv[fam], z, m));
  };
  const baseId = BASE.id;
  const arms = [];
  for (const a of KEPT) {
    if (a.id === baseId) continue;
    const rows = [];
    for (const z of ZONES) for (const m of METRICS) {
      const bs = series(baseId, z, m), as = series(a.id, z, m);
      rows.push({ zone: z, metric: m, base: bs, arm: as, spread: spread(bs), verdict: cells([bs], [as])[0] ?? 'unresolved' });
    }
    const labelFor = (pred) => labelOf(rows.filter(pred).map((r) => r.verdict));
    const fam = (m) => (FRAME_METRICS.includes(m) ? 'frames' : 'counts');
    const labels = {};
    for (const f of ['counts', 'frames']) {
      labels[f] = { all: labelFor((r) => fam(r.metric) === f) };
      for (const z of ZONES) labels[f][z] = labelFor((r) => fam(r.metric) === f && r.zone === z);
    }
    arms.push({ id: a.id, target: a.target, flags: a.flags, visits: pool(a.id).length, cells: rows, labels, census: censusCells(pool(baseId), pool(a.id)) });
  }
  const baseRows = [];
  for (const z of ZONES) for (const m of METRICS) {
    const bs = series(baseId, z, m);
    baseRows.push({ zone: z, metric: m, n: bs.length, median: med(bs), min: bs.length ? Math.min(...bs) : null, max: bs.length ? Math.max(...bs) : null, spread: spread(bs) });
  }
  return { base: { id: baseId, visits: pool(baseId).length, cells: baseRows, census: censusBase(pool(baseId)) }, arms };
}

export function anomalies(visitsDone) {
  const out = [];
  const ref = visitsDone.find((v) => v.arm === BASE.id)?.values;
  for (const v of visitsDone) {
    if (ref && v.values.vh !== ref.vh) out.push(`${v.arm}: viewport ${v.values.vh} px differs from the base's ${ref.vh}`);
    if (v.values.counts.length < PA.passes) out.push(`${v.arm}: ${v.values.counts.length} counts passes of ${PA.passes}`);
    if (v.values.frames.length < PA.reps) out.push(`${v.arm}: ${v.values.frames.length} frame reps of ${PA.reps}`);
  }
  return out;
}

export const familyOf = (metric) => (FRAME_METRICS.includes(metric) ? 'frames' : 'counts');
export { ZONES, sum0 };
