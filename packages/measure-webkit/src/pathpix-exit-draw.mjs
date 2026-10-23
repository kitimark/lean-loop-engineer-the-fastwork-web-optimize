import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { decodePng, encodePng } from './pathpix-png.mjs';
import { deltas, frameDiff, split, strip } from './pathpix-analyze.mjs';
import { drawOf, drawWorst, drawTimes } from './pathpix-exit.mjs';

export const DRAW_ARMS = ['N', 'F'];
export const DRAW_PHASES = ['out', 'in'];
export const drawFile = (arm, phase, k) => `shots/${arm}_${phase}_${k}.png`;

/** Device-pixel band (x0, x1, y0, y1) around the faithful word's boxes of one frame, padded by `pad` css px. */
export function drawBand(rects, dpr, w, h, pad = 8) {
  const rs = rects.filter(Boolean);
  if (!rs.length) return null;
  const x0 = Math.min(...rs.map((r) => r[0])), y0 = Math.min(...rs.map((r) => r[1]));
  const x1 = Math.max(...rs.map((r) => r[0] + r[2])), y1 = Math.max(...rs.map((r) => r[1] + r[3]));
  const c = (v, hi) => Math.max(0, Math.min(hi, v));
  return [c(Math.floor((x0 - pad) * dpr), w), c(Math.ceil((x1 + pad) * dpr), w), c(Math.floor((y0 - pad) * dpr), h), c(Math.ceil((y1 + pad) * dpr), h)];
}

const cell = (a, b, band, w) => {
  const del = deltas(a, b);
  const all = frameDiff(del, w);
  const s = band ? split(del, w, band) : null;
  return { del, raw: { changed: all.changed, maxDelta: all.maxDelta }, bbox: all.bbox, band: s ? s.inside : null, rest: s ? s.out : null };
};

/** Replays the draw frames of one lane directory: each arm against faithful, read against faithful against faithful (A2). */
export function analyzeDraw(dir, { strips = 'changed', emit = () => {} } = {}) {
  const man = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
  const { frame, dpr } = man;
  const load = (arm, phase, k) => {
    const row = man.samples?.[arm]?.[phase]?.[k];
    return row?.file ? { row, img: decodePng(readFileSync(join(dir, row.file))) } : null;
  };
  const frames = [];
  const times = man.times ?? drawTimes();
  for (const phase of DRAW_PHASES) {
    for (let k = 0; k < times.length; k++) {
      const a = load('A', phase, k), a2 = load('A2', phase, k);
      const rec = { phase, k, t: times[k], floor: null, arms: {}, unstable: [] };
      if (!a || !a2) { rec.missing = !a ? 'A' : 'A2'; frames.push(rec); continue; }
      const rects = ['A', 'A2'].map((n) => (n === 'A' ? a : a2).row.rect);
      const others = DRAW_ARMS.map((n) => load(n, phase, k));
      const band = drawBand([...rects, ...others.map((o) => o?.row.rect)], dpr, frame.w, frame.h);
      rec.band = band;
      const fl = cell(a.img, a2.img, band, frame.w);
      rec.floor = { ...fl.raw, bbox: fl.bbox, band: fl.band, rest: fl.rest };
      for (const arm of [['A', a], ['A2', a2], ...DRAW_ARMS.map((n, i) => [n, others[i]])]) if (arm[1] && arm[1].row.stable === false) rec.unstable.push(arm[0]);
      DRAW_ARMS.forEach((n, i) => {
        const o = others[i];
        if (!o) { rec.arms[n] = { missing: true }; return; }
        const c = cell(a.img, o.img, band, frame.w);
        const draw = drawOf(rec.floor, c.raw);
        rec.arms[n] = { ...c.raw, bbox: c.bbox, band: c.band, rest: c.rest, draw, kinds: o.row.kinds, anims: o.row.n };
        if (strips !== 'none' && band && (strips === 'all' || c.raw.changed)) {
          const m = [band[0], band[1], band[2], band[3]];
          emit(`strips/draw_${n}_${phase}_${k}.png`, encodePng(strip(a.img, o.img, c.del, m, { pad: 0, maxH: 400 })));
        }
      });
      frames.push(rec);
    }
  }
  const worst = {};
  const worstBy = {};
  for (const n of DRAW_ARMS) {
    const ds = frames.filter((f) => f.arms[n] && !f.arms[n].missing).map((f) => f.arms[n].draw);
    const read = (xs) => (xs.length ? drawWorst(xs) : 'missing');
    worst[n] = read(ds);
    worstBy[n] = Object.fromEntries(DRAW_PHASES.map((p) => [p, read(frames.filter((f) => f.phase === p && f.arms[n] && !f.arms[n].missing).map((f) => f.arms[n].draw))]));
  }
  const missing = frames.filter((f) => f.missing || DRAW_ARMS.some((n) => f.arms[n]?.missing)).length;
  const floorMax = frames.reduce((m, f) => (f.floor ? { changed: Math.max(m.changed, f.floor.changed), maxDelta: Math.max(m.maxDelta, f.floor.maxDelta) } : m), { changed: 0, maxDelta: 0 });
  return { mode: 'draw', run: man.run, engine: man.engine, flags: man.flags, dpr, frame, times, frames, worst, worstBy, floorMax, missing, cut: man.cut ?? [] };
}

const px = (r) => (r ? `${r.changed} (max ${r.maxDelta})` : 'n/a');

export function drawTable(res) {
  const L = [];
  L.push(`## Draw window (${res.engine}, run ${res.run}): arm against faithful at seeked times, floor = faithful against faithful`);
  L.push('');
  L.push(`flags: ${DRAW_ARMS.map((n) => `${n} = ${res.flags?.[n] ?? '?'}`).join(', ')}; frame ${res.frame.w}x${res.frame.h} device px; missing frames: ${res.missing}`);
  L.push('');
  L.push(`| phase | t ms | floor changed (max) | ${DRAW_ARMS.map((n) => `${n} changed (max) | ${n} in band | ${n} outside band | ${n} read`).join(' | ')} |`);
  L.push(`|---|---|---|${DRAW_ARMS.map(() => '---|---|---|---').join('|')}|`);
  for (const f of res.frames) {
    if (!f.floor) { L.push(`| ${f.phase} | ${f.t} | missing ${f.missing} | ${DRAW_ARMS.map(() => ' | | | ').join('|')}|`); continue; }
    const cols = DRAW_ARMS.map((n) => {
      const a = f.arms[n];
      return !a || a.missing ? 'missing | | | ' : `${px(a)} | ${a.band ? a.band.changed : 'n/a'} | ${a.rest ? a.rest.changed : 'n/a'} | ${a.draw}`;
    });
    L.push(`| ${f.phase} | ${f.t} | ${px(f.floor)}${f.unstable.length ? ` unstable ${f.unstable.join('+')}` : ''} | ${cols.join(' | ')} |`);
  }
  L.push('');
  for (const n of DRAW_ARMS) L.push(`- ${n}: worst frame ${res.worst[n]} (out ${res.worstBy[n].out}, in ${res.worstBy[n].in})`);
  if (res.cut.length) L.push(`- cut: ${res.cut.join('; ')}`);
  return L.join('\n');
}
