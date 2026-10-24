import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const HZ = 60;
const SEGMENTS = [{ name: 'rest', dyPerFrame: 0, frames: 10 }, { name: 'replay', until: 'script' }, { name: 'tail', dyPerFrame: 0, frames: 30 }];
const X = 215;

const run = (y0, dir, n, step) => Array.from({ length: n }, (_, i) => [X, y0 + dir * step * i]);

export const SCENARIOS = {
  'flick-gap8': { about: 'open at the page end, flick down to close, new touch up to reopen 8 frames after the lift', gap: 8, same: false },
  'flick-gap20': { about: 'as flick-gap8 with 20 frames between the lift and the reopen touch', gap: 20, same: false },
  'flick-gap32': { about: 'as flick-gap8 with 32 frames between the lift and the reopen touch', gap: 32, same: false },
  'same-touch': { about: 'one touch only: up (open), fast down (close), up (reopen) without lifting', gap: 0, same: true, step: 36, n: 10 },
  'same-touch-slow': { about: 'one touch only: up (open), slow down (close), up (reopen) without lifting', gap: 0, same: true, step: 14, n: 18 },
};

export function strokesOf({ gap, same, step = 36, n = 10 }) {
  if (same) {
    const up1 = run(700, -1, 24, 14);
    const last = up1[up1.length - 1][1];
    const hold = Array.from({ length: 50 }, () => [X, last]);
    const down = run(last, 1, n, step).slice(1);
    const up2 = run(down[down.length - 1][1], -1, 21, 14).slice(1);
    return [{ f0: 0, path: [...up1, ...hold, ...down, ...up2] }];
  }
  const open = { f0: 0, path: run(700, -1, 24, 14) };
  const close = { f0: 80, path: run(150, 1, 10, 36) };
  const reopen = { f0: 80 + 10 + gap, path: run(650, -1, 20, 14) };
  return [open, close, reopen];
}

export function profileOf(name) {
  const sc = SCENARIOS[name];
  const strokes = strokesOf(sc);
  const last = strokes[strokes.length - 1];
  return {
    id: `user-bug-1025-reopen-${name}`,
    about: `${sc.about}. Scripted: starts at the page end (the platform is armed there), then the strokes; 60 Hz, then 150 idle frames.`,
    hz: HZ,
    viewport: { width: 430, height: 775, dpr: 3, mobile: true, touch: true },
    pinnedDate: '2026-10-01T00:00:00+07:00',
    timezone: 'Asia/Bangkok',
    locale: 'en-US',
    seed: 1025,
    load: { quietFrames: 30, maxFrames: 900, prerollFrames: 60 },
    zoneHeightPx: 500,
    input: { mode: 'replay', unit: 'css-px', start: 'end', maxFrames: last.f0 + last.path.length + 150, strokes },
    segments: SEGMENTS,
  };
}

export function render(p) {
  const { strokes, ...input } = p.input;
  const head = JSON.stringify({ ...p, input: { ...input, strokes: '@@' } }, null, 2);
  const body = strokes.map((s) => `{ "f0": ${s.f0}, "path": [${s.path.map((q) => `[${q[0]},${q[1]}]`).join(',')}] }`).join(',\n      ');
  return `${head.replace('"@@"', `[\n      ${body}\n    ]`)}\n`;
}

if (process.argv[1] && process.argv[1].endsWith('combo-profile.mjs') && process.argv.includes('--write')) {
  const dir = join(dirname(fileURLToPath(import.meta.url)), '../../../measure-chromium/profiles');
  for (const name of Object.keys(SCENARIOS)) writeFileSync(join(dir, `user-bug-1025-reopen-${name}.json`), render(profileOf(name)));
}
