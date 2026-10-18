// Image comparison: two PNG crops -> the counts the Lean verdict takes (Fw.Gate.Pixel.Stats) plus a diff image.
// No pass/fail decision here (verdict.mjs). Counting rules:
//  - the canvas is the larger of the two crops in each direction (total = W x H);
//  - pixels outside the smaller crop count as changed with delta 255 (a size mismatch is a change);
//  - on the common area pixelmatch (YIQ-free OKLab HyAB threshold 0.1) finds the differing pixels; the ones it
//    classifies as antialiasing are the "aa" mask (counted apart), the rest are "changed". The diff image colours them:
//    red = changed, yellow = antialiasing only, magenta = outside the smaller crop, grey = equal.
import pixelmatch from 'pixelmatch';
import { PNG } from 'pngjs';

export const decode = (buf) => {
  const p = PNG.sync.read(buf);
  return { width: p.width, height: p.height, data: p.data };
};
const toPng = (img) => { const p = new PNG({ width: img.width, height: img.height }); img.data.copy ? img.data.copy(p.data) : p.data.set(img.data); return p; };
export const encodePng = (img) => PNG.sync.write(toPng(img));

/** Same size and same bytes (the settled check compares two captures of one arm). */
export const sameImage = (a, b) => a.width === b.width && a.height === b.height && Buffer.compare(Buffer.from(a.data.buffer, a.data.byteOffset, a.data.length), Buffer.from(b.data.buffer, b.data.byteOffset, b.data.length)) === 0;

const crop = (img, w, h) => {
  if (img.width === w && img.height === h) return img.data;
  const out = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) img.data.copy(out, y * w * 4, y * img.width * 4, y * img.width * 4 + w * 4);
  return out;
};

/**
 * Compare two decoded images. `a` is the original, `b` the rewrite; either may be null (the element is absent in that
 * arm: its canvas is 0 x 0). Returns { stats, size, diff } where stats lacks `settled` (the caller adds it).
 */
export function compare(a, b) {
  const A = a ?? { width: 0, height: 0, data: Buffer.alloc(0) };
  const B = b ?? { width: 0, height: 0, data: Buffer.alloc(0) };
  const W = Math.max(A.width, B.width);
  const H = Math.max(A.height, B.height);
  const w = Math.min(A.width, B.width);
  const h = Math.min(A.height, B.height);
  const total = W * H;
  const outside = total - w * h;
  const out = Buffer.alloc(W * H * 4);
  for (let i = 0; i < total; i++) { out[4 * i] = 255; out[4 * i + 1] = 0; out[4 * i + 2] = 255; out[4 * i + 3] = 255; }
  let changed = outside;
  let aa = 0;
  let maxDelta = outside > 0 ? 255 : 0;
  let aaMaxDelta = 0;
  if (w > 0 && h > 0) {
    const ca = crop(A, w, h);
    const cb = crop(B, w, h);
    const o = Buffer.alloc(w * h * 4);
    pixelmatch(ca, cb, o, w, h, { threshold: 0.1, includeAA: false });
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = 4 * (y * w + x);
        const isDiff = o[i] === 255 && o[i + 1] === 0 && o[i + 2] === 0;
        const isAA = o[i] === 255 && o[i + 1] === 255 && o[i + 2] === 0;
        if (isDiff || isAA) {
          const d = Math.max(Math.abs(ca[i] - cb[i]), Math.abs(ca[i + 1] - cb[i + 1]), Math.abs(ca[i + 2] - cb[i + 2]), Math.abs(ca[i + 3] - cb[i + 3]));
          if (isDiff) { changed++; if (d > maxDelta) maxDelta = d; } else { aa++; if (d > aaMaxDelta) aaMaxDelta = d; }
        }
        const j = 4 * (y * W + x);
        out[j] = o[i]; out[j + 1] = o[i + 1]; out[j + 2] = o[i + 2]; out[j + 3] = 255;
      }
    }
  }
  return {
    stats: { total, changed, aa, maxDelta, aaMaxDelta },
    size: { orig: [A.width, A.height], rewrite: [B.width, B.height] },
    diff: { width: W, height: H, data: out },
  };
}
