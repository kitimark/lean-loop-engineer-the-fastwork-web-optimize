// The node twins of lean/Fw/Gate/TrajectoryGpu.lean (src/trajectory/cells-gpu.mjs) against the vectors Lean generates
// (packages/contracts/golden/gate/trajectory-gpu.jsonl): every line kind, exact rationals.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  ratOf, ratStr, tolCss, cellEq, parseDec, parseLen, parseInset, expand4, readShape, shapeVec, interpAt, matchedGrade,
  effectAt, effectTols, keptInterior, effClock, lagFrames, lagGrade, panelGrade, darkness, painGrade, rat, ZERO,
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
  for (const k of ['tol', 'dec', 'len', 'inset', 'expand4', 'clip', 'cell', 'interp', 'matched', 'effect', 'lag', 'panel', 'pain', 'dark', 'interior']) {
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
    assert.equal(panelGrade(l.series, l.lag === null ? null : ratOf(l.lag)), l.grade, l.name);
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
  assert.equal(ratStr(effectTols(rat(1), ZERO)[2]), '0/1');
});
