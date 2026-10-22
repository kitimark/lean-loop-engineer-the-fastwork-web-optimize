#!/usr/bin/env node
// Layout passes per frame of the `scroll` phase of profile people-o-hover, from chromium-counts artifacts.
// usage: node layout-per-frame.mjs <label>=<counts.json> [<label>=<counts.json> ...]   (one counts.json per determinism run)
// prints, per label and run, the frames of the phase, the sum of trace.Layout, trace.UpdateLayoutTree, trace.Paint and the max per frame.
import { readFileSync } from 'node:fs';

const KEYS = ['trace.Layout', 'trace.UpdateLayoutTree', 'trace.Paint', 'trace.Layout.dirtyObjects'];
for (const arg of process.argv.slice(2)) {
  const [label, file] = arg.split('=');
  const doc = JSON.parse(readFileSync(file, 'utf8'));
  const frames = doc.frames.filter((f) => f.phase === 'scroll');
  const sum = Object.fromEntries(KEYS.map((k) => [k, frames.reduce((a, f) => a + (f.counts[k] ?? 0), 0)]));
  const perFrame = frames.map((f) => f.counts['trace.Layout'] ?? 0);
  console.log(JSON.stringify({ label, file, frames: frames.length, sum, layoutPerFrame: perFrame.join(','), maxLayout: Math.max(...perFrame), framesWithLayout: perFrame.filter((x) => x > 0).length }));
}
