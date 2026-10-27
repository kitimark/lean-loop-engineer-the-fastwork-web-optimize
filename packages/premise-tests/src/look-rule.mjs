import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const GOLDEN = resolve(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/morph-geom.jsonl');

export function loadLookGolden(path = GOLDEN) {
  const lines = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const cell = lines.find((l) => l.fn === 'lookCell')?.out;
  if (!cell) throw new Error(`no lookCell line in ${path}`);
  return { cell, lines };
}

const diff = (x, y) => Math.abs(x - y);
export const pixelOver = (cell, a, b) => Math.max(diff(a[0], b[0]), diff(a[1], b[1]), diff(a[2], b[2])) > cell.over;

export const pxRange = (size, x, w) => ({ lo: Math.max(0, Math.floor(x)), hi: Math.min(size, Math.max(0, Math.ceil(x + w))) });

export const share = (over, n) => (n === 0 ? 0 : over / n);

const clamp01 = (x) => Math.min(1, Math.max(0, x));
export const ease = (x) => 1 - (1 - clamp01(x)) ** 3;

const trackValue = (cell, dur, t) => (dur === cell.gridMs ? t / cell.gridMs : dur === cell.timeEnd ? ease(t / cell.tweenMs) : null);
export const within = (cell, v, m) => v - m <= cell.mTol && m - v <= cell.mTol;
export const trackAt = (cell, dur, t, m) => {
  const v = trackValue(cell, dur, t);
  return v === null ? false : within(cell, v, m);
};

export const tracksOk = (m, n) => (m === 0 ? n === 0 : n > 0);
export const scrollEq = (cell, a, b) => a - b <= cell.scrollTol && b - a <= cell.scrollTol;
export const timedSettled = (m, flip, goal, n) => (m === 0 ? !flip && !goal && n === 0 : m === 1 ? flip && goal && n === 0 : false);

export function fadeOf({ lines }, m) {
  const l = lines.find((x) => x.fn === 'lookFade' && x.in.m === m);
  if (!l) throw new Error(`no lookFade golden line for m=${m}`);
  return l.out;
}

export const fadeShows = (cell, golden, o, m) => {
  const f = fadeOf(golden, m).fade;
  return o - f <= cell.fadeTol && f - o <= cell.fadeTol;
};

export function diffMap(a, b) {
  const n = a.width * a.height;
  const out = new Uint8Array(n);
  for (let p = 0; p < n; p++) {
    const i = 4 * p;
    out[p] = Math.max(diff(a.data[i], b.data[i]), diff(a.data[i + 1], b.data[i + 1]), diff(a.data[i + 2], b.data[i + 2]));
  }
  return out;
}

export function regionStats(cell, map, W, H, box) {
  const xr = pxRange(W, box.x, box.width), yr = pxRange(H, box.y, box.height);
  let max = 0, over = 0, n = 0;
  for (let y = yr.lo; y < yr.hi; y++) for (let x = xr.lo; x < xr.hi; x++) {
    const d = map[y * W + x];
    if (d > max) max = d;
    if (d > cell.over) over++;
    n++;
  }
  return { max, share: share(over, n), px: n, over };
}

export function elementTable(cell, map, W, H, boxes) {
  const ranges = boxes.map((b) => ({ b, xr: pxRange(W, b.x, b.width), yr: pxRange(H, b.y, b.height) }))
    .map((r) => ({ ...r, area: Math.max(0, r.xr.hi - r.xr.lo) * Math.max(0, r.yr.hi - r.yr.lo) }))
    .filter((r) => r.area > 0);
  const order = ranges.map((r, i) => i).sort((p, q) => ranges[q].area - ranges[p].area || p - q);
  const owner = new Int32Array(W * H).fill(-1);
  const inside = new Float64Array(ranges.length);
  for (const k of order) {
    const { xr, yr } = ranges[k];
    for (let y = yr.lo; y < yr.hi; y++) for (let x = xr.lo; x < xr.hi; x++) {
      const i = y * W + x;
      owner[i] = k;
      if (map[i] > cell.over) inside[k]++;
    }
  }
  const own = new Float64Array(ranges.length);
  let total = 0, unowned = 0;
  for (let i = 0; i < map.length; i++) {
    if (map[i] <= cell.over) continue;
    total++;
    if (owner[i] < 0) unowned++;
    else own[owner[i]]++;
  }
  const rows = ranges.map((r, k) => ({ key: r.b.key, px: r.area, over: inside[k], own: own[k], shareOfBox: share(inside[k], r.area), shareOfDiff: share(own[k], total) }));
  rows.sort((p, q) => q.own - p.own || q.over - p.over);
  return { total, unowned, rows };
}
