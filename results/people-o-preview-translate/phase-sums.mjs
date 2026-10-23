#!/usr/bin/env node
// Per phase, the sum over frames of some counts of each counts.json (TS stand-in: sums; the classes are fwcore's). Usage:
//   node phase-sums.mjs label=<counts.json> ...
import { readFileSync } from 'node:fs';

const KEYS = ['trace.Layout', 'trace.Layout.dirtyObjects', 'trace.UpdateLayoutTree', 'trace.Paint', 'trace.PrePaint', 'trace.UpdateLayer', 'raster.invalidationAreaPx'];
for (const arg of process.argv.slice(2)) {
  const [label, file] = arg.split('=');
  const doc = JSON.parse(readFileSync(file, 'utf8'));
  const out = {};
  for (const f of doc.frames) {
    const p = (out[f.phase] ??= { frames: 0, ...Object.fromEntries(KEYS.map((k) => [k, 0])) });
    p.frames++;
    for (const k of KEYS) p[k] += f.counts[k] ?? 0;
  }
  console.log(label, JSON.stringify(out));
}
