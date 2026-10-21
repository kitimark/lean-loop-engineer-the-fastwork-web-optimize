// Twin of Lean Fw.Device.StillRuns (lean/Fw/Device/StillRuns.lean): the still runs of a part series and the throttle-lift verdict.
// test/throttle-stillruns.test.mjs checks every function against packages/contracts/golden/device/stillruns.jsonl.
// Rows are [scrollY, value per mille] pairs (Lean partSeries); positions are in the recorder's tenth px.

export const BAND_LO = 5;
export const BAND_HI = 6;
export const MIN_BASE = 10;
export const DROP_DEN = 5;

export const mid = (v) => v > 0 && v < 1000;
const dist = (a, b) => (a <= b ? b - a : a - b);

/** The still runs: {k, jump, mid}. A trailing run has no move to end it and is dropped. */
export function runs(rows) {
  const out = [];
  if (rows.length === 0) return out;
  let prev = rows[0][0], k = 0, m = true;
  for (let i = 1; i < rows.length; i++) {
    const [y, v] = rows[i];
    if (y === prev) { k++; m = m && mid(v); continue; }
    if (k > 0) out.push({ k, jump: dist(prev, y), mid: m });
    prev = y; k = 0; m = true;
  }
  return out;
}

const inBand = (lo, hi) => (r) => r.mid && lo <= r.k && r.k <= hi;
export const count = (lo, hi, rows) => runs(rows).filter(inBand(lo, hi)).length;
export const bandRuns = (rows) => count(BAND_LO, BAND_HI, rows);
export const shortRuns = (rows) => count(1, 9, rows);
export const exitFrames = (rows) => rows.filter((r) => mid(r[1])).length;
export const allMove = (rows) => rows.every((r, i) => i === 0 || r[0] !== rows[i - 1][0]);
export const moves = (ys) => ys.every((y, i) => i === 0 || y !== ys[i - 1]);

/** A position that changes once every `p` frames, value `v`. */
export const stairs = (ys, p, v) => ys.flatMap((y) => Array.from({ length: p }, () => [y, v]));

/** Still frames between two updates 100 ms apart at a frame interval of `d` hundredths of a millisecond. */
export const throttleK = (d) => Math.floor((10000 + d - 1) / d) - 1;

export const sameHeight = (hs) => hs.every((h) => h === hs[0]);

/** The probe verdict: confounded | no-data | lifted | not-lifted. base and lift are {runs, frames} summed over the passes of an arm. */
export function verdict(hs, base, lift) {
  if (!sameHeight(hs)) return 'confounded';
  if (base.runs < MIN_BASE || base.frames === 0 || lift.frames === 0) return 'no-data';
  return lift.runs * base.frames * DROP_DEN <= base.runs * lift.frames ? 'lifted' : 'not-lifted';
}

/** Lean partSeries: position i paired with the value of frame i + 1. */
export function partSeries(ys, vs) {
  const n = Math.max(0, Math.min(ys.length, vs.length - 1));
  return ys.slice(0, n).map((y, i) => [y, vs[i + 1]]);
}

/** The counts of one arm summed over its passes (each {ys, vs} in Lean's integer units). */
export function armCounts(passes) {
  let r = 0, f = 0;
  for (const p of passes) {
    const rows = partSeries(p.ys, p.vs);
    r += bandRuns(rows);
    f += exitFrames(rows);
  }
  return { runs: r, frames: f };
}
