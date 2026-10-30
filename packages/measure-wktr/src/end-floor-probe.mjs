import { overallNames, rpf100 } from './end-wktr.mjs';
import { PIN_N, MIN_REPS, tickOf, armVerdict, repClass, overall as overallClass } from './end-floor-window.mjs';

export const PROBE_BAND = 10;
export const MIN_FRAMES = PIN_N * MIN_REPS;

export const V = { causes: 'probeCauses', partial: 'probePartial', innocent: 'probeInnocent', noFloor: 'noFloor', unread: 'unread' };

export const rate = (x) => (x.frames === 0 ? 0 : Math.floor((x.recalcs * 100) / x.frames));

export function readable(on, off) {
  const unequal = on.src === 'raf' && off.src === 'raf' && on.frames !== off.frames;
  return MIN_FRAMES <= on.frames && MIN_FRAMES <= off.frames && !unequal;
}

export function verdict(on, off) {
  if (!readable(on, off)) return V.unread;
  if (rate(on) <= PROBE_BAND) return V.noFloor;
  if (rate(off) <= PROBE_BAND) return V.causes;
  if (rate(off) + PROBE_BAND < rate(on)) return V.partial;
  return V.innocent;
}

export const overall = (vs) => overallNames(vs.filter((v) => v !== V.unread));

export const CV = { all: 'all cancelled', some: 'some cancelled', none: 'none cancelled', unread: 'unread' };

export function cancelFrame(seen) {
  for (let i = 0; i < seen.length; i++) if (seen[i].made > 0 && seen[i].idle === seen[i].made) return i;
  return null;
}

export function cancelVerdict(cs) {
  if (cs.length < MIN_REPS) return CV.unread;
  if (cs.every((c) => c !== null)) return CV.all;
  return cs.some((c) => c !== null) ? CV.some : CV.none;
}

export function cancelSpan(cs) {
  const vs = cs.filter((c) => c !== null);
  return vs.length === 0 ? null : [Math.min(...vs), Math.max(...vs)];
}

export const ARMS = [
  'rs-flip-nat', 'rs-flip-pbon', 'rs-flip-pboff', 'rs-flip-pbconly', 'rs-flip-pbnotk', 'rs-flip-pbnoph', 'rs-flip-pbnogh', 'rs-flip-pbnomc',
  'rs-flip-pbnoraf', 'rs-flip-pbpon', 'rs-flip-pbpoff', 'rs-flip-pbcre', 'rs-flip-pbon', 'rs-flip-pboff',
];
export const PAIRS = [
  ['primary', 'pbon', 'pboff'], ['repeat', 'pbon#2', 'pboff#2'], ['group counter only', 'pbon', 'pbconly'], ['group tick probe', 'pbon', 'pbnotk'],
  ['group phase read', 'pbon', 'pbnoph'], ['group glint clock', 'pbon', 'pbnogh'], ['group message hop', 'pbon', 'pbnomc'],
  ['no harness rAF', 'pbon', 'pbnoraf'], ['paused page', 'pbpon', 'pbpoff'],
];

const sum = (xs) => xs.reduce((a, b) => a + b, 0);

export function rowsByName(rep) {
  const seen = new Map();
  const out = new Map();
  for (const row of rep.rows ?? []) {
    const m = /^rs-flip-(.*)$/.exec(row.arm);
    if (!m || !row.rs) continue;
    const n = (seen.get(m[1]) ?? 0) + 1;
    seen.set(m[1], n);
    out.set(n === 1 ? m[1] : `${m[1]}#${n}`, row);
  }
  return out;
}

export function readingOf(row) {
  const pb = row?.rs?.pb ?? [];
  if (pb.length === 0) return { frames: 0, recalcs: 0, src: 'raf', reps: 0, ru: 0 };
  return { frames: sum(pb.map((t) => t.n)), recalcs: sum(pb.map((t) => t.r)), src: pb[0].src, reps: pb.length, ru: sum(pb.map((t) => t.u ?? 0)) };
}

export function seenOf(sample) { return { made: sample[1], idle: sample[5] }; }

export function creReps(row) { return (row?.rs?.cre ?? []).filter((c) => Array.isArray(c)); }

export function creFacts(row) {
  const reps = creReps(row);
  const cancels = reps.map((r) => cancelFrame(r.map(seenOf)));
  const ticks = reps.map((r) => r.map((s) => tickOf([s[11], s[7], s[8], s[9]])));
  const at = cancels.map((c, i) => (c === null ? null : reps[i][c][0]));
  const untilCancel = reps.map((r, i) => sum(r.slice(0, cancels[i] ?? r.length).map((s) => s[11])));
  const afterCancel = reps.map((r, i) => (cancels[i] === null ? [] : r.slice(cancels[i]).map((s) => s[11])));
  return {
    reps: reps.length,
    cancels,
    ms: at,
    verdict: cancelVerdict(cancels),
    span: cancelSpan(cancels),
    spanMs: cancelSpan(at),
    klass: armVerdict(ticks),
    classes: ticks.map(repClass),
    made0: reps.map((r) => r[0][1]),
    idle0: reps.map((r) => r[0][5]),
    pending0: reps.map((r) => r[0][6]),
    running0: reps.map((r) => r[0][2]),
    samples: reps.map((r) => r.length),
    untilCancel,
    afterRate: rpf100(afterCancel.flat()),
    afterFrames: afterCancel.flat().length,
  };
}

const span = (xs) => (xs.length === 0 ? '-' : `${Math.min(...xs)} to ${Math.max(...xs)}`);
const spanOf = (x) => (x === null ? 'none' : `${x[0]} to ${x[1]}`);

export function creText(f) {
  return [
    `reps ${f.reps},`,
    `tracks made at sample 0 ${span(f.made0)},`,
    `running ${span(f.running0)} pending ${span(f.pending0)} idle ${span(f.idle0)} at sample 0,`,
    `cancel sample ${spanOf(f.span)} (frames from creation),`,
    `cancel ms ${spanOf(f.spanMs)},`,
    `cancel ${f.verdict},`,
    `samples per rep ${span(f.samples)},`,
    `recalcs until cancel per rep ${span(f.untilCancel)},`,
    `recalcs per 100 frames after cancel ${f.afterRate} over ${f.afterFrames} frames,`,
    `tick class ${f.klass},`,
    `rep classes ${f.classes.length === 0 ? '-' : [...new Set(f.classes)].sort().join(' ')}`,
  ].join(' ');
}

const readText = (name, x) => `${name} frames ${x.frames} recalcs ${x.recalcs} rate ${rate(x)} per 100 ${x.src === 'raf' ? 'rAF callbacks' : 'rendering updates'}`;

export function decideProbeJob(rep) {
  const rows = rowsByName(rep);
  const pairs = PAIRS.map(([name, onK, offK]) => {
    const on = rows.get(onK);
    const off = rows.get(offK);
    const ro = readingOf(on);
    const rf = readingOf(off);
    return { name, onK, offK, on: ro, off: rf, v: verdict(ro, rf) };
  });
  const cre = rows.has('pbcre') ? creFacts(rows.get('pbcre')) : null;
  const nat = rows.has('nat') ? readingOf(rows.get('nat')) : null;
  return { pairs, cre, rows, nat };
}

export function jobLinesP(label, rep) {
  const d = decideProbeJob(rep);
  const lines = d.pairs.map((p) => `end-floor-probe ${label} ${p.name}: on ${readText(p.onK, p.on)}, off ${readText(p.offK, p.off)}, verdict ${p.v}`);
  if (d.cre) lines.push(`end-floor-cre ${label}: ${creText(d.cre)}`);
  return { lines, d };
}

export function overallLinesP(ds) {
  const lines = [];
  const names = [...new Set(ds.flatMap((d) => d.pairs.map((p) => p.name)))];
  for (const n of names) {
    const vs = ds.map((d) => d.pairs.find((p) => p.name === n)?.v ?? V.unread);
    lines.push(`end-floor-probe overall ${n}: ${overall(vs)} (jobs ${vs.join(' ')})`);
  }
  const cs = ds.filter((d) => d.cre);
  if (cs.length > 0) {
    lines.push(`end-floor-cre overall cancel: ${overallClass(cs.map((d) => d.cre.verdict))} (jobs ${cs.map((d) => d.cre.verdict).join(' | ')})`);
    lines.push(`end-floor-cre overall tick class: ${overallClass(cs.map((d) => d.cre.klass))} (jobs ${cs.map((d) => d.cre.klass).join(' ')})`);
  }
  return lines;
}

export function rowLineP(job, file, i, row, occurrence) {
  const head = `${job} ${file} rows[${i}] ${row.arm}${occurrence > 1 ? `#${occurrence}` : ''}:`;
  if (Array.isArray(row.rs?.cre)) return `${head} ${creText(creFacts(row))}`;
  const x = readingOf(row);
  if (x.reps === 0) {
    const fs = row.rs?.frames ?? [];
    return `${head} legacy probe, frames ${fs.length}, recalcs ${sum(fs.map((f) => f.r))}, rate ${fs.length === 0 ? '-' : rpf100(fs.map((f) => f.r))} per 100 frames, reps ${row.rs?.reps ?? 0}`;
  }
  const fs = row.rs.frames ?? [];
  const pb = row.rs.pb;
  const perFrame = fs.length === 0 ? '' : `, per-frame r sum ${sum(fs.map((f) => f.r))} (r=0 ${fs.filter((f) => f.r === 0).length}, r=1 ${fs.filter((f) => f.r === 1).length}, r>=2 ${fs.filter((f) => f.r >= 2).length})`;
  return `${head} ${readText('window', x)}, reps ${x.reps}, window frames ${span(pb.map((t) => t.n))}, rendering updates ${x.ru}, window ms ${span(pb.map((t) => t.ms))}${perFrame}`;
}
