import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { decodePng, encodePng, cropImage, sameImage } from './pathpix-png.mjs';
import { mask, maskEmpty, inMask, rawOf, grade, premises, cellS1 } from './pathpix.mjs';

const gcd = (a, b) => (b === 0n ? (a < 0n ? -a : a) : gcd(b, a % b));
export function microRat(u) {
  const n = BigInt(Math.round(u)), d = 1000000n, g = gcd(n, d) || 1n;
  const [a, b] = [n / g, d / g];
  return b === 1n ? `${a}` : `${a}/${b}`;
}

export function deltas(a, b) {
  const n = a.w * a.h, out = new Uint8Array(n), p = a.rgba, q = b.rgba;
  for (let i = 0; i < n; i++) {
    const k = i * 4;
    out[i] = Math.max(Math.abs(p[k] - q[k]), Math.abs(p[k + 1] - q[k + 1]), Math.abs(p[k + 2] - q[k + 2]), Math.abs(p[k + 3] - q[k + 3]));
  }
  return out;
}

const bucket = (d) => (d === 1 ? 'b1' : d <= 3 ? 'b2_3' : d <= 15 ? 'b4_15' : 'b16_255');

export function split(del, w, m) {
  const inside = [], out = [], hist = { b1: 0, b2_3: 0, b4_15: 0, b16_255: 0 };
  for (let i = 0; i < del.length; i++) {
    const d = del[i];
    if (inMask(m, i % w, Math.floor(i / w))) { inside.push(d); if (d) hist[bucket(d)]++; } else out.push(d);
  }
  return { inside: rawOf(inside), out: rawOf(out), hist };
}

export function strip(a, b, del, m, { pad = 8, maxH = 800, gain = 32 } = {}) {
  const x0 = Math.max(0, m[0] - pad), x1 = Math.min(a.w, m[1] + pad), y0 = Math.max(0, m[2] - pad), y1 = Math.min(a.h, Math.min(m[3] + pad, m[2] - pad + maxH));
  const cw = x1 - x0, ch = y1 - y0, gap = 6, W = cw * 3 + gap * 2;
  const rgba = new Uint8Array(W * ch * 4).fill(128);
  for (let r = 0; r < ch; r++) {
    for (let c = 0; c < cw; c++) {
      const s = ((y0 + r) * a.w + x0 + c) * 4;
      const put = (panel, R, G, B) => { const o = (r * W + panel * (cw + gap) + c) * 4; rgba[o] = R; rgba[o + 1] = G; rgba[o + 2] = B; rgba[o + 3] = 255; };
      put(0, a.rgba[s], a.rgba[s + 1], a.rgba[s + 2]);
      put(1, b.rgba[s], b.rgba[s + 1], b.rgba[s + 2]);
      const v = Math.min(255, del[(y0 + r) * a.w + x0 + c] * gain);
      const inM = inMask(m, x0 + c, y0 + r);
      put(2, v, inM ? v : 0, inM ? v : 0);
    }
  }
  return { w: W, h: ch, rgba };
}

export function frameDiff(del, w) {
  let changed = 0, max = 0, x0 = w, y0 = del.length, x1 = -1, y1 = -1;
  for (let i = 0; i < del.length; i++) {
    const d = del[i];
    if (!d) continue;
    changed++; if (d > max) max = d;
    const x = i % w, y = (i - x) / w;
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  return { changed, maxDelta: max, bbox: changed ? [x0, y0, x1 + 1, y1 + 1] : null };
}

export function thumb(a, b, del, k = 4, gain = 32) {
  const cw = Math.floor(a.w / k), ch = Math.floor(a.h / k), gap = 4, W = cw * 3 + gap * 2;
  const rgba = new Uint8Array(W * ch * 4).fill(128);
  for (let r = 0; r < ch; r++) {
    for (let c = 0; c < cw; c++) {
      const s = ((r * k) * a.w + c * k) * 4;
      let m = 0;
      for (let dy = 0; dy < k; dy++) for (let dx = 0; dx < k; dx++) m = Math.max(m, del[(r * k + dy) * a.w + c * k + dx]);
      const d = Math.min(255, m * gain);
      const put = (panel, R, G, B) => { const o = (r * W + panel * (cw + gap) + c) * 4; rgba[o] = R; rgba[o + 1] = G; rgba[o + 2] = B; rgba[o + 3] = 255; };
      put(0, a.rgba[s], a.rgba[s + 1], a.rgba[s + 2]); put(1, b.rgba[s], b.rgba[s + 1], b.rgba[s + 2]); put(2, d, d, d);
    }
  }
  return { w: W, h: ch, rgba };
}

const loadImg = (dir, f) => decodePng(readFileSync(join(dir, f)));
const sig = (s) => JSON.stringify((s.layers ?? []).filter((l) => l.layer).map((l) => [l.layer, l.boundsU, l.memory ?? null]).sort());
const recs = (s, layer) => (s.layers ?? []).filter((l) => l.layer === layer);

export function analyzeLane(dir, { strips = 'changed', emit = () => {} } = {}) {
  const man = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
  const { frame, dpr, engine } = man;
  const cells = [], skipped = [], frames = [];
  const armA = man.samples.A, armA2 = man.samples.A2;
  if (!armA || !armA2) throw new Error('manifest lacks arm A or A2');
  const firstStrip = new Set();
  const armsB = [['A2', null], ...man.layers.filter((l) => man.samples[`P:${l}`]).map((l) => [`P:${l}`, l])];
  const cache = new Map();
  const load = (f) => { if (!cache.has(f)) cache.set(f, loadImg(dir, f)); return cache.get(f); };
  for (let i = 0; i < man.offsets.length; i++) {
    cache.clear();
    for (const [armB, only] of armsB) {
      if (armA[i] && man.samples[armB][i]) {
        const fa = [load(armA[i].files[0]), load(armA[i].files[1])], fb = [load(man.samples[armB][i].files[0]), load(man.samples[armB][i].files[1])];
        if (fa[0].w === frame.w && fb[0].w === frame.w) {
          const fdel = deltas(fa[0], fb[0]), fd = frameDiff(fdel, frame.w);
          frames.push({ arm: armB, i, y: armA[i].scrollY, sameA: sameImage(fa[0], fa[1]), sameB: sameImage(fb[0], fb[1]), ...fd });
          if (armB === 'A2' && strips !== 'none' && fd.changed) emit(`strips/FRAME_${armB}_${i}.png`, encodePng(thumb(fa[0], fb[0], fdel)));
        }
      }
      for (const layer of only ? [only] : man.layers) {
        const sa = armA[i], sb = man.samples[armB][i];
        const box = sa?.boxes?.[layer];
        const kind = only ? 'P' : 'A/A';
        if (!sa || !box) { skipped.push({ layer, i, kind, why: 'no box (layer not rendered)' }); continue; }
        const m = mask(dpr, frame.w, frame.h, box);
        if (maskEmpty(m)) { skipped.push({ layer, i, kind, why: 'off screen at this offset' }); continue; }
        if (!sb) { skipped.push({ layer, i, kind, why: 'not captured (the arm stopped early)' }); continue; }
        const [a0, a1, b0, b1] = [load(sa.files[0]), load(sa.files[1]), load(sb.files[0]), load(sb.files[1])];
        if (a0.w !== frame.w || a0.h !== frame.h || b0.w !== frame.w || b0.h !== frame.h) throw new Error(`capture size ${a0.w}x${a0.h} / ${b0.w}x${b0.h} is not the frame ${frame.w}x${frame.h}`);
        const del = deltas(a0, b0);
        const { inside, out, hist } = split(del, frame.w, m);
        const ra = recs(sa, layer), rb = recs(sb, layer);
        const compA = ra.length > 0, compB = rb.length > 0;
        const p1 = compA && compB && sig(sa) === sig(sb);
        const cell = {
          run: man.run, engine, lossless: man.lossless,
          claim: { props: [], scales: false, text: false, snap: false, compA, compB, bound: null },
          sameA: sameImage(a0, a1), sameB: sameImage(b0, b1), out, inside, control: null, p1,
          origin: [microRat(box[0]), microRat(box[1])], dpr, t1: null, stripsAccepted: false,
        };
        const rec = { layer, i, y: sa.scrollY, kind, mask: m, boxSame: JSON.stringify(sb.boxes?.[layer] ?? null) === JSON.stringify(box), cell, grade: grade(cell), premises: premises(engine, cell.claim), s1: cellS1(cell), hist };
        const changed = inside.changed + out.changed > 0;
        const key = `${kind}:${layer}`;
        if (strips === 'all' || (strips === 'changed' && (changed || !firstStrip.has(key)))) {
          firstStrip.add(key);
          rec.strip = `strips/${kind === 'P' ? 'P' : 'AA'}_${layer.replace(/[^\w.-]/g, '_')}_${i}.png`;
          emit(rec.strip, encodePng(strip(a0, b0, del, m)));
        }
        cells.push(rec);
      }
    }
  }
  return { schema: 'fw.path-pix.cells/1', engine, run: man.run, lane: man.lane, compositing: man.compositing, dpr, frame, maxY: man.maxY, offsets: man.offsets, layers: man.layers, pLayers: man.pLayers ?? man.layers, cut: man.cut ?? [], cells, skipped, frames };
}

export function table(res) {
  const out = [`### path-pix ${res.lane ?? res.engine} (run ${res.run}, ${res.compositing ?? '?'} compositing)`, ''];
  const kinds = ['A/A', 'P'];
  out.push('| kind | cells | E | E1 | Q | L | invalid | cells with inside change | max inside delta | max outside delta |', '|---|---|---|---|---|---|---|---|---|---|');
  for (const k of kinds) {
    const cs = res.cells.filter((c) => c.kind === k);
    const n = (g) => cs.filter((c) => c.grade === g).length;
    out.push(`| ${k} | ${cs.length} | ${n('E')} | ${n('E1')} | ${n('Q')} | ${n('L')} | ${n('invalid')} | ${cs.filter((c) => c.cell.inside.changed > 0).length} | ${Math.max(0, ...cs.map((c) => c.cell.inside.maxDelta))} | ${Math.max(0, ...cs.map((c) => c.cell.out.maxDelta))} |`);
  }
  out.push('', '| layer | kind | offsets in view | grades | inside changed (sum) | inside max delta | outside changed (sum) | outside max delta | P1 witnessed | not equal across loads (sameA/sameB false) |', '|---|---|---|---|---|---|---|---|---|---|');
  for (const l of res.layers) for (const k of kinds) {
    const cs = res.cells.filter((c) => c.layer === l && c.kind === k);
    if (!cs.length) continue;
    const g = {}; for (const c of cs) g[c.grade] = (g[c.grade] ?? 0) + 1;
    const sum = (f) => cs.reduce((s, c) => s + f(c), 0);
    out.push(`| ${l} | ${k} | ${cs.length} | ${Object.entries(g).map(([a, b]) => `${a}:${b}`).join(' ')} | ${sum((c) => c.cell.inside.changed)} | ${Math.max(...cs.map((c) => c.cell.inside.maxDelta))} | ${sum((c) => c.cell.out.changed)} | ${Math.max(...cs.map((c) => c.cell.out.maxDelta))} | ${cs.filter((c) => c.cell.p1).length}/${cs.length} | ${cs.filter((c) => !c.cell.sameA || !c.cell.sameB).length} |`);
  }
  if (res.cut?.length) out.push('', `arms cut short: ${res.cut.join('; ')}`);
  out.push('', `skipped cells: ${res.skipped.length} (${[...new Set(res.skipped.map((s) => s.why))].join('; ')})`);
  return out.join('\n');
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  const args = process.argv.slice(2);
  const dir = args.find((a) => !a.startsWith('--'));
  const opt = (k, d) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] : d; };
  if (!dir) { console.error('usage: node src/pathpix-analyze.mjs <laneDir> [--strips all|changed|none] [--out <dir>]'); process.exit(2); }
  const out = resolve(opt('out', dir));
  mkdirSync(join(out, 'strips'), { recursive: true });
  const res = analyzeLane(resolve(dir), { strips: opt('strips', 'changed'), emit: (name, png) => writeFileSync(join(out, name), png) });
  writeFileSync(join(out, 'cells.json'), JSON.stringify(res) + '\n');
  const md = table(res);
  writeFileSync(join(out, 'summary.md'), md + '\n');
  console.log(md);
}
