#!/usr/bin/env node
// Compile a phone recording (device-lag-recorder) into the committed CI replay profile shape (packages/measure-chromium/profiles/user-*.json).
//   node packages/measure-webkit/src/replay/make-ci-profile.mjs --in rec.json --id user-bug-1025 --about "..." --out profile.json
// The profile keeps the strokes of the pass (taps dropped) resampled at 60 Hz: one touch position per frame, the frame of each stroke's
// start. No timestamps of the recording and no raw samples are kept. The recording itself stays out of git.
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync } from 'node:fs';
import { replayStrokes, t0Of } from '../device-session.mjs';

export const HZ = 60;

const round1 = (v) => Math.round(v * 10) / 10;

/** One stroke [[t, phase, x, y, n]...] as {f0, path}: positions at t0 + k / HZ, linear between samples, ends at the lift. */
export function resample(stroke, t0) {
  const dt = 1000 / HZ;
  const a = stroke[0][0], z = stroke[stroke.length - 1][0];
  const path = [];
  let j = 0;
  for (let k = 0; a + k * dt <= z + 1e-6; k++) {
    const t = a + k * dt;
    while (j + 1 < stroke.length - 1 && stroke[j + 1][0] <= t) j++;
    const p = stroke[j], q = stroke[j + 1] ?? p;
    const u = q[0] === p[0] ? 0 : Math.min(1, Math.max(0, (t - p[0]) / (q[0] - p[0])));
    path.push([round1(p[2] + (q[2] - p[2]) * u), round1(p[3] + (q[3] - p[3]) * u)]);
  }
  return { f0: Math.round((a - t0) / dt), path };
}

export function profileOf(rec, { id, about }) {
  const ss = replayStrokes(rec.touches);
  const t0 = t0Of(ss);
  const strokes = ss.map((s) => resample(s, t0));
  const last = strokes[strokes.length - 1];
  return {
    id,
    about,
    hz: HZ,
    viewport: { width: rec.viewport.w, height: rec.viewport.h, dpr: rec.viewport.dpr, mobile: true, touch: true },
    pinnedDate: '2026-10-01T00:00:00+07:00',
    timezone: 'Asia/Bangkok',
    locale: 'en-US',
    zoneHeightPx: 500,
    input: { mode: 'replay', unit: 'css-px', maxFrames: last.f0 + last.path.length, maxY: rec.maxY, strokes },
  };
}

export function render(p) {
  const { strokes, ...input } = p.input;
  const head = JSON.stringify({ ...p, input: { ...input, strokes: '@@' } }, null, 2);
  const body = strokes.map((s) => `{ "f0": ${s.f0}, "path": [${s.path.map((q) => `[${q[0]},${q[1]}]`).join(',')}] }`).join(',\n      ');
  return `${head.replace('"@@"', `[\n      ${body}\n    ]`)}\n`;
}

if (process.argv[1] && process.argv[1].endsWith('make-ci-profile.mjs')) {
  const { values: v } = parseArgs({ options: { in: { type: 'string' }, id: { type: 'string' }, about: { type: 'string', default: '' }, out: { type: 'string' } } });
  const rec = JSON.parse(readFileSync(v.in, 'utf8'));
  writeFileSync(v.out, render(profileOf(rec, { id: v.id, about: v.about })));
}
