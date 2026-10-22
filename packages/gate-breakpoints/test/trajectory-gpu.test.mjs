import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  ratOf, ratStr, tolCss, cellEq, parseDec, parseLen, parseInset, expand4, readShape, shapeVec, interpAt, matchedGrade,
  effectAt, effectTols, cellsOfRaw, seriesOf, keptInterior, effClock, lagFrames, lagGrade, panelGrade, panelCell, darkness, painGrade, rat, ZERO,
  worst, restedBefore, swapSpans, swapSeries, carouselCellAt, painCell, holdFrames,
  settleRun, tailRun, SETTLE_CAP_MS, TAIL_CAP_MS, STILL_FRAMES,
} from '../src/trajectory/cells-gpu.mjs';

const golden = readFileSync(fileURLToPath(new URL('../../contracts/golden/gate/trajectory-gpu.jsonl', import.meta.url)), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => golden.filter((l) => l.kind === k);
const vec = (xs) => xs.map(ratOf);
const vecStr = (xs) => xs.map(ratStr);
const series = (s) => s.map(({ k, v }) => ({ k: ratOf(k), v: vec(v) }));
const lenStr = (l) => `${l.k}:${ratStr(l.v)}`;
const optStr = (r) => (r === null ? null : ratStr(r));

test('the golden file holds every line kind', () => {
  const kinds = new Set(golden.map((l) => l.kind));
  for (const k of ['tol', 'dec', 'len', 'inset', 'expand4', 'clip', 'cell', 'interp', 'matched', 'effect', 'lag', 'panel', 'series', 'panelcell', 'pain', 'dark', 'interior', 'worst', 'rested', 'swaps', 'carousel', 'paincell', 'kinkcell', 'settle', 'tail']) {
    assert.ok(kinds.has(k), k);
  }
});

test('tolerance of half a device pixel in css px', () => {
  for (const l of of('tol')) assert.equal(ratStr(tolCss(ratOf(l.dpr))), l.tol);
});

test('decimal, length and inset readers', () => {
  for (const l of of('dec')) assert.equal(optStr(parseDec(l.s)), l.out, l.s);
  for (const l of of('len')) { const v = parseLen(l.s); assert.equal(v === null ? null : lenStr(v), l.out, l.s); }
  for (const l of of('inset')) {
    const v = parseInset(l.s);
    const got = v === null ? null : { sides: [v.top, v.right, v.bottom, v.left].map(lenStr), radii: v.radii === null ? null : v.radii.map(lenStr) };
    assert.deepEqual(got, l.out, l.s);
  }
  for (const l of of('expand4')) assert.deepEqual(expand4(l.in), l.out);
});

test('the clip rect of an inset on a border box', () => {
  const cases = of('clip');
  assert.ok(cases.length >= 8);
  for (const l of cases) {
    const [x, y, w, h] = vec(l.box);
    const s = readShape({ x, y, w, h }, ratOf(l.radius), l.clip);
    assert.deepEqual(s === null ? null : vecStr(shapeVec(s)), l.out, l.name);
  }
});

test('cell equality within a tolerance per component, length-checked', () => {
  for (const l of of('cell')) assert.equal(cellEq(vec(l.tols), vec(l.a), vec(l.b)), l.eq, JSON.stringify(l));
});

test('interpolation between samples, none outside the keys', () => {
  for (const l of of('interp')) {
    const v = interpAt(series(l.table), ratOf(l.k));
    assert.deepEqual(v === null ? null : vecStr(v), l.out, l.k);
  }
});

test('matched-clock grades E, Q, L and none', () => {
  const cases = of('matched');
  assert.ok(cases.length >= 6);
  for (const l of cases) {
    assert.equal(matchedGrade(vec(l.tols), vec(l.grid), ratOf(l.frameKey), l.minCovered, series(l.ref), series(l.cand)), l.grade, l.name);
  }
});

test('the faithful panel effect, its tolerances and clock', () => {
  for (const l of of('effect')) {
    const m = ratOf(l.m);
    assert.deepEqual(vecStr(effectAt(m)), l.out, l.m);
    assert.equal(ratStr(effClock(effectAt(m)[0])), l.clock);
    assert.deepEqual(vecStr(effectTols(rat(2), rat(600))), l.tols);
  }
});

test('panel lag in frames and the panel cell grade', () => {
  for (const l of of('lag')) {
    const lag = lagFrames(l.frames.map(([nav, op]) => ({ nav: ratOf(nav), op: ratOf(op) })));
    assert.equal(optStr(lag), l.lag, l.name);
    assert.equal(lag === null ? null : lagGrade(lag), l.grade, l.name);
  }
  for (const l of of('panel')) {
    assert.equal(panelGrade(l.series, l.lag === null ? null : ratOf(l.lag), l.shifted), l.grade, l.name);
  }
  const cells = of('panelcell');
  assert.ok(cells.length >= 6);
  for (const l of cells) {
    const c = panelCell(vec(l.tols), l.minCovered, series(l.ref), series(l.frames));
    assert.equal(optStr(c.lag), l.lag, l.name);
    assert.equal(c.grade, l.grade, l.name);
  }
  const grade = (n) => cells.find((l) => l.name === n).grade;
  assert.equal(grade('closing in step'), 'E');
  assert.equal(grade('closing one frame behind'), 'Q');
  assert.equal(grade('closing one frame behind, blur dropped'), 'L');
  assert.equal(grade('in step, stalled frame'), 'E');
  for (const name of ['one frame behind, blur dropped', 'one frame behind, scale dropped', 'in step, blur dropped', 'in step, scale dropped']) {
    assert.equal(cells.find((l) => l.name === name).grade, 'L', name);
  }
});

test('seriesOf sorts by key and keeps the first sample of an equal key, as Lean seriesOf', () => {
  const cases = of('series');
  assert.ok(cases.length >= 6);
  for (const l of cases) {
    const got = seriesOf(series(l.in)).map((p) => ({ k: ratStr(p.k), v: vecStr(p.v) }));
    assert.deepEqual(got, l.out, l.name);
  }
});

test('the interior of the morph keeps only the keys strictly between the edges', () => {
  for (const l of of('interior')) assert.equal(keptInterior(ratOf(l.k)), l.kept, l.k);
});

test('pain darkness and grade', () => {
  for (const l of of('dark')) assert.equal(ratStr(darkness(l.layer === null ? null : ratOf(l.layer), l.class)), l.out);
  const cases = of('pain');
  assert.ok(cases.length >= 8);
  for (const l of cases) assert.equal(painGrade(vec(l.base), vec(l.cand)), l.grade, l.name);
});

test('a division by zero is zero, as in Lean', () => {
  assert.equal(ratStr(effectTols(rat(1), ZERO)[2]), '1/1000');
});

test('a candidate that drops the panel blur or scale grades L on a raw artifact, never Q', () => {
  const thousandths = (r) => Number((r.n * 1000n) / r.d);
  const row = (m, rep, drop) => {
    const [op, blur, scale] = effectAt(rat(BigInt(m), 10000n));
    const e = [0, 0, 0, [thousandths(op)], null, [drop === 'blur' ? 0 : thousandths(blur)], [drop === 'scale' ? 1000 : thousandths(scale)], null];
    return { m, rep, nodes: { panel: [e] } };
  };
  const rowsOf = (step, drop) => Array.from({ length: Math.floor(10000 / step) + 1 }, (_, i) => row(i * step, 0, drop));
  const raw = (drop) => ({
    hash: 'x', baseHash: 'x',
    runs: [{ role: 'base', width: 390, morph: { phases: { open: rowsOf(50, null) } } },
      { role: 'cand', width: 390, morph: { phases: { open: rowsOf(500, drop) } } }],
  });
  const grade = (drop) => cellsOfRaw(raw(drop)).find((u) => u.cell === 'panel-effect' && u.part === 'open').grade;
  assert.equal(grade(null), 'E');
  assert.equal(grade('blur'), 'L');
  assert.equal(grade('scale'), 'L');
});

const rowsOf = (rs) => rs.map((v, i) => ({ t: i, v }));
const seriesStr = (s) => s.map((p) => ({ k: ratStr(p.k), v: vecStr(p.v) }));

test('worst of the reps: none when a rep is not comparable or there are no reps, as Lean worst', () => {
  const cases = of('worst');
  assert.ok(cases.some((l) => l.in.includes(null) && l.in.some((g) => g !== null) && l.out === null));
  for (const l of cases) assert.equal(worst(l.in), l.out, JSON.stringify(l.in));
});

test('restedBefore reads two equal rows before the index, as Lean restedBefore', () => {
  const cases = of('rested');
  assert.ok(cases.length >= 5);
  for (const l of cases) assert.equal(restedBefore(rowsOf(l.rows), l.i), l.out, l.name);
});

test('swap spans and their series at the frame clock, as Lean swapSpans and swapSeries', () => {
  const cases = of('swaps');
  assert.ok(cases.length >= 6);
  for (const l of cases) {
    const rows = rowsOf(l.rows), spans = swapSpans(rows, l.still);
    assert.deepEqual(spans.map(({ from, to }) => [from, to]), l.spans, l.name);
    assert.deepEqual(spans.map((sp) => seriesStr(swapSeries(rows, sp))), l.out, l.name);
    assert.deepEqual(spans.map((sp) => holdFrames(rows, sp)), l.holds, l.name);
  }
  assert.deepEqual(cases.find((l) => l.name === 'an entering avatar held 4 rows').holds, [3]);
  const n = (name) => cases.find((l) => l.name === name).spans.length;
  assert.equal(n('opens at rest'), 2);
  assert.equal(n('opens mid-swap'), 1);
});

test('the carousel cell pairs swaps by order; a count mismatch is L and a null rep makes the unit not comparable, as Lean carouselCell', () => {
  const cases = of('carousel');
  assert.ok(cases.length >= 6);
  for (const l of cases) {
    const c = carouselCellAt(ratOf(l.dpr), rowsOf(l.base), rowsOf(l.cand));
    assert.deepEqual(c.swaps, l.swaps, l.name);
    assert.deepEqual(c.grades, l.reps, l.name);
    assert.equal(c.grade, l.grade, l.name);
  }
  const grade = (name) => cases.find((l) => l.name === name).grade;
  assert.equal(grade('equal swaps in step'), 'E');
  assert.equal(grade('one swap missing'), 'L');
  assert.equal(grade('zero swaps'), 'L');
  assert.equal(grade('a null rep among E reps'), null);
});

test('the pain cell grades each direction, none when its base never flips, as Lean painCell', () => {
  const cases = of('paincell');
  assert.ok(cases.length >= 4);
  const dir = ([b, c]) => ({ b: vec(b), c: vec(c) });
  for (const l of cases) {
    const up = dir(l.up), down = dir(l.down);
    const arm = (k) => ({ up: up[k].map((x) => ({ layer: Number(x.n) / Number(x.d), cls: false })), down: down[k].map((x) => ({ layer: Number(x.n) / Number(x.d), cls: false })) });
    const reps = painCell(arm('b'), arm('c'));
    assert.deepEqual(reps, l.reps, l.name);
    assert.equal(worst(reps), l.grade, l.name);
  }
});

test('a sparse reference against the declared effect grades by residual, as Lean panelCell', () => {
  const cases = of('kinkcell');
  assert.equal(cases.length, 3);
  for (const l of cases) {
    assert.equal(matchedGrade(vec(l.tols), [], ratOf('1/1'), l.minCovered, series(l.ref), series(l.frames)), l.plain, l.name);
    assert.equal(panelCell(vec(l.tols), l.minCovered, series(l.ref), series(l.frames)).grade, l.grade, l.name);
  }
  const grade = (n) => cases.find((l) => l.name === n).grade;
  assert.equal(grade('sparse reference, candidate on the effect'), 'E');
  assert.equal(grade('sparse reference, opacity off by 3/100'), 'L');
});

const timed = (fs) => fs.map(({ t, v }) => ({ t: ratOf(t), v }));

test('the in-page settle rule stops after 6 equal frames once moved, or at the cap, as Lean settleRun', () => {
  const cases = of('settle');
  assert.equal(cases.length, 7);
  assert.equal(STILL_FRAMES, 6);
  assert.equal(ratStr(SETTLE_CAP_MS), '2200/1');
  for (const l of cases) {
    assert.equal(ratStr(SETTLE_CAP_MS), l.cap, l.name);
    const r = settleRun(l.still, SETTLE_CAP_MS, ZERO, l.prev, timed(l.frames));
    assert.deepEqual([r.consumed, r.quiet], [l.consumed, l.quiet], l.name);
  }
  assert.equal(cases.find((l) => l.name === 'the cap ends the wait').quiet, false);
});

test('the tail stops after 6 equal frames past the window or at the cap, as Lean tailRun', () => {
  const cases = of('tail');
  assert.equal(cases.length, 4);
  assert.equal(ratStr(TAIL_CAP_MS), '1500/1');
  for (const l of cases) {
    assert.equal(ratStr(TAIL_CAP_MS), l.cap, l.name);
    const r = tailRun(ratOf(l.ms), l.still, timed(l.frames));
    assert.deepEqual([r.rows, r.quiet], [l.rows, l.quiet], l.name);
  }
});
