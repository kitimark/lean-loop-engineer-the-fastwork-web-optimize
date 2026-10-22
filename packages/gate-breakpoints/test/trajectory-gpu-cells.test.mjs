// The page-side readings of the GPU cells (src/trajectory/cells-gpu.mjs) on synthetic raw artifacts: a run against itself (A/A) is
// E, a panel clock one frame behind is Q, two frames behind is L, a clipped border box reads as its clip, and the pain and
// carousel cells grade a flip one step late and a moved avatar. The grades themselves are Lean's (trajectory-gpu.test.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MORPH_NODES, GPU_NODES, GPU_CELLS } from '../src/trajectory/registry.mjs';
import { cellsOfRaw, layoutOf, swapsOf, tally, ratOf, ratStr, effectAt, painCell, carouselCell, navShapeOf } from '../src/trajectory/cells-gpu.mjs';
import { reduceCells } from '../src/trajectory/cells-gpu-cli.mjs';

const q = (x) => Math.round(x * 1000);
const gpu = layoutOf(GPU_NODES);
const std = layoutOf(MORPH_NODES);

/** One sampled frame: the nav as [rect, radius, clip] and the panel from the faithful effect at `pm` (its own clock). */
const row = (layout, m, rep, { rect = [100 - 50 * m, 10, 200 + 400 * m, 60], radius = 30, clip = 'none', pm = m } = {}) => {
  const nav = Array(Object.keys(layout.nav).length).fill(null);
  nav[layout.nav.rect] = rect.map(q);
  nav[layout.nav['border-radius']] = [q(radius)];
  if (layout.nav['clip-path'] !== undefined) nav[layout.nav['clip-path']] = clip;
  const [op, blur, scale] = effectAt(ratOf(`${Math.round(pm * 10000)}/10000`)).map((r) => Number(r.n) / Number(r.d));
  const panel = Array(Object.keys(layout.panel).length).fill(null);
  panel[layout.panel.opacity] = [q(op)];
  panel[layout.panel['filter.num']] = [q(blur)];
  panel[layout.panel['transform.lin']] = [q(scale), 0, 0, 0, q(scale), 0, 0, 0, q(1)];
  return { tag: 'open', m: Math.round(m * 10000), rep, nodes: { nav: [nav], panel: [panel] } };
};

/** Three reps of 21 frames 0.05 apart, each offset by a hundredth of a morph step, as the pooled reps of a push are. */
const phase = (layout, fn = {}) => [0, 1, 2].flatMap((rep) => Array.from({ length: 21 }, (_, i) => {
  const m = Math.min(1, i * 0.05 + rep * 0.01);
  return row(layout, m, rep, fn.row ? fn.row(m, i, rep) : {});
}));

const raw = (layout, base, cand, extra = {}) => ({
  engine: 'chromium', search: '', hash: 'h', baseHash: 'h', layout,
  runs: [
    { width: 390, site: 'rewrite', role: 'base', morph: { phases: { open: base, close: base } }, ...extra.base },
    { width: 390, site: 'rewrite', role: 'cand', morph: { phases: { open: cand, close: cand } }, ...extra.cand },
  ],
});

const grades = (units, cell) => units.filter((u) => u.cell === cell).map((u) => u.grade);

test('a run against itself grades E for the nav clip and the panel effect', () => {
  const p = phase(std);
  const units = cellsOfRaw(raw(std, p, p), MORPH_NODES);
  assert.deepEqual(grades(units, 'nav-clip'), ['E', 'E']);
  assert.deepEqual(grades(units, 'panel-effect'), ['E', 'E']);
});

test('a settling tail clamped at m 0 does not make a run against itself L', () => {
  const tail = (shift) => phase(std, { row: (m, i) => ({ rect: [100 - 50 * m + (m < 0.01 ? shift + i : 0), 10, 200 + 400 * m, 60] }) });
  const units = cellsOfRaw(raw(std, tail(0), tail(7)), MORPH_NODES);
  assert.deepEqual(grades(units, 'nav-clip'), ['E', 'E']);
});

test('a panel clock one frame behind is Q, two frames behind is L', () => {
  const base = phase(gpu);
  const behind = (k) => phase(gpu, { row: (m) => ({ pm: Math.max(0, m - 0.05 * k) }) });
  const one = cellsOfRaw(raw(gpu, base, behind(1)));
  const two = cellsOfRaw(raw(gpu, base, behind(2)));
  assert.deepEqual(grades(one, 'panel-effect'), ['Q', 'Q']);
  assert.deepEqual(grades(two, 'panel-effect'), ['L', 'L']);
});

test('a clipped border box reads as its clip, and a different clip is L', () => {
  const base = phase(gpu);
  const clipped = phase(gpu, { row: (m) => ({ rect: [90 - 50 * m, 0, 220 + 400 * m, 80], radius: 0, clip: 'inset(10px 10px round 30px)' }) });
  const moved = phase(gpu, { row: (m) => ({ rect: [90 - 50 * m, 0, 220 + 400 * m, 80], radius: 0, clip: 'inset(10px 20px round 30px)' }) });
  const r = (c) => ({ ...raw(gpu, base, c), hash: 'other' });
  assert.deepEqual(grades(cellsOfRaw(r(clipped)), 'nav-clip'), ['E', 'E']);
  assert.deepEqual(grades(cellsOfRaw(r(moved)), 'nav-clip'), ['L', 'L']);
});

test('a candidate of another config cannot be graded on a nav reading without clip-path', () => {
  const p = phase(std);
  const units = cellsOfRaw({ ...raw(std, p, p), hash: 'other' }, MORPH_NODES);
  assert.deepEqual(grades(units, 'nav-clip'), [null, null]);
  assert.match(units.find((u) => u.cell === 'nav-clip').note, /clip-path/);
});

test('a nav row reads as its shape vector; unreadable rows read as none', () => {
  const r = row(gpu, 0.5, 0, { rect: [0, 0, 100, 40], radius: 20, clip: 'inset(0px 10px round 16px)' });
  assert.deepEqual(navShapeOf(r, gpu).map(ratStr), ['10/1', '0/1', '80/1', '40/1', '16/1']);
  assert.equal(navShapeOf({ nodes: {} }, gpu), null);
});

test('pain: a flip one scroll step late is Q, two steps late is L, a base that never flips has no grade', () => {
  const flip = (at, n = 20) => Array.from({ length: n }, (_, i) => ({ y: i, layer: null, cls: i >= at }));
  const mk = (at) => ({ down: flip(at), up: flip(at).reverse() });
  assert.deepEqual(painCell(mk(8), mk(8)), ['E', 'E']);
  assert.deepEqual(painCell(mk(8), mk(9)), ['Q', 'Q']);
  assert.deepEqual(painCell(mk(8), mk(10)), ['L', 'L']);
  assert.deepEqual(painCell(mk(99), mk(8)), [null, null]);
  const units = cellsOfRaw(raw(std, [], [], { base: { pain: mk(8) }, cand: { pain: mk(9) } }), MORPH_NODES);
  assert.deepEqual(grades(units, 'pain-dark'), ['Q']);
});

test('carousel: swaps are cut out of the series and graded at the swap clock', () => {
  const rows = (vals) => vals.map((v, i) => ({ t: i * 16.7, v }));
  const still = Array(10).fill([0, 0, 1000, 1000]);
  const a = rows([[0, 0, 1000, 1000], ...still, [5000, 0, 1000, 1000], [30000, 0, 1000, 1000], ...Array(10).fill([40000, 0, 1000, 1000])]);
  assert.equal(swapsOf(a).length, 1);
  assert.deepEqual(carouselCell(390, a, a).grades, ['E']);
  const moved = rows([[0, 0, 1000, 1000], ...still, [5000, 0, 1000, 1000], [30000, 0, 1000, 1000], ...Array(10).fill([45000, 0, 1000, 1000])]);
  assert.deepEqual(carouselCell(390, a, moved).grades, ['L']);
  assert.equal(carouselCell(390, a, rows(still)).swaps[1], 0);
});

test('carousel: the key is the frame count and only full-count vectors compare (rAF jitter and the entering avatar are not motion)', () => {
  const rest = [0, 0, 1000, 1000], mid = (i) => [5000 * i, 0, 1000, 1000, 0, 0, 1000, 1000];
  const series = (ts) => [...Array(3).fill(rest), ...ts.map((_, i) => mid(i + 1)), ...Array(10).fill(rest)].map((v, i) => ({ t: i < 3 ? i * 16.7 : (ts[i - 3] ?? 99 + i), v }));
  const a = series([100, 116.7, 133.4, 150.1]), jit = series([100, 115.1, 133.3, 149.9]);
  assert.equal(swapsOf(a).length, 1);
  assert.ok(swapsOf(a)[0].every((p) => p.v.length === 8));
  assert.deepEqual(carouselCell(390, a, jit).grades, ['E']);
});

test('carousel: a recording that opens mid-swap has no whole first swap', () => {
  const rest = [0, 0, 1000, 1000], mid = (i) => [5000 * i, 0, 1000, 1000];
  const rows = (vs) => vs.map((v, i) => ({ t: i * 16.7, v }));
  const open = rows([mid(1), mid(2), mid(3), ...Array(8).fill(rest), mid(1), mid(2), ...Array(8).fill(rest)]);
  assert.equal(swapsOf(open).length, 1);
  const whole = rows([...Array(3).fill(rest), mid(1), mid(2), ...Array(8).fill(rest)]);
  assert.equal(swapsOf(whole).length, 1);
});

test('the report counts cells and grades and prints a unit line each', () => {
  const p = phase(std);
  const { units, lines, md } = reduceCells(raw(std, p, p));
  assert.equal(units.length, 4);
  assert.ok(lines.some((l) => l.includes('nav-clip') && l.includes('E 2')));
  assert.match(md, /\| 390 \| panel-effect \| open \| E \|/);
  assert.deepEqual(tally('chromium', []), []);
});

test('the registry names the pain and carousel parts of anchors.json', () => {
  assert.equal(GPU_CELLS.pain.cls, 'is-pain-dark');
  assert.ok(GPU_CELLS.pain.maxWidth <= 860 && GPU_CELLS.carousel.sampleMs > 0);
  assert.ok(GPU_NODES.find((n) => n.id === 'nav').props.some((pr) => pr.id === 'clip-path'));
  assert.ok(!MORPH_NODES.find((n) => n.id === 'nav').props.some((pr) => pr.id === 'clip-path'));
});
