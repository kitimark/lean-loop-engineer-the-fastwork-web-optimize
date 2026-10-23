import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { decodePng, encodePng, sameImage } from './pathpix-png.mjs';
import { analyzeLane, table, deltas, frameDiff, strip, thumb, microRat } from './pathpix-analyze.mjs';
import { mask, maskEmpty, inMask, grade, premises, cellS1, cellValid, textHold } from './pathpix.mjs';

export const exitOffsets = (T, n) => [T, T + 1, T + Math.floor(n / 4), T + Math.floor(n / 2), T + Math.floor((n * 19) / 20), T + Math.floor((n * 19) / 20) + 1, T + n - 1, T + n, T + n + 1];

export function exitClaim(layer, le600) {
  const mk = (props) => ({ props, scales: false, text: true, snap: false, compA: false, compB: false, bound: null });
  if (layer === 'hero_copy') return mk(le600 ? ['opacity', 'transform'] : ['opacity', 'transform', 'filter']);
  if (layer === 'hero.cue_cue') return mk(le600 ? ['opacity', 'transform', 'filter'] : ['opacity', 'filter']);
  if (layer === 'hero.orbit_card' || layer === 'hero.deck_article') return mk(['opacity', 'translate']);
  return null;
}

// Twins of Lean `Fw.Gate.PathPix` (golden kinds accentPin, accentRow, accentGrade, cover, pinRegion).
export const armPin = () => 'accent-hook';
/** The capture sets the site's hook (`?fwpin=accent`, hero.accent/hook.ts) on every exit arm; `search` is the arm's other query. */
export const hookSearch = (search) => (search ? `${search}&fwpin=accent` : '?fwpin=accent');
export const pinAt = (arm, _i) => armPin(arm);
export const shownAccent = (pin, live) => (pin === 'accent-hook' ? { cursor: -1, phase: 'idle' } : live);
export const pinMasks = (_pin, ms) => ms;

export const accentPinned = (served, start, stop, n) => n === 1 && start === served && stop === served;
export const accentRowOf = (row) => {
  const a = row?.accent;
  const at = { y: Number.isFinite(row?.y) ? row.y : -1, scrollY: Number.isFinite(row?.scrollY) ? row.scrollY : -1 };
  if (!a?.shotStart || !a?.shotEnd) return { n: 0, start: null, stop: null, ...at };
  const sig = (x) => (typeof x === 'string' && x ? x : null);
  return { n: a.shotStart.n === a.shotEnd.n ? a.shotStart.n : 0, start: sig(a.shotStart.sig), stop: sig(a.shotEnd.sig), ...at };
};
export const rowsPinned = (served, rows) => rows.every((r) => accentPinned(served, r.start, r.stop, r.n));
export const rowPlaced = (maxY, r) => r.scrollY === Math.min(r.y, maxY);
export const rowsPlaced = (maxY, rows) => rows.every((r) => rowPlaced(maxY, r));
export const rowsOk = (served, maxY, rows) => rowsPinned(served, rows) && rowsPlaced(maxY, rows);
export const checkedRows = (rows, floorRows, f) => (f ? [...rows, ...floorRows] : rows);
export const gradePinned = (served, maxY, rows, floorRows, c, f, live) => (rowsOk(served, maxY, checkedRows(rows, floorRows, f)) ? gradeRel(c, f, live) : 'invalid');
export const unpinnedWhy = (served, maxY, rows, floorRows, f) => {
  const rs = checkedRows(rows, floorRows, f);
  return rowsPinned(served, rs) ? (rowsPlaced(maxY, rs) ? null : 'misplaced') : 'accent-unpinned';
};
export const floorPinned = (served, maxY, rows, f) => ({ ...f, valid: f.valid && rowsOk(served, maxY, rows) });

// Lean `Cover.all`, `occludedBoth`: every grid point of a layer is behind opaque foreign content, in both arms.
export const coverAll = (c) => !!c && c.n > 0 && c.k === c.n;
export const occludedBoth = (a, b) => coverAll(a) && coverAll(b);

export const rawLe = (a, b) => a.changed <= b.changed && a.maxDelta <= b.maxDelta;
export const floorOf = (c) => ({ valid: cellValid(c), out: c.out, inside: c.inside });
export const withinFloor = (c, f) => f.valid && rawLe(c.out, f.out) && rawLe(c.inside, f.inside);

export function gradeRel(c, f, live) {
  if (!live) return 'invalid';
  const g = grade(c);
  if (g !== 'L') return g;
  return !textHold(c) && f && withinFloor(c, f) ? 'Q' : 'L';
}

export function whyL(c, f, live) {
  if (gradeRel(c, f, live) !== 'L') return null;
  return c.out.changed !== 0 ? 'outside' : textHold(c) ? 'text' : 'inside';
}

export const region = (ms, m, x, y) => (inMask(m, x, y) ? 'inside' : ms.some((k) => inMask(k, x, y)) ? 'other' : 'out');

const bucket = (d) => (d === 1 ? 'b1' : d <= 3 ? 'b2_3' : d <= 15 ? 'b4_15' : 'b16_255');

export function splitUnion(del, w, h, masks) {
  const cover = new Uint8Array(w * h);
  for (const m of masks) for (let y = m[2]; y < m[3]; y++) cover.fill(1, y * w + m[0], y * w + m[1]);
  let oc = 0, om = 0;
  for (let i = 0; i < del.length; i++) if (!cover[i]) { const d = del[i]; if (d) { oc++; if (d > om) om = d; } }
  const inside = masks.map((m) => {
    let changed = 0, maxDelta = 0;
    const hist = { b1: 0, b2_3: 0, b4_15: 0, b16_255: 0 };
    let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
    for (let y = m[2]; y < m[3]; y++) for (let x = m[0]; x < m[1]; x++) {
      const d = del[y * w + x];
      if (d) { changed++; if (d > maxDelta) maxDelta = d; hist[bucket(d)]++; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    }
    return { raw: { changed, maxDelta }, hist, bbox: changed ? [x0, y0, x1 + 1, y1 + 1] : null };
  });
  return { out: { changed: oc, maxDelta: om }, inside };
}

// Names of the parts (capture-side rects in css px) that a changed device-pixel box [x0, y0, x1, y1] touches.
export const partsHit = (parts, bbox, dpr) => (!bbox || !parts ? [] : parts.filter(([, x, y, w, h]) => x * dpr < bbox[2] && (x + w) * dpr > bbox[0] && y * dpr < bbox[3] && (y + h) * dpr > bbox[1]).map((p) => p[0]));

const baseLayer = (key) => key.replace(/#\d+$/, '');
const recs = (s, layer) => (s.layers ?? []).filter((l) => l.layer === layer);
const sigOf = (s, layer) => JSON.stringify(recs(s, layer).map((l) => [l.layer, l.boundsU, l.memory ?? null]).sort());
const safe = (s) => s.replace(/[^\w.-]/g, '_');

export const liveP = (l) => !!l && l.live === true && l.variant === 'threaded' && l.supported === true && l.nonDoc > 0;
export const liveA = (l) => !l || (l.variant !== 'threaded' && l.live !== true);

export function driverMoved(rows, exit) {
  const first = rows.find((r) => r && r.y === 0) ?? rows.find(Boolean);
  if (!first) return false;
  const key = Object.keys(first.boxes ?? {}).find((k) => k.startsWith('hero_copy')) ?? Object.keys(first.boxes ?? {})[0];
  if (!key) return false;
  return rows.some((r) => r && r.y > exit.T && r.y <= exit.T + exit.n && r.boxes?.[key] && JSON.stringify(r.boxes[key]) !== JSON.stringify(first.boxes[key]));
}

export function analyzeExit(dir, { strips = 'changed', emit = () => {} } = {}) {
  const man = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
  if (man.mode !== 'exit') throw new Error('manifest is not an exit lane');
  const { frame, dpr, engine } = man;
  const S = man.samples;
  if (!S.A || !S.A2) throw new Error('manifest lacks arm A or A2');
  const le600 = man.vw <= 600;
  const cells = [], skipped = [], frames = [], liveness = [];
  const moved = driverMoved(S.A, man.exit);
  const floors = new Map();
  const served = typeof man.handover?.pin?.A?.ssr === 'string' && man.handover.pin.A.ssr ? man.handover.pin.A.ssr : undefined;
  const maxY = Number.isFinite(man.maxY) ? man.maxY : Number.MAX_SAFE_INTEGER;
  const clockSeen = new Set();
  const firstStrip = new Set();
  const cache = new Map();
  const load = (f) => { if (!cache.has(f)) cache.set(f, decodePng(readFileSync(join(dir, f)))); return cache.get(f); };
  for (let i = 0; i < man.offsets.length; i++) {
    cache.clear();
    const rowA = S.A[i];
    if (!rowA) { skipped.push({ i, kind: 'all', why: 'arm A not captured at this offset' }); continue; }
    for (const r of [rowA, S.A2[i], S.P?.[i]]) if (r && Number.isFinite(r.dateNow)) clockSeen.add(r.dateNow);
    const keys = [], masks = [];
    for (const k of Object.keys(rowA.boxes ?? {}).sort()) {
      const m = mask(dpr, frame.w, frame.h, rowA.boxes[k]);
      if (maskEmpty(m)) { skipped.push({ key: k, i, kind: 'all', why: 'off screen at this offset' }); continue; }
      keys.push(k); masks.push(m);
    }
    for (const [kind, armB, row] of [['A/A', 'A2', S.A2[i]], ['P', 'P', S.P?.[i]]]) {
      if (!row) { for (const k of keys) skipped.push({ key: k, i, kind, why: `arm ${armB} not captured at this offset` }); continue; }
      const [a0, a1, b0, b1] = [load(rowA.files[0]), load(rowA.files[1]), load(row.files[0]), load(row.files[1])];
      if (a0.w !== frame.w || a0.h !== frame.h || b0.w !== frame.w || b0.h !== frame.h) throw new Error(`capture size ${a0.w}x${a0.h} / ${b0.w}x${b0.h} is not the frame ${frame.w}x${frame.h}`);
      const del = deltas(a0, b0);
      const fd = frameDiff(del, frame.w);
      frames.push({ arm: armB, i, y: rowA.scrollY, sameA: sameImage(a0, a1), sameB: sameImage(b0, b1), ...fd });
      if (kind === 'P' && strips !== 'none' && fd.changed) emit(`strips/FRAME_P_${i}.png`, encodePng(thumb(a0, b0, del)));
      const live = moved && (kind === 'P' ? liveP(row.live) : liveA(rowA.live) && liveA(row.live));
      const accentRows = [accentRowOf(rowA), accentRowOf(row)];
      const pinned = rowsOk(served, maxY, accentRows);
      liveness.push({ arm: armB, i, y: row.scrollY, live: row.live ?? null, accepted: live, accentPinned: pinned });
      const sp = splitUnion(del, frame.w, frame.h, masks);
      keys.forEach((key, n) => {
        const box = rowA.boxes[key], layer = baseLayer(key), claim0 = exitClaim(layer, le600);
        if (!claim0) { skipped.push({ key, i, kind, why: 'not an exit consumer' }); return; }
        if ((rowA.alpha?.[key] ?? 1) < 1 / 255 && (row.alpha?.[key] ?? 1) < 1 / 255) { skipped.push({ key, i, kind, why: 'transparent in both arms' }); return; }
        if (occludedBoth(rowA.cover?.[key], row.cover?.[key])) { skipped.push({ key, i, kind, why: 'occluded by opaque foreign content in both arms' }); return; }
        const compA = recs(rowA, layer).length > 0, compB = recs(row, layer).length > 0;
        const p1 = compA && compB && sigOf(rowA, layer) === sigOf(row, layer);
        const cell = {
          run: man.run, engine, lossless: man.lossless,
          claim: { ...claim0, compA, compB },
          sameA: sameImage(a0, a1), sameB: sameImage(b0, b1), out: sp.out, inside: sp.inside[n].raw, control: null, p1,
          origin: [microRat(box[0]), microRat(box[1])], dpr, t1: null, stripsAccepted: false,
        };
        const fkey = `${key}@${i}`;
        const floorEntry = kind === 'P' ? floors.get(fkey) ?? null : null;
        const floor = floorEntry && floorEntry.floor;
        const floorRows = floorEntry ? floorEntry.rows : [];
        if (kind === 'A/A') floors.set(fkey, { floor: floorPinned(served, maxY, accentRows, floorOf(cell)), rows: accentRows });
        const checked = checkedRows(accentRows, floorRows, floor);
        const ok = rowsOk(served, maxY, checked);
        const rec = {
          key, layer, i, y: rowA.scrollY, kind, mask: masks[n], boxSame: JSON.stringify(row.boxes?.[key] ?? null) === JSON.stringify(box), live,
          cell, floor, accentPinned: ok, invalidWhy: unpinnedWhy(served, maxY, accentRows, floorRows, floor), grade: gradePinned(served, maxY, accentRows, floorRows, cell, floor, live), absGrade: ok ? grade(cell) : 'invalid',
          why: ok ? whyL(cell, floor, live) : null,
          where: { bbox: sp.inside[n].bbox, parts: partsHit(rowA.parts?.[key], sp.inside[n].bbox, dpr) },
          ifAccepted: gradePinned(served, maxY, accentRows, floorRows, { ...cell, stripsAccepted: true }, floor, live), premises: premises(engine, cell.claim), s1: cellS1(cell), hist: sp.inside[n].hist,
        };
        const changed = cell.inside.changed + cell.out.changed > 0;
        const sk = `${kind}:${key}`;
        if (strips === 'all' || (strips === 'changed' && (changed || !firstStrip.has(sk)) && (kind === 'P' || changed))) {
          firstStrip.add(sk);
          rec.strip = `strips/${kind === 'P' ? 'P' : 'AA'}_${safe(key)}_${i}.png`;
          emit(rec.strip, encodePng(strip(a0, b0, del, masks[n])));
        }
        cells.push(rec);
      });
    }
  }
  return {
    schema: 'fw.path-pix.exit/1', engine, run: man.run, lane: man.lane, compositing: man.compositing, flag: man.flag, dpr, vw: man.vw, frame,
    exit: man.exit, offsets: man.offsets, maxY: Number.isFinite(man.maxY) ? man.maxY : null, clock: { values: [...clockSeen].sort((a, b) => a - b), constant: clockSeen.size <= 1 }, driverMoved: moved, cells, skipped, frames, liveness, armsRun: Object.keys(S), cut: man.cut ?? [], fonts: man.fonts ?? null,
  };
}

const sumRaw = (r) => `${r.changed}/${r.maxDelta}`;

export function exitTable(res) {
  const out = [`### path-pix exit ${res.lane ?? res.engine} (run ${res.run}, flag ${res.flag}, ${res.compositing ?? '?'} compositing)`, ''];
  out.push(`exit track: T ${res.exit?.T}, n ${res.exit?.n}, viewport ${res.exit?.v}, offsets ${res.offsets.join(',')}`, '');
  out.push('| kind | cells | E | E1 | Q | L | invalid | L by text | L outside | L inside | if strips accepted: E/E1/Q/L/invalid |', '|---|---|---|---|---|---|---|---|---|---|---|');
  for (const k of ['A/A', 'P']) {
    const cs = res.cells.filter((c) => c.kind === k);
    const n = (g) => cs.filter((c) => c.grade === g).length;
    const w = (x) => cs.filter((c) => c.why === x).length;
    const a = (g) => cs.filter((c) => c.ifAccepted === g).length;
    out.push(`| ${k} | ${cs.length} | ${n('E')} | ${n('E1')} | ${n('Q')} | ${n('L')} | ${n('invalid')} | ${w('text')} | ${w('outside')} | ${w('inside')} | ${a('E')}/${a('E1')}/${a('Q')}/${a('L')}/${a('invalid')} |`);
  }
  out.push('', '| consumer | offset i | y | P grade (why) | if accepted | P inside chg/max | P out chg/max | A/A grade | A/A inside | A/A out | live | strip |', '|---|---|---|---|---|---|---|---|---|---|---|---|');
  const aa = new Map(res.cells.filter((c) => c.kind === 'A/A').map((c) => [`${c.key}@${c.i}`, c]));
  for (const c of res.cells.filter((x) => x.kind === 'P')) {
    const f = aa.get(`${c.key}@${c.i}`);
    out.push(`| ${c.key} | ${c.i} | ${c.y} | ${c.grade}${c.why ? ` (${c.why})` : ''} | ${c.ifAccepted} | ${sumRaw(c.cell.inside)} | ${sumRaw(c.cell.out)} | ${f ? f.grade : '-'} | ${f ? sumRaw(f.cell.inside) : '-'} | ${f ? sumRaw(f.cell.out) : '-'} | ${c.live} | ${c.strip ?? ''} |`);
  }
  out.push('', `faithful driver moved the consumers in arm A: ${res.driverMoved}`);
  out.push('', `cells marked invalid with reason accent-unpinned: ${res.cells.filter((c) => c.invalidWhy === 'accent-unpinned').length} of ${res.cells.length}; misplaced (scrollY is not the offset): ${res.cells.filter((c) => c.invalidWhy === 'misplaced').length}`);
  if (res.clock) out.push(`page Date.now in every row: ${res.clock.constant ? 'constant' : 'moves'} (${res.clock.values.join(', ') || 'not recorded'})`);
  const notLive = res.liveness.filter((l) => l.arm === 'P' && !l.accepted);
  out.push('', `P rows not live: ${notLive.length} of ${res.liveness.filter((l) => l.arm === 'P').length}`);
  if (res.cut?.length) out.push(`arms cut short: ${res.cut.join('; ')}`);
  out.push(`skipped cells: ${res.skipped.length} (${[...new Set(res.skipped.map((s) => s.why))].join('; ')})`);
  return out.join('\n');
}

export function analyzeDir(dir, opts) {
  const man = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
  if (man.mode === 'exit') { const res = analyzeExit(dir, opts); return { res, md: exitTable(res) }; }
  const res = analyzeLane(dir, opts);
  return { res, md: table(res) };
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  const args = process.argv.slice(2);
  const dir = args.find((a) => !a.startsWith('--'));
  const opt = (k, d) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] : d; };
  if (!dir) { console.error('usage: node src/pathpix-exit.mjs <laneDir> [--strips all|changed|none] [--out <dir>]'); process.exit(2); }
  const out = resolve(opt('out', dir));
  mkdirSync(join(out, 'strips'), { recursive: true });
  const res = analyzeExit(resolve(dir), { strips: opt('strips', 'changed'), emit: (name, png) => writeFileSync(join(out, name), png) });
  writeFileSync(join(out, 'cells.json'), JSON.stringify(res) + '\n');
  const md = exitTable(res);
  writeFileSync(join(out, 'summary.md'), md + '\n');
  console.log(md);
}
