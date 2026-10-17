// packages/measure-webkit/src/{reduce,quietsteps}.mjs against fwcore (Fw.Measure.WebKit / Quiet), on random inputs.
import { test, before, after } from 'node:test';
import fc from 'fast-check';
import { FwCore } from '../src/fwcore.mjs';
import { differential, sameKeys } from '../src/diff.mjs';
import { int, half, risingHalves } from '../src/arb.mjs';
import { tally, reduceSteps, zones, classify, symDiff, summarize, COUNT_TYPES } from '../../measure-webkit/src/reduce.mjs';
import { quietReply } from '../../measure-webkit/src/quietsteps.mjs';

let core;
before(() => { core = new FwCore(); });
after(() => core.close());

const type = fc.oneof({ weight: 8, arbitrary: fc.constantFrom(...COUNT_TYPES) },
  { weight: 3, arbitrary: fc.constantFrom('TimeStamp', 'RequestAnimationFrame', 'EvaluateScript', 'Foo') });
const quad = fc.oneof(fc.constant(null), fc.array(half(0, 50), { minLength: 8, maxLength: 8 }), fc.array(half(0, 50), { minLength: 0, maxLength: 9 }));
const row = (start) => fc.tuple(type, start, fc.oneof(fc.constant(null), half(0, 30))).chain(([t, s, e]) =>
  (t === 'Paint' ? quad : t === 'TimeStamp' ? fc.oneof(fc.constant(null), fc.constantFrom('wk:s0', 'x', 'wk:end')) : fc.constant(null)).map((x) => [t, s, e, x]));

test('measure.webkit.tally', () => differential(core, {
  op: 'measure.webkit.tally',
  arb: fc.record({ rows: fc.array(row(half(0, 30)), { maxLength: 20 }) }),
  ts: ({ rows }) => tally(rows),
}));

test('measure.webkit.reduceSteps', () => differential(core, {
  op: 'measure.webkit.reduceSteps',
  arb: risingHalves(1, 6).chain((marks) => fc.record({
    marks: fc.constant(marks),
    endTime: half(marks[marks.length - 1], marks[marks.length - 1] + 10),
    rows: fc.array(row(half(-2, marks[marks.length - 1] + 12)), { maxLength: 25 }),
  })),
  ts: ({ rows, marks, endTime }) => reduceSteps(rows, marks, endTime),
}));

test('measure.webkit.zones', () => differential(core, {
  op: 'measure.webkit.zones',
  arb: fc.array(half(0, 3000), { maxLength: 8 }).chain((ys) => fc.record({
    ys: fc.constant(ys),
    perStep: fc.array(fc.array(int(0, 9), { maxLength: 12 }), { minLength: ys.length, maxLength: ys.length }),
    perStepPaintArea: fc.array(int(0, 99), { minLength: ys.length, maxLength: ys.length }),
    zonePx: fc.option(int(50, 800), { nil: undefined }),
  })),
  ts: ({ ys, perStep, perStepPaintArea, zonePx }) => ({ zones: zonePx === undefined ? zones(ys, perStep, perStepPaintArea) : zones(ys, perStep, perStepPaintArea, zonePx) }),
}));

const word = fc.constantFrom('a', 'b', 'c', 'd');
test('measure.symDiff', () => differential(core, {
  op: 'measure.symDiff',
  arb: fc.record({ a: fc.array(word, { maxLength: 8 }), b: fc.array(word, { maxLength: 8 }) }),
  ts: ({ a, b }) => ({ symDiff: symDiff(a, b) }),
}));

test('measure.summarize', () => differential(core, {
  op: 'measure.summarize',
  arb: fc.record({ rows: fc.array(fc.record({
    cls: fc.constantFrom('deterministic', 'stable', 'quarantined'),
    family: fc.constantFrom('scroll', 'census'),
    level: fc.constantFrom('total', 'per step', 'per zone'),
    metric: fc.constantFrom('Layout', 'Paint', 'layerCount'),
  }), { maxLength: 10 }) }),
  ts: ({ rows }) => ({ summary: summarize(rows).map(({ family, metric, levels, worst }) => ({ family, metric, levels, worst })) }),
}));

const tol = fc.record({ absTol: int(0, 3), relTol: fc.constantFrom(0, 0.02, 0.05, 0.1, 0.5) });
const runsEq = fc.tuple(int(0, 6), int(2, 4)).chain(([len, n]) => fc.array(fc.array(int(0, 40), { minLength: len, maxLength: len }), { minLength: n, maxLength: n }));

test('measure.classify (cells)', () => differential(core, {
  op: 'measure.classify',
  arb: fc.record({ mode: fc.constant('cells'), runs: runsEq, tol }),
  ts: ({ runs, tol: t }) => classify(runs, t),
  project: sameKeys, // Lean also reports the frame-sense maxima k and t
}));

test('measure.classify (cells, run lengths differ)', () => differential(core, {
  op: 'measure.classify',
  arb: fc.record({ mode: fc.constant('cells'), runs: fc.array(fc.array(int(0, 40), { maxLength: 5 }), { minLength: 2, maxLength: 3 }), tol }),
  ts: ({ runs, tol: t }) => classify(runs, t),
  project: sameKeys,
}));

test('measure.quietSteps', () => differential(core, {
  op: 'measure.quietSteps',
  arb: fc.record({
    limit: int(0, 100),
    minKept: int(0, 4),
    tol,
    durs: fc.array(fc.array(int(0, 100), { maxLength: 6 }), { minLength: 1, maxLength: 4 }),
    series: fc.array(fc.record({ type: fc.constantFrom('a', 'b', 'c'), runs: fc.array(fc.array(int(0, 6), { maxLength: 6 }), { minLength: 2, maxLength: 3 }) }), { maxLength: 3 }),
  }),
  ts: (q) => quietReply(q),
}));
