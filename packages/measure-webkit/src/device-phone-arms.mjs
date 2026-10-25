// Twin of lean/Fw/Device/PhoneArms.lean (TS stand-in until the reductions run as fwcore); test/device-phone-arms.test.mjs checks every
// function against golden/device/phone-arms.jsonl. Lean decides the arms, the visit order, the blocks, when a visit may start and the
// verdict of a cell; this file maps those decisions over a visit's counts and frames files. Integer units as in device-session.mjs:
// times in hundredths of a ms, positions in tenth px, frame-interval rates in hundredths per 100 frames.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { verdict, spread, sameFlags, movingRows, stat, zoneOf, inZone, ZONES } from './device-session.mjs';
import { COUNT_TYPES } from './reduce.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
/** The constants Lean owns, read from the generated golden. */
export const PA = Object.freeze(GOLDEN.find((l) => l.kind === 'consts'));
/** The candidate arms, in Lean's order: the base, the original, then each flag alone. */
export const ARMS = Object.freeze(GOLDEN.filter((l) => l.kind === 'arm').map((l) => Object.freeze(l.arm)));
export const METRICS = PA.metrics;
const FRAME_METRICS = ['over34', 'over50'];
const COUNT_METRICS = METRICS.filter((m) => !FRAME_METRICS.includes(m));

export const samePage = (a, b) => a.target === b.target && sameFlags(a.flags, b.flags);

/** Lean `dedup`: the arms that stay; an arm that loads the same page as an earlier kept arm is dropped. */
export function dedup(xs) {
  const seen = [], out = [];
  for (const x of xs) if (!seen.some((s) => samePage(x, s))) { seen.push(x); out.push(x); }
  return out;
}
/** Each dropped arm with the kept arm it duplicates. */
export const dropped = (xs) => { const kept = dedup(xs); return xs.filter((x) => !kept.includes(x)).map((x) => ({ id: x.id, sameAs: kept.find((k) => samePage(x, k)).id })); };

export const KEPT = Object.freeze(dedup(ARMS));
export const BASE = KEPT[0];
export const OTHERS = Object.freeze(KEPT.slice(1));

/** Lean `visits`: the base, the first half of the others, the base, the rest reversed, the base (A/B/A with the base three times). */
export function visits(b, os) {
  const h = Math.floor(os.length / 2);
  return [b, ...os.slice(0, h), b, ...os.slice(h).reverse(), b];
}
/** Lean `blocks`: the list cut into pieces of at most `per`. */
export function blocks(per, l) {
  const out = [];
  for (let i = 0; i < l.length; i += per) out.push(l.slice(i, i + per));
  return out;
}
export const mayStart = (elapsedS, longestS) => elapsedS + longestS <= PA.capMin * 60;
export const coolOk = (gapS) => PA.coolMin * 60 <= gapS;
export const SESSION = Object.freeze(visits(BASE, OTHERS));
export const wallMin = (n, perBlock = PA.perBlock) => n * PA.visitMin + (Math.max(1, blocks(perBlock, SESSION).length) - 1) * PA.coolMin;

/** Lean `binZone`: the zone of a 500 px bin by its centre (vh10, maxY10 in tenth px; y0 in px). */
export const binZone = (vh10, maxY10, y0) => zoneOf(vh10, maxY10, y0 * 10 + 2500);
export const zoneSum = (vh10, maxY10, z, bins) => bins.filter((b) => binZone(vh10, maxY10, b[0]) === z).reduce((s, b) => s + b[1], 0);

export const cells = (bs, as) => bs.slice(0, Math.min(bs.length, as.length)).map((b, i) => verdict(b, as[i]));
/** Lean `labelOf`: better when a cell beats the base and none is worse, worse the other way round, mixed with both, same when no cell leaves the spread. */
export function labelOf(vs) {
  const b = vs.includes('beats'), w = vs.includes('worse');
  return b && w ? 'mixed' : b ? 'better' : w ? 'worse' : vs.includes('same') ? 'same' : 'unresolved';
}
export const armLabel = (bs, as) => labelOf(cells(bs, as));
export const table = (bs, arms) => arms.map((a) => armLabel(bs, a));

// ---- plumbing (TS stand-in; holds no decision) ---------------------------------------------------------------------------------

/** The URL search that loads an arm's page. */
export const searchOf = (arm) => (arm.flags.length === 0 ? '' : `?fw=${arm.flags.join(',')}`);

/**
 * The prerendered page each rewrite arm loads: `{id, search, hash}`; throws when a search is not prerendered. `distinct` is false when
 * two arms share a hash (the same page under two names), so the plan can name the reason an arm would be dropped.
 */
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

/** The viewport and scroll range (tenth px) of a counts file. */
export function geometry(counts) {
  const i = counts.reduced[0].info;
  return { vh10: Math.round(i.vh * 10), maxY10: Math.round(i.maxY * 10), vh: i.vh, maxY: i.maxY };
}

/** Per pass of a counts file: {zone: {metric: count}} for the count metrics, summed over the bins of each zone. */
export function countValues(counts) {
  return counts.reduced.map((p) => {
    const g = { vh10: Math.round(p.info.vh * 10), maxY10: Math.round(p.info.maxY * 10) };
    const out = {};
    for (const z of ZONES) {
      out[z] = {};
      for (const m of COUNT_METRICS) {
        const k = COUNT_TYPES.indexOf(m);
        if (k < 0) throw new Error(`count type ${m} is not recorded`);
        out[z][m] = zoneSum(g.vh10, g.maxY10, z, p.zones.map((b) => [b.y0, b.counts[k]]));
      }
    }
    return out;
  });
}

/** Per rep of a frames file: {zone: {over34, over50}} in hundredths per 100 moving frames, zoned by the viewport of the counts pass. */
export function frameValues(frames, vh10) {
  return frames.runs.map((r) => {
    const rows = movingRows(r.ts.map((t, i) => [Math.round(t * 100), Math.round(r.ys[i] * 10)]));
    const mx = Math.round(r.maxY * 10);
    const out = {};
    for (const z of ZONES) { const s = stat(inZone(vh10, mx, z, rows)); out[z] = { over34: s.per34, over50: s.per50, n: s.n }; }
    return out;
  });
}

/** One visit's values: counts per pass and frames per rep. */
export function visitValues(counts, frames) {
  const g = geometry(counts);
  return { ...g, counts: countValues(counts), frames: frameValues(frames, g.vh10) };
}

const seriesOf = (vals, z, m) => vals.map((v) => v[z][m]);

/**
 * The tables: for each arm, every (zone, metric) cell with the base series (all base visits pooled), the arm series, Lean's cell
 * verdict, and Lean's label per zone and family (counts, frames) and per family overall. `visitsDone` = [{arm, values}].
 */
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
    arms.push({ id: a.id, target: a.target, flags: a.flags, visits: pool(a.id).length, cells: rows, labels });
  }
  const baseRows = [];
  for (const z of ZONES) for (const m of METRICS) {
    const bs = series(baseId, z, m);
    baseRows.push({ zone: z, metric: m, n: bs.length, median: med(bs), min: bs.length ? Math.min(...bs) : null, max: bs.length ? Math.max(...bs) : null, spread: spread(bs) });
  }
  return { base: { id: baseId, visits: pool(baseId).length, cells: baseRows }, arms };
}

/** Anomalies of a set of visits: a viewport that differs from the first base visit's, or a visit without passes. */
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
