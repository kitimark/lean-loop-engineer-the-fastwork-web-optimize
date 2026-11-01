import { crc32, deflateSync, inflateSync } from 'node:zlib';

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export function decodePng(buf) {
  if (!buf.subarray(0, 8).equals(SIG)) throw new Error('not a PNG');
  let at = 8; let hdr = null; const idat = [];
  while (at < buf.length) {
    const len = buf.readUInt32BE(at); const type = buf.toString('latin1', at + 4, at + 8); const body = buf.subarray(at + 8, at + 8 + len);
    if (type === 'IHDR') hdr = { width: body.readUInt32BE(0), height: body.readUInt32BE(4), depth: body[8], color: body[9], interlace: body[12] };
    else if (type === 'IDAT') idat.push(body);
    at += 12 + len;
  }
  if (!hdr) throw new Error('PNG has no IHDR');
  if (hdr.depth !== 8 || (hdr.color !== 2 && hdr.color !== 6) || hdr.interlace !== 0) throw new Error(`unsupported PNG (depth ${hdr.depth}, color ${hdr.color}, interlace ${hdr.interlace})`);
  const bpp = hdr.color === 6 ? 4 : 3; const stride = hdr.width * bpp;
  const raw = inflateSync(Buffer.concat(idat));
  const px = new Uint8Array(hdr.height * stride);
  for (let y = 0; y < hdr.height; y++) {
    const f = raw[y * (stride + 1)]; const src = y * (stride + 1) + 1; const dst = y * stride;
    for (let i = 0; i < stride; i++) {
      const x = raw[src + i];
      const a = i >= bpp ? px[dst + i - bpp] : 0;
      const b = y > 0 ? px[dst - stride + i] : 0;
      const c = i >= bpp && y > 0 ? px[dst - stride + i - bpp] : 0;
      let v;
      if (f === 0) v = x; else if (f === 1) v = x + a; else if (f === 2) v = x + b; else if (f === 3) v = x + ((a + b) >> 1);
      else if (f === 4) { const p = a + b - c; const pa = Math.abs(p - a); const pb = Math.abs(p - b); const pc = Math.abs(p - c); v = x + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c); }
      else throw new Error(`PNG filter ${f}`);
      px[dst + i] = v & 255;
    }
  }
  const data = new Uint8Array(hdr.width * hdr.height * 4);
  for (let p = 0; p < hdr.width * hdr.height; p++) {
    data[p * 4] = px[p * bpp]; data[p * 4 + 1] = px[p * bpp + 1]; data[p * 4 + 2] = px[p * bpp + 2]; data[p * 4 + 3] = bpp === 4 ? px[p * bpp + 3] : 255;
  }
  return { width: hdr.width, height: hdr.height, data };
}

function chunk(type, body) {
  const head = Buffer.alloc(8); head.writeUInt32BE(body.length, 0); head.write(type, 4, 'latin1');
  const tail = Buffer.alloc(4); tail.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), body])) >>> 0, 0);
  return Buffer.concat([head, body, tail]);
}

export function encodePng({ width, height, data }) {
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) { raw[y * (width * 4 + 1)] = 0; Buffer.from(data.buffer, data.byteOffset + y * width * 4, width * 4).copy(raw, y * (width * 4 + 1) + 1); }
  return Buffer.concat([SIG, chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

export function diffImages(a, b) {
  if (a.width !== b.width || a.height !== b.height) throw new Error(`size differs: ${a.width}x${a.height} against ${b.width}x${b.height}`);
  const d = new Uint8Array(a.width * a.height);
  let max = 0; let count = 0; let over2 = 0; let at = null; const cols = new Set();
  for (let p = 0; p < d.length; p++) {
    let m = 0;
    for (let c = 0; c < 3; c++) m = Math.max(m, Math.abs(a.data[p * 4 + c] - b.data[p * 4 + c]));
    d[p] = m;
    if (m > 0) { count++; cols.add(p % a.width); }
    if (m > 2) over2++;
    if (m > max) { max = m; at = { x: p % a.width, y: Math.floor(p / a.width) }; }
  }
  return { width: a.width, height: a.height, d, max, count, over2, at, columns: [...cols].sort((x, y) => x - y) };
}

export function heat(v) {
  if (v === 0) return [0, 0, 0];
  if (v <= 2) return [30, 60, 160];
  if (v <= 8) return [0, 170, 90];
  if (v <= 32) return [240, 200, 0];
  return [230, 30, 30];
}

export function heatImage(diff) {
  const data = new Uint8Array(diff.width * diff.height * 4);
  for (let p = 0; p < diff.d.length; p++) { const [r, g, b] = heat(diff.d[p]); data.set([r, g, b, 255], p * 4); }
  return { width: diff.width, height: diff.height, data };
}

export function zoom(img, k) {
  const w = img.width * k; const h = img.height * k; const data = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const s = (Math.floor(y / k) * img.width + Math.floor(x / k)) * 4; data.set(img.data.subarray(s, s + 4), (y * w + x) * 4);
  }
  return { width: w, height: h, data };
}

export function stack(imgs, gap, rgb) {
  const width = imgs[0].width; const height = imgs.reduce((s, i) => s + i.height, 0) + gap * (imgs.length - 1);
  const data = new Uint8Array(width * height * 4);
  for (let p = 0; p < width * height; p++) data.set([rgb[0], rgb[1], rgb[2], 255], p * 4);
  let y = 0;
  for (const i of imgs) {
    if (i.width !== width) throw new Error('stack: widths differ');
    data.set(i.data, y * width * 4); y += i.height + gap;
  }
  return { width, height, data };
}

export function padTo(img, width, rgb) {
  if (img.width === width) return img;
  const data = new Uint8Array(width * img.height * 4);
  for (let p = 0; p < width * img.height; p++) data.set([rgb[0], rgb[1], rgb[2], 255], p * 4);
  for (let y = 0; y < img.height; y++) data.set(img.data.subarray(y * img.width * 4, (y + 1) * img.width * 4), y * width * 4);
  return { width, height: img.height, data };
}

const GREY = [128, 128, 128];

export function strip(orig, flag, k) {
  const diff = diffImages(orig, flag);
  return { diff, image: stack([zoom(orig, k), zoom(flag, k), zoom(heatImage(diff), k)], 8, GREY) };
}

export function combine(images) {
  const w = Math.max(...images.map((i) => i.width));
  return stack(images.map((i) => padTo(i, w, GREY)), 16, GREY);
}
