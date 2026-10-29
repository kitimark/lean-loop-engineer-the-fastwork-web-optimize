export const EW = { minFlip: 12, minSpreadRecalc: 50, minSpreadOther: 20, bandDen: 16, minValid: 2 };

export const METRICS = {
  recalc: { minS: EW.minSpreadRecalc, pick: (f) => f.r },
  layout: { minS: EW.minSpreadOther, pick: (f) => (f.y ? f.y[0] : undefined) },
  compositing: { minS: EW.minSpreadOther, pick: (f) => (f.y ? f.y[1] : undefined) },
  layerFlush: { minS: EW.minSpreadOther, pick: (f) => (f.y ? f.y[2] : undefined) },
};

export const V = { unread: 'unread', noContrast: 'no-contrast', uninformative: 'uninformative', cuts: 'cuts', noChange: 'no change', adds: 'adds' };
const JUDGED = new Set([V.cuts, V.noChange, V.adds]);
export const judged = (v) => JUDGED.has(v);

const sum = (xs) => xs.reduce((a, b) => a + b, 0);
export const rpf100 = (fs) => (fs.length === 0 ? 0 : Math.floor((sum(fs) * 100) / fs.length));
export const spreadOf = (xs) => {
  const mx = xs.reduce((m, x) => Math.max(m, x), 0);
  return mx - xs.reduce((m, x) => Math.min(m, x), mx);
};

export const cellNums = (c) => ({
  nb: sum(c.base.map((a) => a.length)),
  nf: c.floor.length,
  n: c.var.length,
  b: rpf100(c.base.flat()),
  f: rpf100(c.floor),
  v: rpf100(c.var),
  spread: spreadOf(c.base.map(rpf100)),
});
export const numsS = (x) => Math.max(0, x.b - x.f);
export const numsBand = (x) => Math.max(Math.floor(numsS(x) / EW.bandDen), x.spread);
export const atFloor = (x) => x.v <= x.f + numsBand(x);

export function judge(minF, minS, x) {
  const band = numsBand(x);
  if (x.nb < minF || x.nf < minF || x.n < minF) return V.unread;
  if (x.b < x.f + minS) return V.noContrast;
  if (numsS(x) <= 2 * band) return V.uninformative;
  if (x.v + band < x.b) return V.cuts;
  if (x.b + band < x.v) return V.adds;
  return V.noChange;
}

export function overall(vs) {
  const js = vs.filter(judged);
  if (js.length < EW.minValid) return 'inconclusive';
  return js.slice(1).every((v) => v === js[0]) ? js[0] : 'mixed';
}

export const overallNames = (ns) => (ns.length < EW.minValid ? 'inconclusive' : ns.slice(1).every((n) => n === ns[0]) ? ns[0] : 'mixed');

export const CAUSE = {
  none: 'no residual', running: 'the running animation', markup: 'the variant markup', both: 'markup and running animation', offset: 'floor offset between processes',
};
export function causeOf(t) {
  if (t.v <= t.f + t.band) return CAUSE.none;
  if (t.p + t.band < t.v) return t.f + t.band < t.p ? CAUSE.both : CAUSE.running;
  return t.f + t.band < t.p ? CAUSE.markup : CAUSE.offset;
}

export const CATS = ['written', 'animated', 'empty'];
export const catOf = (f) => (f.r === 0 ? null : f.written ? 'written' : f.elems ? 'animated' : 'empty');
export const catSum = (c, fs) => sum(fs.filter((f) => catOf(f) === c).map((f) => f.r));
export const catRate = (c, fs) => (fs.length === 0 ? 0 : Math.floor((catSum(c, fs) * 100) / fs.length));
export const above = (band, live, paused) => CATS.filter((c) => band < Math.max(0, catRate(c, live) - catRate(c, paused)));
export const mechName = (cs) => (cs.length === 0 ? 'nothing above the band' : cs.length === 1 ? `one category: ${cs[0]}` : 'several categories');
export const mechOf = (band, live, paused) => mechName(above(band, live, paused));
const NEXT = {
  written: 'stop the DOM write the top key names while the flip runs',
  animated: 'find the animation that restyles elements in the flip and hold it for the flip',
  empty: 'no page-side fix: read the WebKit invalidation path for a recalc that restyles no element',
};
export const mechNext = (band, live, paused) => {
  const cs = above(band, live, paused);
  return cs.length === 0 ? 'no candidate: the residual is not in the recalcs' : cs.length === 1 ? NEXT[cs[0]] : 'one intervention arm per category above the band';
};

const rowsOf = (rep, arm) => (rep ? rep.rows.filter((r) => r.arm === arm && r.rs) : []);
export function series(row, metric) {
  const fr = row.rs.frames ?? [];
  const xs = fr.map(METRICS[metric].pick);
  return xs.some((x) => x === undefined) ? [] : xs;
}
export const cellOf = (metric, baseRows, floorRow, varRow) => ({
  base: baseRows.map((r) => series(r, metric)),
  floor: floorRow ? series(floorRow, metric) : [],
  var: varRow ? series(varRow, metric) : [],
});
export const sframes = (row) => {
  const kt = row.rs.kt ?? [];
  return (row.rs.frames ?? []).map((f) => {
    const keys = (f.k ?? []).map((k) => (typeof k === 'number' ? kt[k] : k));
    return { r: f.r, written: keys.some((k) => String(k).startsWith('mut:')), elems: (f.z ?? []).some((n) => n > 0), keys };
  });
};
export function keyDeltas(live, paused, top = 6) {
  const tally = (fs) => {
    const m = new Map();
    for (const f of fs) if (f.r > 0) for (const k of new Set(f.keys)) m.set(k, (m.get(k) ?? 0) + 1);
    return m;
  };
  const a = tally(live);
  const b = tally(paused);
  return [...new Set([...a.keys(), ...b.keys()])]
    .map((k) => ({ key: k, live: a.get(k) ?? 0, paused: b.get(k) ?? 0 }))
    .filter((x) => x.live > x.paused)
    .sort((x, y) => y.live - y.paused - (x.live - x.paused) || x.key.localeCompare(y.key))
    .slice(0, top);
}

export const VARIANTS = ['fp', 'comp', 'both'];
export const VARIANT_NAME = { fp: 'platform:faded-pause', comp: 'platform.glint:compositor', both: 'faded-pause + compositor' };

export function decideJobE(reps) {
  const base = reps.base;
  const baseNat = rowsOf(base, 'rs-flip-nat');
  const baseIso = rowsOf(base, 'rs-flip');
  const floor = rowsOf(base, 'rs-flip-pall')[0];
  const one = (metric, baseRows, varRow) => {
    const nums = cellNums(cellOf(metric, baseRows, floor, varRow));
    return { nums, band: numsBand(nums), atFloor: atFloor(nums), verdict: judge(EW.minFlip, METRICS[metric].minS, nums) };
  };
  const cells = {};
  for (const m of Object.keys(METRICS)) {
    for (const v of VARIANTS) cells[`${v}/${m}`] = one(m, baseNat, rowsOf(reps[v], 'rs-flip-nat')[0]);
    cells[`comp-iso/${m}`] = one(m, baseIso, rowsOf(reps.comp, 'rs-flip')[0]);
  }
  const iso = cells['comp-iso/recalc'];
  const compPall = rowsOf(reps.comp, 'rs-flip-pall')[0];
  const compIso = rowsOf(reps.comp, 'rs-flip')[0];
  let cause = null;
  if (floor && compPall && compIso) {
    const t = { f: rpf100(series(floor, 'recalc')), p: rpf100(series(compPall, 'recalc')), v: rpf100(series(compIso, 'recalc')), band: iso.band };
    cause = { ...t, name: causeOf(t) };
  }
  let mech = null;
  const live = rowsOf(reps.comp, 'rs-flip-obsf')[0];
  const paused = rowsOf(reps.comp, 'rs-flip-pallf')[0];
  if (live && paused) {
    const l = sframes(live);
    const p = sframes(paused);
    mech = {
      band: iso.band, frames: [l.length, p.length], rates: CATS.map((c) => catRate(c, l)), pausedRates: CATS.map((c) => catRate(c, p)),
      name: mechOf(iso.band, l, p), next: mechNext(iso.band, l, p), keys: keyDeltas(l, p),
    };
  }
  return { cells, cause, mech };
}

export const cellLine = (label, key, d) => {
  const x = d.nums;
  return `end-wktr ${label} ${key}: base ${x.b} floor ${x.f} variant ${x.v} per 100 frames, band ${d.band} spread ${x.spread}, frames base ${x.nb} floor ${x.nf} variant ${x.n}, at floor ${d.atFloor}, verdict ${d.verdict}`;
};

export function jobLinesE(label, reps) {
  const d = decideJobE(reps);
  const lines = Object.entries(d.cells).map(([k, c]) => cellLine(label, k, c));
  if (d.cause) lines.push(`end-wktr ${label} compositor flip residual: floor ${d.cause.f} own floor ${d.cause.p} live ${d.cause.v} band ${d.cause.band}, cause ${d.cause.name}`);
  if (d.mech) {
    lines.push(`end-wktr ${label} compositor flip mechanism: frames live ${d.mech.frames[0]} paused ${d.mech.frames[1]}, rates ${CATS.map((c, i) => `${c} ${d.mech.rates[i]}/${d.mech.pausedRates[i]}`).join(' ')}, ${d.mech.name}; next: ${d.mech.next}`);
    lines.push(`end-wktr ${label} compositor flip keys (frames with a recalc, live/paused): ${d.mech.keys.map((k) => `${k.key} ${k.live}/${k.paused}`).join(' | ') || '-'}`);
  }
  return { lines, d };
}

export function overallE(ds) {
  const keys = [...new Set(ds.flatMap((d) => Object.keys(d.cells)))];
  const out = {};
  for (const k of keys) out[k] = overall(ds.map((d) => d.cells[k]?.verdict).filter((v) => v !== undefined));
  const causes = ds.map((d) => d.cause?.name).filter((v) => v !== undefined);
  const mechs = ds.map((d) => d.mech?.name).filter((v) => v !== undefined);
  return { cells: out, cause: overallNames(causes), mech: overallNames(mechs) };
}
