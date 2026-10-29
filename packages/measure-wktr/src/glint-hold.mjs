export const GH_C = { minIdle: 40, minFlip: 12, minSpread: 50, bandDen: 16, minValid: 2 };

const DUR = 5000;
const SEG = 1000;
const RAMP = { left: [0, 3], right: [1, 2] };
const FAITHFUL = 2;

export const tickAt = (hold, side, e) => {
  if (e < 0) return 0;
  if (!hold) return FAITHFUL;
  const k = Math.min(4, Math.floor((((e % DUR) + DUR) % DUR) / SEG));
  return RAMP[side].includes(k) ? 2 : 0;
};
const tickO = (hold, side, e) => e !== null && e !== undefined && tickAt(hold, side, e) > 0;
export const frameTicks = (hold, prev, f) =>
  tickO(hold, 'left', f[1]) || tickO(hold, 'right', f[2]) || (prev !== null && (tickO(hold, 'left', prev[1]) || tickO(hold, 'right', prev[2])));
export const ticks = (hold, fs) => fs.reduce((n, f, i) => n + (frameTicks(hold, i === 0 ? null : fs[i - 1], f) ? 1 : 0), 0);
export const armTicks = (hold, arm) => arm.reduce((n, w) => n + ticks(hold, w), 0);
export const armFrames = (arm) => arm.flat();
export const rpf100 = (fs) => (fs.length === 0 ? 0 : Math.floor((fs.reduce((s, f) => s + f[0], 0) * 100) / fs.length));
const spreadOf = (xs) => {
  const mx = xs.reduce((m, x) => Math.max(m, x), 0);
  return mx - xs.reduce((m, x) => Math.min(m, x), mx);
};
const sum = (xs) => xs.reduce((a, b) => a + b, 0);

export const cellNums = (c) => ({
  nb: sum(c.baseOn.map((a) => armFrames(a).length)),
  bq: sum(c.baseOn.map((a) => armTicks(false, a))),
  nf: armFrames(c.baseOff).length,
  n: armFrames(c.holdOn).length,
  q: armTicks(true, c.holdOn),
  b: rpf100(c.baseOn.flatMap(armFrames)),
  f: rpf100(armFrames(c.baseOff)),
  h: rpf100(armFrames(c.holdOn)),
  spread: spreadOf(c.baseOn.map((a) => rpf100(armFrames(a)))),
});

const sub = (a, b) => Math.max(0, a - b);
export const numsS = (x) => sub(x.b, x.f);
export const numsPred = (x) => (x.n === 0 ? x.b : x.f + Math.floor((numsS(x) * x.q) / x.n));
export const numsBand = (x) => Math.max(Math.floor(numsS(x) / GH_C.bandDen), x.spread);
const predCut = (x) => sub(x.b, numsPred(x));

export const V = {
  unread: 'unread', premise: 'premise', noContrast: 'no-contrast', uninformative: 'uninformative',
  asPredicted: 'cuts as predicted', cutsLess: 'cuts less', cutsMore: 'cuts more', noCut: 'no cut',
};
const JUDGED = new Set([V.asPredicted, V.cutsLess, V.cutsMore, V.noCut]);
export const judged = (v) => JUDGED.has(v);

export function judge(minF, x) {
  const band = numsBand(x);
  const pred = numsPred(x);
  if (x.nb < minF || x.nf < minF || x.n < minF) return V.unread;
  if (x.bq < x.nb) return V.premise;
  if (x.b < x.f + GH_C.minSpread) return V.noContrast;
  if (predCut(x) < 2 * band) return V.uninformative;
  if (x.h + band < pred) return V.cutsMore;
  if (pred + band < x.h) return x.b <= x.h + band ? V.noCut : V.cutsLess;
  return V.asPredicted;
}

export function overall(vs) {
  const js = vs.filter(judged);
  if (js.length < GH_C.minValid) return 'inconclusive';
  return js.slice(1).every((v) => v === js[0]) ? js[0] : 'mixed';
}

export function rowArm(row) {
  const fr = row.rs.frames.map((f) => [f.r, f.g ? f.g[0] : null, f.g ? f.g[1] : null]);
  const wins = row.rs.wins && row.rs.wins.length ? row.rs.wins : [fr.length];
  const out = [];
  let at = 0;
  for (const n of wins) { out.push(fr.slice(at, at + n)); at += n; }
  return out;
}

const rowsOf = (report, arm) => report.rows.filter((r) => r.arm === arm && r.rs);

export function reportToCells(base, hold) {
  const cell = (kind) => {
    const on = rowsOf(base, `rs-${kind}`).map(rowArm);
    const off = rowsOf(base, `rs-${kind}-smil`)[0];
    const h = rowsOf(hold, `rs-${kind}`)[0];
    return { baseOn: on, baseOff: off ? rowArm(off) : [], holdOn: h ? rowArm(h) : [] };
  };
  return { idle: cell('idle'), flip: cell('flip') };
}

export function decideJob(base, hold) {
  const cells = reportToCells(base, hold);
  const one = (c, minF) => {
    const nums = cellNums(c);
    return { nums, pred: numsPred(nums), band: numsBand(nums), verdict: judge(minF, nums) };
  };
  return { idle: one(cells.idle, GH_C.minIdle), flip: one(cells.flip, GH_C.minFlip) };
}

export const jobLine = (label, kind, d) => {
  const x = d.nums;
  return `glint ${label} ${kind}: base ${x.b} floor ${x.f} hold ${x.h} per 100 frames, predicted ${d.pred} band ${d.band} spread ${x.spread}, frames base ${x.nb} floor ${x.nf} hold ${x.n}, hold frames after a tick ${x.q}/${x.n}, base frames after a tick ${x.bq}/${x.nb} => ${d.verdict}`;
};

export const glintLines = (label, base, hold) => {
  const d = decideJob(base, hold);
  return [jobLine(label, 'idle', d.idle), jobLine(label, 'flip', d.flip)];
};

export const overallJobs = (ds) => ({ idle: overall(ds.map((d) => d.idle.verdict)), flip: overall(ds.map((d) => d.flip.verdict)) });
