// Twin of Lean Fw.Device.FinishRuns (lean/Fw/Device/FinishRuns.lean): finish-zone still runs, scrollY reversals while the morph is
// open, open lateness and the per-arm verdict. test/throttle-finish.test.mjs checks it against
// packages/contracts/golden/device/finishruns.jsonl. A frame is [scrollY, maxY, open] with positions in the recorder's tenth px.
import { runs, bandRuns, shortRuns, exitFrames, MIN_BASE, DROP_DEN } from './stillruns.mjs';

export const ZONE_PX = 6000;
export const END_PX = 70;
export const OPEN_WINDOW = 180;

export const inZone = (f) => f[0] >= f[1] - ZONE_PX;
export const atEnd = (f) => f[0] >= f[1] - END_PX;
const zoneValue = (f) => (inZone(f) ? 500 : 0);

/** Each position paired with the zone value of the next frame (Lean zoneRows). */
export const zoneRows = (fs) => fs.slice(0, Math.max(0, fs.length - 1)).map((f, i) => [f[0], zoneValue(fs[i + 1])]);

export const finishBand = (fs) => bandRuns(zoneRows(fs));
export const finishShort = (fs) => shortRuns(zoneRows(fs));
export const finishFrames = (fs) => exitFrames(zoneRows(fs));
export { runs };

/** The first stretch of open frames, at most OPEN_WINDOW of them. */
export function openPhase(fs) {
  const from = fs.findIndex((f) => f[2]);
  if (from < 0) return [];
  let to = from;
  while (to < fs.length && fs[to][2]) to++;
  return fs.slice(from, Math.min(to, from + OPEN_WINDOW));
}

/** Direction changes of the distinct consecutive positions. */
export function turns(xs) {
  const d = xs.filter((x, i) => i === 0 || x !== xs[i - 1]);
  let n = 0;
  for (let i = 1; i + 1 < d.length; i++) if ((d[i] - d[i - 1]) * (d[i + 1] - d[i]) < 0) n++;
  return n;
}

export const reversals = (fs) => turns(openPhase(fs).map((f) => f[0]));

/** Frames from reaching the page end to the first open frame; null when never reached or not open within OPEN_WINDOW. */
export function lateness(fs) {
  const at = fs.findIndex(atEnd);
  if (at < 0) return null;
  const win = fs.slice(at, at + OPEN_WINDOW);
  const i = win.findIndex((f) => f[2]);
  return i < 0 ? null : i;
}

export const reached = (fs) => fs.some(atEnd);

/** The counts of one pass: {band, short, frames, reversals, reached, late}. */
export const reduce = (fs) => ({ band: finishBand(fs), short: finishShort(fs), frames: finishFrames(fs), reversals: reversals(fs),
  reached: reached(fs), late: lateness(fs) });

const sum = (l) => l.reduce((a, b) => a + b, 0);
export const armOf = (rs) => ({ runs: sum(rs.map((r) => r.band)), frames: sum(rs.map((r) => r.frames)) });
export const reversalSum = (rs) => sum(rs.map((r) => r.reversals));

/** The verdict of the lift arm against a baseline arm: no-data | no-signature | lifted | not-lifted. Arms are {runs, frames}. */
export function verdict(base, lift) {
  if (base.frames === 0 || lift.frames === 0) return 'no-data';
  if (base.runs < MIN_BASE) return 'no-signature';
  return lift.runs * base.frames * DROP_DEN <= base.runs * lift.frames ? 'lifted' : 'not-lifted';
}
