import { readFileSync } from 'node:fs';
import { TOUCH_TAIL, findCounts, lastFrame, runWindows, sumRange } from '../../packages/measure-chromium/src/offscreen-windows.mjs';

const KEYS = ['census.layers', 'census.drawingLayers', 'census.drawingAreaPx', 'census.tiles', 'census.activeTiles'];

function runOf(path) {
  const c = JSON.parse(readFileSync(path, 'utf8'));
  const frames = c.frames;
  const cols = Object.fromEntries(KEYS.map((k) => [k, frames.map((f) => f.counts[k] ?? 0)]));
  const run = { ys: frames.map((f) => Math.round(f.scrollY * 1000)), cols, tail: TOUCH_TAIL };
  const w = runWindows(run);
  const last = lastFrame(frames.length, TOUCH_TAIL);
  const span = (name, lo, hi) => ({ name, lo, hi, ...Object.fromEntries(KEYS.map((k) => [k, sumRange(cols[k], lo, hi)])) });
  const spans = [
    ...w.windows.map((x) => {
      const win = x.vec.vals;
      return { name: x.name, ...Object.fromEntries(KEYS.map((k) => [k, win[k]])) };
    }),
    span('tail', last, frames.length),
    span('whole', 0, frames.length),
  ];
  return { path, search: c.meta?.search ?? null, end: w.end, frames: frames.length, spans };
}

const out = {};
for (const a of process.argv.slice(2)) {
  const eq = a.indexOf('=');
  out[a.slice(0, eq)] = findCounts(a.slice(eq + 1)).map(runOf);
}
process.stdout.write(JSON.stringify(out, null, 1) + '\n');
