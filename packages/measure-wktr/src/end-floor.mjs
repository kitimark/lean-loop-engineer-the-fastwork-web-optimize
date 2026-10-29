import { EW, rpf100, spreadOf, overallNames } from './end-wktr.mjs';

export const WRITERS = ['style', 'data', 'pub', 'cls', 'panel', 'plat'];
export const ARM_OF = { style: 'qstyle', data: 'qdata', pub: 'qpub', cls: 'qclass', panel: 'qpanel', plat: 'qplat', write: 'qwrite' };
export const KEYS = {
  style: ['nav#style'],
  data: ['nav#data-fw-morph'],
  pub: ['nav#style', 'nav#data-fw-morph'],
  cls: ['nav#class', 'nav-earn#aria-hidden', 'nav-earn#tabindex'],
  panel: ['morph-panel#aria-hidden', 'morph-panel#data-expanded', 'morph-panel#data-start-selling-scene', 'morph-panel#tabindex'],
  plat: ['platform#style'],
};
KEYS.write = [...KEYS.pub, ...KEYS.cls, ...KEYS.panel, ...KEYS.plat];

export const QSETS = Object.fromEntries(Object.entries(ARM_OF).map(([w, arm]) => [arm, KEYS[w]]));

export const FLOOR_ARMS = [
  'rs-flip-nat', 'rs-flip-pall', ...WRITERS.map((w) => `rs-flip-${ARM_OF[w]}`), 'rs-flip-qwrite', 'rs-flip-pall',
];
export const FLOOR_OPTS = { rsIdleMs: 5000, rsReps: 16, gh: true, gk: true, lay: false };

export const W = { unread: 'unread', leaked: 'leaked', noWrites: 'no writes', carries: 'carries', raises: 'raises', noEffect: 'no effect' };

const sum = (xs) => xs.reduce((a, b) => a + b, 0);
export const rate = (fs) => rpf100(fs.map((f) => f.r));
export const leaks = (muted, fs) => fs.filter((f) => f.keys.some((k) => muted.includes(k))).length;

export const cellNums = (c) => ({
  np: sum(c.pall.map((a) => a.length)),
  na: c.all.length,
  nv: c.var.length,
  p: rate(c.pall.flat()),
  a: rate(c.all),
  s: rate(c.var),
  spread: spreadOf(c.pall.map(rate)),
  leakV: leaks(c.muted, c.var),
  leakA: leaks(KEYS.write, c.all),
});
export const gap = (x) => Math.max(0, x.p - x.a);
export const band = (x) => Math.max(Math.floor(gap(x) / EW.bandDen), x.spread);
export const cut = (x) => Math.max(0, x.p - x.s);

export function judge(x) {
  const b = band(x);
  if (x.np < EW.minFlip || x.na < EW.minFlip || x.nv < EW.minFlip) return W.unread;
  if (x.leakV > 0 || x.leakA > 0) return W.leaked;
  if (gap(x) <= 2 * b) return W.noWrites;
  if (x.s + b < x.p) return W.carries;
  if (x.p + b < x.s) return W.raises;
  return W.noEffect;
}

export const dominant = (e) => e.v === W.carries && e.p < 2 * e.cut;

export function finding(allV, es) {
  if (allV === W.unread || allV === W.leaked) return 'unread';
  if (allV === W.noWrites) return 'no writes';
  const ds = es.filter(dominant);
  if (ds.length === 0) return es.some((e) => e.v === W.carries) ? 'spread over writers' : 'joint';
  if (ds.length === 1) return `dominant ${ARM_OF[ds[0].w]}`;
  return 'several dominate';
}

export const overallF = (fs) => overallNames(fs.filter((f) => f !== 'unread'));

const rowsOf = (rep, arm) => (rep ? rep.rows.filter((r) => r.arm === arm && r.rs) : []);
export const framesOf = (row) => {
  const kt = row.rs.kt ?? [];
  return (row.rs.frames ?? []).map((f) => ({ r: f.r, keys: (f.k ?? []).map((k) => (typeof k === 'number' ? kt[k] : k)) }));
};

export function decideJobF(rep) {
  const pall = rowsOf(rep, 'rs-flip-pall').map(framesOf);
  const all = rowsOf(rep, 'rs-flip-qwrite').map(framesOf)[0] ?? [];
  const nat = rowsOf(rep, 'rs-flip-nat').map(framesOf)[0] ?? [];
  const cell = (w) => ({ pall, all, var: rowsOf(rep, `rs-flip-${ARM_OF[w]}`).map(framesOf)[0] ?? [], muted: KEYS[w] });
  const cells = {};
  for (const w of [...WRITERS, 'write']) {
    const c = cell(w);
    const nums = cellNums(c);
    cells[w] = { nums, band: band(nums), cut: cut(nums), verdict: judge(nums) };
  }
  const es = WRITERS.map((w) => ({ w, v: cells[w].verdict, p: cells[w].nums.p, cut: cells[w].cut }));
  const f = finding(cells.write.verdict, es);
  const natRate = rate(nat);
  return { cells, entries: es, finding: f, nat: { n: nat.length, rate: natRate } };
}

export function cellLineF(label, w, d) {
  const x = d.nums;
  return `end-floor ${label} ${ARM_OF[w]}: floor ${x.p} arm ${x.s} reference ${x.a} per 100 frames, cut ${d.cut}, band ${d.band} spread ${x.spread}, frames floor ${x.np} reference ${x.na} arm ${x.nv}, leaks ${x.leakV}/${x.leakA}, verdict ${d.verdict}`;
}

export function jobLinesF(label, rep) {
  const d = decideJobF(rep);
  const lines = Object.entries(d.cells).map(([w, c]) => cellLineF(label, w, c));
  lines.push(`end-floor ${label} natural page ${d.nat.rate} per 100 frames over ${d.nat.n} frames`);
  lines.push(`end-floor ${label} finding: ${d.finding}`);
  return { lines, d };
}

export const overallW = (vs) => overallNames(vs.filter((v) => v !== W.unread && v !== W.leaked));

export function overallFloor(ds) {
  const cells = {};
  for (const w of [...WRITERS, 'write']) cells[w] = overallW(ds.map((d) => d.cells[w].verdict));
  return { cells, finding: overallF(ds.map((d) => d.finding)) };
}
