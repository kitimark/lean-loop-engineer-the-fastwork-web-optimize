export const C = { minJobs: 3, flipShareMin: 750 };

export const METRICS = {
  chromium: [
    { name: 'RasterTask', key: 'trace.RasterTask' },
    { name: 'DisplayItemListRaster', key: 'trace.DisplayItemListRaster' },
    { name: 'PaintImage', key: 'trace.PaintImage' },
    { name: 'cc.Draw', key: 'trace.cc.Draw' },
  ],
  webkit: [{ name: 'layerCount' }, { name: 'backingBytes' }, { name: 'Paint' }],
};

const arm = (id, off, flip) => ({ id, off, flip });
export const ARMS = [arm('base', false, false), arm('base+off', true, false), arm('timed-fixed', false, true), arm('timed-fixed+off', true, true)];
export const PROBE_FLAG = 'morph.columns:probe-off';
const CHROMIUM_ARMS = ['base+off', 'timed-fixed', 'timed-fixed+off'];

export const flagsOf = (a) => [...(a.off ? [PROBE_FLAG] : []), ...(a.flip ? ['morph.geom:on', 'morph.tween:geom-timed'] : [])];
export const searchOf = (a) => (flagsOf(a).length ? `?fw=${flagsOf(a).join(',')}` : '');
export const refOf = (a) => (a.flip ? 'timed-fixed' : 'base');
export const wkArmOf = (a) => `morph-${a.flip ? 'timed' : 'base'}${a.off ? '-off' : ''}`;
export const crLabelOf = (a) => (a.id === 'base' ? 'rewrite' : `f${CHROMIUM_ARMS.indexOf(a.id) + 1}`);
export const armById = (id) => ARMS.find((a) => a.id === id);

export const countsArmsToken = () => CHROMIUM_ARMS.map((id) => flagsOf(armById(id)).join(',')).join('|');

export const flipValid = (took, pushes) => pushes > 0 && C.flipShareMin * pushes <= 1000 * took;

export const pushLabel = (p) => (p.flipArm ? (p.took ? 'flip' : p.onDark ? 'dark-no-take' : 'light-fallback') : 'plain');

export const lo = (xs) => xs.reduce((m, x) => Math.min(m, x), xs[0] ?? 0);
export const hi = (xs) => xs.reduce((m, x) => Math.max(m, x), xs[0] ?? 0);

export const CELL = { cost: 'pictures cost', noCost: 'no cost', mixed: 'mixed', few: 'few jobs', zero: 'reference zero' };

export function cellOf(ref, off) {
  if (ref.length < C.minJobs || off.length < C.minJobs) return CELL.few;
  if (hi(ref) === 0) return CELL.zero;
  if (off.every((o) => o < lo(ref))) return CELL.cost;
  if (off.every((o) => lo(ref) <= o && o <= hi(ref))) return CELL.noCost;
  return CELL.mixed;
}

export const READING = { cost: 'pictures cost', noCost: 'no cost', mixed: 'mixed', few: 'undecided (few jobs)' };

export function reading(valid, cells) {
  if (!valid) return READING.few;
  if (cells.includes(CELL.cost)) return READING.cost;
  if (cells.length === 0 || cells.includes(CELL.few)) return READING.few;
  if (cells.every((c) => c === CELL.noCost || c === CELL.zero)) return READING.noCost;
  return READING.mixed;
}

export function fate(plan, bc, bw, fc, fw) {
  if (plan === 'p2' || plan === 'p3' || plan === 'p4') return 'independent of picture cost';
  const rs = plan === 'p5' ? [bc, bw, fc, fw] : [bc, bw];
  if (rs.includes(READING.cost)) return 'keep';
  if (rs.every((r) => r === READING.noCost)) return 'drop';
  return 'open';
}

export function contrast(engine, jobs, offId, logs = {}) {
  const off = armById(offId);
  const ref = armById(refOf(off));
  const cells = METRICS[engine].map((m) => {
    const r = (jobs[ref.id] ?? []).map((j) => j[m.name]).filter(Number.isFinite);
    const o = (jobs[off.id] ?? []).map((j) => j[m.name]).filter(Number.isFinite);
    return { metric: m.name, ref: r, off: o, lo: r.length ? lo(r) : null, hi: r.length ? hi(r) : null, cell: cellOf(r, o) };
  });
  const arms = off.flip ? [ref.id, off.id] : [];
  const valid = arms.every((id) => flipValid(logs[id]?.took ?? 0, logs[id]?.pushes ?? 0));
  return { ref: ref.id, off: off.id, valid, cells, reading: reading(valid, cells.map((c) => c.cell)) };
}

export function fates(readings) {
  const { bc, bw, fc, fw } = readings;
  return Object.fromEntries(['p2', 'p3', 'p4', 'p5', 'p6'].map((p) => [p, fate(p, bc, bw, fc, fw)]));
}
