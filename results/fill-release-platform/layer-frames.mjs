// TS stand-in (no Lean golden): sums the census layer, drawing-area and tile counts per offscreen window (windows from
// packages/measure-chromium/src/offscreen-windows.mjs), over the profile tail and over the whole run, per counts.json.
// usage: node layer-frames.mjs <label>=<dir> [<label>=<dir> ...]
import { readFileSync } from 'node:fs';
import { allWindows, endFrame, findCounts, lastFrame, TOUCH_TAIL } from '../../packages/measure-chromium/src/offscreen-windows.mjs';

const KEYS = ['census.layers', 'census.drawingLayers', 'census.drawingAreaPx', 'census.tiles', 'census.activeTiles'];

function runOf(path) {
  const c = JSON.parse(readFileSync(path, 'utf8'));
  const frames = c.frames;
  const e = endFrame(frames.map((f) => Math.round(f.scrollY * 1000)));
  const last = lastFrame(frames.length, TOUCH_TAIL);
  const sum = (lo, hi, k) => frames.slice(lo, hi).reduce((s, f) => s + (f.counts[k] ?? 0), 0);
  const spans = [...allWindows(e, last), { name: 'tail', lo: last, hi: frames.length }, { name: 'whole', lo: 0, hi: frames.length }];
  return {
    path, search: c.meta?.search ?? null, end: e, frames: frames.length,
    spans: spans.map((w) => ({ name: w.name, lo: w.lo, hi: w.hi, ...Object.fromEntries(KEYS.map((k) => [k, sum(w.lo, w.hi, k)])) })),
  };
}

const out = {};
for (const a of process.argv.slice(2)) {
  const eq = a.indexOf('=');
  out[a.slice(0, eq)] = findCounts(a.slice(eq + 1)).map(runOf);
}
process.stdout.write(JSON.stringify(out, null, 1) + '\n');
