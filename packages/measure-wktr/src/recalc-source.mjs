const A = (kind) => ['floor', 'obs', 'obsf'].map((v) => `rs-${kind}-${v}`);
export const IDLE_ARMS = A('idle');
export const FLIP_ARMS = A('flip');
const BLOCK = ['rs-idle-blockraf', 'rs-idle-blocktimer'];
const DIAG = ['rs-idle-cancel', 'rs-idle-hide', 'rs-idle-empty'];
export const RS_ARMS = ['rs-warm', ...IDLE_ARMS, ...FLIP_ARMS, ...[...FLIP_ARMS].reverse(), ...[...IDLE_ARMS].reverse(), ...BLOCK, ...[...BLOCK].reverse(), ...DIAG];

export const C = { coverMinPct: 90, absentMinPct: 90, minQ: 10, residualMin: 75, shiftMax: 25, fellMax: 25, minValid: 2 };
export const MF = { idle: 40, flip: 12 };

export const rpf100 = (fs) => (fs.length === 0 ? 0 : Math.floor((fs.reduce((s, f) => s + f.recalcs, 0) * 100) / fs.length));
export const kindOf = (k) => k.split(':')[0];
const count = (k, fs) => fs.filter((f) => f.keys.includes(k)).length;
const sub = (a, b) => Math.max(0, a - b);

export const withRecalc = (j) => j.base.filter((f) => f.recalcs > 0);
export const withoutRecalc = (j) => j.base.filter((f) => f.recalcs === 0);
export const universe = (j) => [...new Set(j.base.flatMap((f) => f.keys))];
const covered = (j, k) => C.coverMinPct * withRecalc(j).length <= 100 * count(k, withRecalc(j));
const absent = (j, k) => C.absentMinPct * withoutRecalc(j).length <= 100 * sub(withoutRecalc(j).length, count(k, withoutRecalc(j)));
const contrast = (j) => C.minQ <= withoutRecalc(j).length;
const hasFrames = (mf, j) => mf <= j.floor.length && mf <= j.base.length;
const residual = (j) => C.residualMin <= rpf100(j.floor);
const shifted = (j) => C.shiftMax < sub(rpf100(j.base), rpf100(j.floor)) || C.shiftMax < sub(rpf100(j.floor), rpf100(j.base));
const iv = (j, kind) => j.ivs.find((x) => x.kind === kind)?.frames;
const fell = (mf, j, kind) => { const fs = iv(j, kind); return fs !== undefined && mf <= fs.length && rpf100(fs) <= C.fellMax; };
const refuted = (mf, j, kind) => { const fs = iv(j, kind); return fs !== undefined && mf <= fs.length && C.fellMax < rpf100(fs); };
export const suspects = (mf, j) => universe(j).filter((k) => covered(j, k) && !refuted(mf, j, kindOf(k)));
export const sources = (mf, j) => suspects(mf, j).filter((k) => (contrast(j) ? absent(j, k) : fell(mf, j, kindOf(k))));

export function why(mf, j) {
  if (!hasFrames(mf, j)) return 'no-frames';
  if (!residual(j)) return 'no-residual';
  if (shifted(j)) return 'observer-shift';
  const s = sources(mf, j);
  if (s.length === 1) return 'named';
  if (s.length >= 2) return 'several';
  if (suspects(mf, j).length === 0 || contrast(j)) return 'engine-internal';
  return 'no-contrast';
}
export const valid = (w) => w === 'engine-internal' || w === 'named' || w === 'several';
export const res = (mf, j) => { const w = why(mf, j); return { why: w, src: w === 'named' ? sources(mf, j)[0] : null }; };

export function overall(rs) {
  const vs = rs.filter((r) => valid(r.why));
  if (vs.length < C.minValid) return { name: 'inconclusive', next: NEXT.inconclusive };
  if (vs.every((r) => r.why === 'engine-internal')) return { name: 'engine-internal', next: NEXT.internal };
  const key = vs[0].src;
  if (vs.every((r) => r.why === 'named') && vs.every((r) => r.src === key) && key !== null) return { name: `named ${key}`, next: NEXT.named };
  return { name: 'several', next: NEXT.several };
}
const NEXT = {
  named: 'one same-look fix task for the named source',
  several: 'one intervention arm per source',
  internal: 'no page-side fix: read the WebKit invalidation path',
  inconclusive: 'rerun with contrast or more valid jobs',
};
export const emptyPm = (fs) => { const z = fs.flatMap((f) => f.sizes); return z.length === 0 ? 0 : Math.floor((z.filter((n) => n === 0).length * 1000) / z.length); };

export const expand = (runs) => runs.flatMap(({ n, f }) => Array.from({ length: n }, () => f));
export const jobOfGolden = (g) => ({ floor: expand(g.floor), base: expand(g.base), ivs: g.ivs.map((x) => ({ kind: x.kind, frames: expand(x.frames) })) });

export function armFrames(report, name) {
  const out = [];
  for (const row of report.rows) {
    if (row.arm !== name || !row.rs || !row.engaged) continue;
    const kt = row.rs.kt;
    for (const f of row.rs.frames ?? []) out.push({ recalcs: f.r, pre: f.p ?? 0, keys: (f.k ?? []).map((k) => (typeof k === 'number' && kt ? kt[k] : k)), sizes: f.z ?? [] });
  }
  return out;
}

export function jobOf(report, kind) {
  const n = (v) => `rs-${kind}-${v}`;
  return {
    floor: armFrames(report, n('floor')),
    base: armFrames(report, n('obs')),
    ivs: kind === 'idle' ? [{ kind: 'raf', frames: armFrames(report, 'rs-idle-blockraf') }, { kind: 'timer', frames: armFrames(report, 'rs-idle-blocktimer') }] : [],
  };
}

export function recalcTally(report) {
  const lines = [];
  const names = [...new Set(report.rows.filter((r) => r.rs).map((r) => r.arm))];
  for (const name of names) {
    const fs = armFrames(report, name);
    const sz = fs.flatMap((f) => f.sizes);
    lines.push(`${name}: frames ${fs.length} rpf100 ${rpf100(fs)} pre-callback rpf100 ${fs.length === 0 ? 0 : Math.floor((fs.reduce((t, f) => t + (f.pre ?? 0), 0) * 100) / fs.length)} readable sizes ${sz.length} empty ${emptyPm([{ sizes: sz }])}pm`);
  }
  for (const kind of ['idle', 'flip']) {
    const j = jobOf(report, kind);
    const mf = MF[kind];
    const r = res(mf, j);
    lines.push(`${kind}: floor ${j.floor.length}f rpf ${rpf100(j.floor)} base ${j.base.length}f rpf ${rpf100(j.base)} recalc-frames ${withRecalc(j).length} quiet-frames ${withoutRecalc(j).length} iv ${j.ivs.map((x) => `${x.kind} ${x.frames.length}f rpf ${rpf100(x.frames)}`).join(', ') || '-'}`);
    lines.push(`${kind}: suspects ${JSON.stringify(suspects(mf, j))} sources ${JSON.stringify(sources(mf, j))} why ${r.why} src ${r.src}`);
  }
  return lines;
}
