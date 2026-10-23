import { createHash } from 'node:crypto';
import { inflateSync } from 'node:zlib';

export function decodePng(b64) {
  const buf = Buffer.from(b64, 'base64');
  if (buf.length < 33 || buf.readUInt32BE(0) !== 0x89504e47) return null;
  let off = 8, w = 0, h = 0, ct = -1;
  const idat = [];
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('latin1', off + 4, off + 8);
    const d = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') {
      w = d.readUInt32BE(0); h = d.readUInt32BE(4); ct = d[9];
      if (d[8] !== 8 || d[12] !== 0 || d[10] !== 0 || d[11] !== 0) return null;
    } else if (type === 'IDAT') idat.push(d);
    else if (type === 'IEND') break;
    off += 12 + len;
  }
  const bpp = ct === 6 ? 4 : ct === 2 ? 3 : 0;
  if (!bpp || !w || !h || idat.length === 0) return null;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = w * bpp;
  if (raw.length !== h * (stride + 1)) return null;
  const px = Buffer.alloc(h * stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    for (let x = 0; x < stride; x++) {
      const v = raw[y * (stride + 1) + 1 + x];
      const a = x >= bpp ? px[y * stride + x - bpp] : 0;
      const b = y > 0 ? px[(y - 1) * stride + x] : 0;
      const c = x >= bpp && y > 0 ? px[(y - 1) * stride + x - bpp] : 0;
      let r;
      if (f === 0) r = v;
      else if (f === 1) r = v + a;
      else if (f === 2) r = v + b;
      else if (f === 3) r = v + ((a + b) >> 1);
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); r = v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c); }
      else return null;
      px[y * stride + x] = r & 255;
    }
  }
  return { w, h, bpp, px };
}

export function pngRegionHash(b64, x0, y0, x1, y1) {
  const img = decodePng(b64);
  if (!img) return null;
  const xa = Math.max(0, Math.floor(x0)), xb = Math.min(img.w, Math.ceil(x1)), ya = Math.max(0, Math.floor(y0)), yb = Math.min(img.h, Math.ceil(y1));
  if (xa >= xb || ya >= yb) return null;
  const hash = createHash('sha256');
  for (let y = ya; y < yb; y++) hash.update(img.px.subarray(y * img.w * img.bpp + xa * img.bpp, y * img.w * img.bpp + xb * img.bpp));
  return hash.digest('hex').slice(0, 16);
}
