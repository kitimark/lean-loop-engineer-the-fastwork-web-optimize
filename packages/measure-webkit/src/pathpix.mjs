
export const offsetAt = (maxY, i) => Math.floor((i * maxY) / 8);
export const offsets = (maxY) => Array.from({ length: 9 }, (_, i) => offsetAt(maxY, i));

const clampN = (n, v) => Math.max(0, Math.min(n, v));
const fdiv = (a, d) => Math.floor(a / d);
export function span(dpr, n, lo, len) {
  return [clampN(n, fdiv(lo * dpr, 1000000) - 1), clampN(n, -fdiv(-((lo + len) * dpr), 1000000) + 1)];
}
export function mask(dpr, fw, fh, box) {
  const [x0, x1] = span(dpr, fw, box[0], box[2]);
  const [y0, y1] = span(dpr, fh, box[1], box[3]);
  return [x0, x1, y0, y1];
}
export const maskEmpty = (m) => m[0] >= m[1] || m[2] >= m[3];
export const inMask = (m, c, r) => m[0] <= c && c < m[1] && m[2] <= r && r < m[3];

export function rawOf(px) {
  let changed = 0, maxDelta = 0;
  for (const d of px) { if (d !== 0) changed++; if (d > maxDelta) maxDelta = d; }
  return { changed, maxDelta };
}
export const rawOk = (r) => (r.changed === 0) === (r.maxDelta === 0) && r.maxDelta <= 255;

const has = (c, names) => c.props.some((p) => names.includes(p));
const translates = (c) => has(c, ['transform', 'translate', 'offset']);
const resamples = (c) => c.scales || has(c, ['scale', 'rotate']);
const filters = (c) => has(c, ['filter', 'backdrop-filter']);
const composited = (c) => c.compA || c.compB;

export function premises(engine, c) {
  return [
    ...(composited(c) ? ['P1'] : []), 'P2', 'P3', 'P4',
    ...(c.snap ? ['S1', 'T1'] : []),
    ...(c.text && (resamples(c) || (translates(c) && !c.snap)) ? ['C1'] : []),
    ...(resamples(c) ? ['C2'] : []),
    ...(translates(c) && !c.snap ? ['C5'] : []),
    ...(filters(c) && engine === 'webkit' && composited(c) ? ['C6'] : []),
  ];
}

function rat(s) {
  const [n, d = '1'] = String(s).split('/');
  return [BigInt(n), BigInt(d)];
}
const GRID = [1n, 10000n];
function onGrid([n, d]) {
  const fl = (a, b) => { const q = a / b; return a % b !== 0n && (a < 0n) !== (b < 0n) ? q - 1n : q; };
  const r = fl(2n * n + d, 2n * d);
  const diff = n - r * d;
  const ad = diff < 0n ? -diff : diff;
  return ad * GRID[1] <= GRID[0] * d;
}
export function cellS1(c) {
  if (!c.origin) return false;
  return c.origin.every((s) => { const [n, d] = rat(s); return onGrid([n * BigInt(c.dpr), d]); });
}

export function cellValid(c) {
  return c.run !== '' && c.lossless && c.sameA && c.sameB && (c.control === null || c.control.same) &&
    rawOk(c.out) && rawOk(c.inside) && (c.control === null || rawOk(c.control.raw)) && (!c.claim.snap || cellS1(c));
}
function closed(c, p) {
  switch (p) {
    case 'P1': return c.p1;
    case 'P2': case 'P3': case 'P4': return true;
    case 'S1': return cellS1(c);
    case 'T1': return c.t1 !== null && c.t1 !== '';
    default: return false;
  }
}
const exactBacked = (c) => premises(c.engine, c.claim).every((p) => closed(c, p));
const covers = (b, claim) => b === 'doubleRound' && claim.props.length > 0 && claim.props.every((p) => p === 'opacity') && !claim.scales && !claim.text;
const near1Backed = (c) => c.claim.bound !== null && covers(c.claim.bound, c.claim) && premises(c.engine, c.claim).filter((p) => p !== 'P1').every((p) => closed(c, p));
export const textHold = (c) => premises(c.engine, c.claim).includes('C1') && !c.stripsAccepted;
const withinNoise = (c) => c.control !== null && c.inside.changed <= c.control.raw.changed && c.inside.maxDelta <= c.control.raw.maxDelta;

export function grade(c) {
  if (!cellValid(c)) return 'invalid';
  if (c.out.changed !== 0) return 'L';
  if (textHold(c)) return 'L';
  if (c.inside.changed === 0 && exactBacked(c)) return 'E';
  if (c.inside.maxDelta <= 1 && near1Backed(c)) return 'E1';
  if (c.inside.maxDelta <= 1) return 'Q';
  if (withinNoise(c)) return 'Q';
  return 'L';
}

export const ALWAYS = ['opacity', 'filter', 'backdrop-filter', 'transform', 'translate', 'scale', 'rotate'];
export const accelerated = (ps) => ps.every((p) => ALWAYS.includes(p));
