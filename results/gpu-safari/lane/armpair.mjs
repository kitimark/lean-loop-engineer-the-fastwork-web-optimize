import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { decodePng } from '../../../packages/measure-webkit/src/pathpix-png.mjs';
import { hashOf } from './pix.mjs';

const boxOf = (r, dpr) => (r ? [(r[0] / 1e6) * dpr, ((r[0] + r[2]) / 1e6) * dpr, (r[1] / 1e6) * dpr, ((r[1] + r[3]) / 1e6) * dpr] : null);
const inBox = (bx, x, y) => !!bx && x >= bx[0] && x < bx[1] && y >= bx[2] && y < bx[3];

export function diffImages(a, b, boxes = {}) {
  let changed = 0, maxDelta = 0, x0 = a.w, y0 = a.h, x1 = -1, y1 = -1;
  const inside = Object.fromEntries(Object.keys(boxes).map((k) => [k, 0]));
  for (let y = 0; y < a.h; y++) {
    for (let x = 0; x < a.w; x++) {
      const o = (y * a.w + x) * 4;
      const d = Math.max(Math.abs(a.rgba[o] - b.rgba[o]), Math.abs(a.rgba[o + 1] - b.rgba[o + 1]), Math.abs(a.rgba[o + 2] - b.rgba[o + 2]));
      if (d === 0) continue;
      changed++;
      if (d > maxDelta) maxDelta = d;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      for (const k of Object.keys(boxes)) if (inBox(boxes[k], x, y)) inside[k]++;
    }
  }
  return { changed, maxDelta, bbox: changed ? [x0, y0, x1, y1] : null, inside };
}

export function armPair(cap, shotsDir, idA, idB) {
  const dpr = cap.session.dpr;
  const load = (id, st) => decodePng(readFileSync(join(shotsDir, cap.arms[id].states.find((s) => s.id === st).files[0])));
  return cap.states.map((st) => {
    const A = cap.arms[idA].states.find((s) => s.id === st.id);
    const a = load(idA, st.id), b = load(idB, st.id);
    const boxes = { platform: boxOf(A.state.platform, dpr), nav: boxOf(A.state.rect, dpr) };
    const d = diffImages(a, b, boxes);
    return { state: st.id, a: idA, b: idB, hashA: hashOf(a), hashB: hashOf(b), ...d, boxes };
  });
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const [, , shotsDir, idA, idB, out] = process.argv;
  const cap = JSON.parse(readFileSync(join(shotsDir, 'capture.json'), 'utf8'));
  const text = JSON.stringify({ schema: 'fw.gpu-safari-armpair/1', session: cap.session, rows: armPair(cap, shotsDir, idA, idB) }, null, 1) + '\n';
  if (out) writeFileSync(out, text);
  else console.log(text);
}
