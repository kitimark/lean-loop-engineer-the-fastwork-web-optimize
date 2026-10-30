import { overallNames } from './end-wktr.mjs';
import { MIN_FRAMES, PROBE_BAND } from './end-floor-probe.mjs';

// Port of lean/Fw/Device/EndFloorDirty.lean; the golden pins it (test/end-floor-dirty.test.mjs).
export const FLOOR_BAND = PROBE_BAND;
export const CARRIER_SHARE = 90;
export const DOCUMENT_SHARE = 90;
export const SKIP_FRAMES = 8;
export { MIN_FRAMES };

export const ARMS_D = [
  'rs-flip-pbpoff', 'rs-flip-pbdn', 'rs-flip-pbpd', 'rs-flip-pbpdt', 'rs-idle-pbpd', 'rs-flip-pbpft', 'rs-flip-pbpfh',
  'rs-flip-pbphide', 'rs-flip-pbphidep', 'rs-flip-pbpd', 'rs-flip-pbpoff',
];
export const HIDE_KEYS = ['flip-pbphide', 'flip-pbphidep'];
export const FLUSH_KEYS = ['flip-pbpft', 'flip-pbpfh'];
const KEY = /^rs-(flip|idle)-(pbpoff|pbdn|pbpdt|pbpd|pbpft|pbpfh|pbphidep|pbphide)$/;

const sum = (xs) => xs.reduce((a, b) => a + b, 0);
const cp = (s) => Array.from(s).map((c) => c.codePointAt(0));
const lessStr = (a, b) => {
  const x = cp(a);
  const y = cp(b);
  for (let i = 0; i < x.length && i < y.length; i++) if (x[i] !== y[i]) return x[i] < y[i];
  return x.length < y.length;
};
const dedup = (xs) => [...new Set(xs)];

export function pair(prev, frames) {
  const out = [];
  let p = prev;
  for (const f of frames) {
    out.push([f.r, dedup(p.filter((n) => !f.h.includes(n)))]);
    p = f.e;
  }
  return out;
}
export const repSets = (frames) => pair([], frames).slice(SKIP_FRAMES);
export const armSets = (reps) => reps.flatMap(repSets);

export const hitN = (xs) => xs.filter(([r]) => r > 0).length;
export const bareN = (xs) => xs.filter(([r, s]) => r > 0 && s.length === 0).length;
export const countName = (n, xs) => xs.filter(([r, s]) => r > 0 && s.includes(n)).length;
export const recalcN = (xs) => sum(xs.map(([r]) => r));
export const rate = (xs) => (xs.length === 0 ? 0 : Math.floor((recalcN(xs) * 100) / xs.length));
export const names = (xs) => dedup(xs.flatMap(([, s]) => s));
const better = (xs, a, b) => countName(b, xs) < countName(a, xs) || (countName(a, xs) === countName(b, xs) && lessStr(a, b));
export function top(xs) {
  let acc = null;
  for (const n of names(xs)) if (acc === null || better(xs, n, acc)) acc = n;
  return acc;
}

export const dName = (d) => (d.kind === 'carrier' ? `carrier ${d.name}` : d.kind);

export function verdict(xs) {
  if (xs.length < MIN_FRAMES) return { kind: 'unread', name: null };
  if (rate(xs) <= FLOOR_BAND) return { kind: 'noFloor', name: null };
  if (DOCUMENT_SHARE * hitN(xs) <= 100 * bareN(xs)) return { kind: 'documentLevel', name: null };
  const t = top(xs);
  if (t !== null && CARRIER_SHARE * hitN(xs) <= 100 * countName(t, xs)) return { kind: 'carrier', name: t };
  return { kind: 'spread', name: null };
}

export const overall = (ds) => overallNames(ds.filter((d) => d.kind !== 'unread').map(dName));

export const readingRate = (x) => (x.frames === 0 ? 0 : Math.floor((x.recalcs * 100) / x.frames));
export function hideVerdict(carrier, hidden, ref, hide) {
  if (ref.frames < MIN_FRAMES || hide.frames < MIN_FRAMES) return 'unread';
  if (hidden !== carrier) return 'unmatched';
  if (readingRate(ref) <= FLOOR_BAND) return 'noReference';
  return readingRate(hide) <= FLOOR_BAND ? 'confirmed' : 'notConfirmed';
}

// flushVerdict: `auto` are the recalcs of the rendering updates, `flush` those of the forced getComputedStyle flush.
export function flushVerdict(x) {
  if (x.frames < MIN_FRAMES) return 'unread';
  const a = FLOOR_BAND < Math.floor((x.auto * 100) / x.frames);
  const f = FLOOR_BAND < Math.floor((x.flush * 100) / x.frames);
  return a && f ? 'both' : f ? 'held' : a ? 'arises' : 'none';
}
export const flushOverall = (fs) => overallNames(fs.filter((f) => f !== 'unread'));
export const hideOverall = (hs) => overallNames(hs.filter((h) => h !== 'unread'));

// Page rows. A rep is [r, pre, hIds, eIds, timelineInvalidations, traversals, lastStyleUpdateSize, (hTypes, eTypes)]; ids index row.rs.kt.
export function rowsByKey(rep) {
  const seen = new Map();
  const out = new Map();
  for (const row of rep.rows ?? []) {
    const m = KEY.exec(row.arm);
    if (!m || !row.rs) continue;
    const base = `${m[1]}-${m[2]}`;
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    out.set(n === 1 ? base : `${base}#${n}`, row);
  }
  return out;
}

export const framesOfRep = (kt, fr) => fr.map((f) => ({ r: f[0], h: f[2].map((i) => kt[i]), e: f[3].map((i) => kt[i]) }));
export const repsOf = (row) => (row?.rs?.dn ?? []).map((w) => framesOfRep(row.rs.kt ?? [], w.f));
export const setsOf = (row) => armSets(repsOf(row));

export function readingOf(row) {
  const pb = row?.rs?.pb ?? [];
  return { frames: sum(pb.map((t) => t.n)), recalcs: sum(pb.map((t) => t.r)), ru: sum(pb.map((t) => t.u ?? 0)), ms: sum(pb.map((t) => t.w ?? 0)) };
}

// Frames after the skipped leading ones of each rep: the frames the verdicts read.
const skipped = (dn) => dn.flatMap((w) => w.f.slice(SKIP_FRAMES));
const per100 = (x, n) => (n === 0 ? 0 : Math.round((x * 100) / n));

export function factsOf(row) {
  const dn = row?.rs?.dn ?? [];
  const fs = dn.flatMap((w) => w.f);
  const tally = new Map();
  for (const f of fs) {
    const ty = Array.isArray(f[7]) ? f.slice(7) : [];
    if (ty.length === 0) continue;
    for (let k = 0; k < 2; k++) f[2 + k].forEach((id, j) => {
      const nm = (row.rs.kt ?? [])[id];
      const t = ty[k][j];
      if (nm === undefined || t === undefined) return;
      const key = `${nm} ${t}`;
      tally.set(key, (tally.get(key) ?? 0) + 1);
    });
  }
  const ag = dn.map((w) => w.ag).filter(Boolean);
  const agSum = (k) => sum(ag.map((a) => a[k] ?? 0));
  const mu = new Map();
  for (const w of dn) for (const [k, c] of w.mu ?? []) mu.set(k, (mu.get(k) ?? 0) + c);
  const flushed = fs.filter((f) => typeof f[7] === 'number');
  return {
    flush: flushed.length === 0 ? null : { frames: skipped(dn).length, auto: sum(skipped(dn).map((f) => f[0])), flush: sum(skipped(dn).map((f) => f[7])) },
    dirt: { h: per100(agSum('h'), fs.length), e: per100(agSum('e'), fs.length), hEl: per100(agSum('hEl'), fs.length), eEl: per100(agSum('eEl'), fs.length), cyc: per100(agSum('cyc'), fs.length), maxH: ag.length === 0 ? 0 : Math.max(...ag.map((a) => a.maxH ?? 0)), maxE: ag.length === 0 ? 0 : Math.max(...ag.map((a) => a.maxE ?? 0)) },
    mut: [...mu.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).slice(0, 8),
    frames: fs.length,
    timeline: per100(sum(fs.map((f) => f[4])), fs.length),
    traversal: per100(sum(fs.map((f) => f[5])), fs.length),
    styleSize: fs.length === 0 ? 0 : Math.max(...fs.map((f) => f[6])),
    nodes: dn.length === 0 ? 0 : Math.max(...dn.map((w) => w.nodes)),
    capped: sum(dn.map((w) => w.caps)),
    walkMs: per100(readingOf(row).ms, readingOf(row).frames) / 100,
    pre: sum(fs.map((f) => f[1])),
    types: [...tally.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).slice(0, 6),
  };
}

export function decideDirtyJob(rep) {
  const rows = rowsByKey(rep);
  const arms = [];
  for (const [key, row] of rows) {
    const xs = setsOf(row);
    const hit = hitN(xs);
    const t = top(xs);
    arms.push({ key, row, sets: xs.length, rate: rate(xs), hit, bare: bareN(xs), top: t, topN: t === null ? 0 : countName(t, xs), v: verdict(xs), reading: readingOf(row), hid: row.rs.hid ?? null, facts: factsOf(row), flush: null });
    const last = arms[arms.length - 1];
    last.flush = last.facts.flush === null ? null : flushVerdict(last.facts.flush);
  }
  const ref = arms.find((a) => a.key === 'flip-pbpd') ?? null;
  const hides = ref === null ? [] : arms.filter((a) => HIDE_KEYS.includes(a.key)).map((a) => ({
    key: a.key,
    hid: a.hid,
    ref: ref.reading,
    hide: a.reading,
    v: ref.v.kind === 'carrier' ? hideVerdict(ref.v.name, a.hid, ref.reading, a.reading) : null,
  }));
  return { arms, hides, ref };
}

const rd = (x) => `frames ${x.frames} recalcs ${x.recalcs} rate ${readingRate(x)} per 100 rAF callbacks`;

export function jobLinesD(label, rep) {
  const d = decideDirtyJob(rep);
  const lines = [];
  for (const a of d.arms) {
    lines.push(`end-floor-dirty ${label} ${a.key}: ${rd(a.reading)}, read frames ${a.sets} rate ${a.rate}, recalc frames ${a.hit} of which no dirty name ${a.bare}, top ${a.top ?? '-'} in ${a.topN} recalc frames, verdict ${dName(a.v)}`);
    const f = a.facts;
    if (f.flush !== null) lines.push(`end-floor-dirty-flush ${label} ${a.key}: frames ${f.flush.frames} update recalcs ${f.flush.auto} flush recalcs ${f.flush.flush}, verdict ${flushVerdict(f.flush)}`);
    lines.push(`end-floor-dirty-dirt ${label} ${a.key}: dirty nodes per sample at rAF start ${f.dirt.h / 100} (elements ${f.dirt.hEl / 100}, max ${f.dirt.maxH}), after the update ${f.dirt.e / 100} (elements ${f.dirt.eEl / 100}, max ${f.dirt.maxE}), cycling names per frame ${f.dirt.cyc / 100}${f.mut.length === 0 ? '' : `, mutations ${f.mut.map(([k, n]) => `${k} x${n}`).join('; ')}`}`);
    lines.push(`end-floor-dirty-facts ${label} ${a.key}: timeline invalidations per 100 frames ${f.timeline}, style invalidation traversals per 100 frames ${f.traversal}, largest last style update ${f.styleSize}, nodes walked ${f.nodes}, capped windows ${f.capped}, walk ms per frame ${f.walkMs}, recalcs before the rAF callback ${f.pre}${f.types.length === 0 ? '' : `, change types ${f.types.map(([k, n]) => `${k} x${n}`).join('; ')}`}`);
  }
  for (const h of d.hides) lines.push(`end-floor-dirty-hide ${label} ${h.key}: hid ${h.hid ?? '-'}, reference ${rd(h.ref)}, hidden ${rd(h.hide)}, verdict ${h.v ?? 'noCarrier'}`);
  return { lines, d };
}

export function overallLinesD(ds) {
  const lines = [];
  const keys = [...new Set(ds.flatMap((d) => d.arms.map((a) => a.key)))];
  for (const k of keys) {
    const vs = ds.map((d) => d.arms.find((a) => a.key === k)?.v ?? { kind: 'unread', name: null });
    lines.push(`end-floor-dirty overall ${k}: ${overall(vs)} (jobs ${vs.map(dName).join(' | ')})`);
  }
  for (const k of FLUSH_KEYS) {
    const fs = ds.map((d) => d.arms.find((a) => a.key === k)?.flush ?? 'unread');
    if (fs.every((f) => f === 'unread')) continue;
    lines.push(`end-floor-dirty-flush overall ${k}: ${flushOverall(fs)} (jobs ${fs.join(' ')})`);
  }
  for (const k of HIDE_KEYS) {
    const hs = ds.map((d) => d.hides.find((h) => h.key === k)?.v ?? 'unread');
    if (hs.every((h) => h === 'unread')) continue;
    lines.push(`end-floor-dirty-hide overall ${k}: ${hideOverall(hs)} (jobs ${hs.join(' ')})`);
  }
  return lines;
}

export function rowLineD(job, file, i, row, occurrence) {
  const x = readingOf(row);
  const dn = row.rs?.dn ?? [];
  return `${job} ${file} rows[${i}] ${row.arm}${occurrence > 1 ? `#${occurrence}` : ''}: ${rd(x)}, reps ${row.rs?.reps ?? 0}, dirty windows ${dn.length}, hid ${row.rs?.hid ?? '-'}`;
}
