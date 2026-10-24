import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MIN_OPEN_MILLI, geometryIndex, acceptScrollIn, classify } from '../src/lag/phase.mjs';
import { jobVerdicts, tally } from '../src/lag/reduce.mjs';
import { analyzeArm } from '../src/lag/report.mjs';
import { reduceSteps } from '../src/reduce.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/webkit-lag.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('geometryIndex agrees with every golden case', () => {
  const cases = of('geometryIndex');
  assert.ok(cases.length >= 10);
  for (const g of cases) assert.equal(geometryIndex(g.start, g.i, g.n), g.index, JSON.stringify(g));
  assert.ok(cases.some((g) => g.start + g.i >= g.n) && cases.some((g) => g.start + g.i < g.n));
});

test('acceptScrollIn agrees with every golden case, each refusal is covered', () => {
  assert.equal(MIN_OPEN_MILLI, of('scrollInConst')[0].minOpenMilli);
  const cases = of('scrollIn');
  for (const g of cases) {
    const o = acceptScrollIn(classify(g.marks, g.down, g.up), g.startY, g.pushY, g.morphMilli);
    assert.equal(o.outcome, g.outcome, JSON.stringify([g.startY, g.pushY, g.morphMilli, g.down, g.up]));
    if (g.outcome === 'ok') assert.deepEqual([o.idle, o.open, o.close], [g.idle, g.open, g.close]);
  }
  for (const o of ['ok', 'noScroll', 'noOpen', 'noUp', 'openShort']) assert.ok(cases.some((g) => g.outcome === o), o);
});

test('jobVerdicts and tally agree with every golden case, one verdict per job', () => {
  const cases = of('jobVerdicts');
  assert.ok(cases.length >= 5);
  for (const g of cases) {
    const jobs = g.jobs.map((j) => ({ a: j.a, b: j.b }));
    const vs = jobVerdicts(jobs);
    assert.deepEqual(vs, g.verdicts);
    assert.deepEqual(tally(vs), { lower: g.lower, higher: g.higher, overlap: g.overlap });
  }
});

const quad = (x0, y0, x1, y1) => [x0, y0, x1, y0, x1, y1, x0, y1];

function morphOf(idle, open, frames = 130) {
  const rows = [], marks = [];
  for (let k = 0; k < frames; k++) {
    marks.push(k);
    rows.push(['TimeStamp', k, null, `wk:s${k}`]);
    if (k >= idle && k < idle + open) { rows.push(['Layout', k + 0.5, null, null]); rows.push(['Paint', k + 0.6, null, quad(0, 500, 12, 515)]); }
  }
  rows.push(['TimeStamp', frames, null, 'wk:end']);
  return { info: { vw: 100, vh: 100, maxY: 1000 }, marks, endTime: frames, records: rows, reduced: reduceSteps(rows, marks, frames), phases: { down: idle - 0.5, up: idle + open - 0.5 }, taken: [true, true], scrollTo: 0, before: { morph: '0' }, after: { morph: '0' } };
}

function arm(runs, samples) {
  const ys = [0, 50, 100, 150, 300, 500, 800, 900, 1000];
  const info = { vw: 100, vh: 100, maxY: 1000 };
  const rows = ys.map((_, k) => ['TimeStamp', k, null, `wk:s${k}`]).concat([['TimeStamp', ys.length, null, 'wk:end']]);
  const m = ys.map((_, k) => k);
  const scroll = { info, ys, marks: m, endTime: ys.length, records: rows, reduced: reduceSteps(rows, m, ys.length) };
  const here0 = [{ name: 'platform', rect: [0, 400, 400, 4000] }];
  const geometry = {
    info, ys, census: [{ scrollY: 0, layerCount: 1, memoryBytes: 1, filterLayers: [] }], scroll: ys.map(() => ({ boxes: here0, filters: [] })),
    morph: { before: { morph: '0' }, after: { morph: '0' }, samples: Array.from({ length: samples }, (_, k) => ({ boxes: [{ name: `g${k}`, rect: [0, 1900, 100, 2100] }], filters: [] })) },
  };
  return analyzeArm([{ geometry, passes: runs.map((morph) => ({ scroll, morph })) }]).morph;
}

test('a run whose marks are off the 10/60/60 schedule reads the geometry sample of its own frame', () => {
  const a = arm([morphOf(13, 57)], 130);
  assert.equal(a.passes, 1);
  const open = a.phases.open.top;
  assert.ok(open.length > 0);
  for (const t of open) assert.equal(t.part, `g${13 + t.y}`, `open frame ${t.y}`);
  assert.deepEqual([...new Set(open.map((t) => t.part))].every((p) => !/^g(10|11|12)$/.test(p)), true);
});

test('past the last geometry sample the last sample is held', () => {
  const a = arm([morphOf(13, 57)], 14);
  assert.ok(a.phases.open.top.length > 0);
  for (const t of a.phases.open.top) assert.equal(t.part, `g${Math.min(13 + t.y, 13)}`);
});
